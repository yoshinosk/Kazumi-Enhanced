import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/magnet/libtorrent_engine.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/magnet/tracker_updater.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 磁力下载服务：基于 libtorrent_flutter（进程内引擎）维护本地任务索引，
/// 并管理引擎启停、Tracker 自动更新。
///
/// 任务索引持久化在设置盒子中（JSON 字符串），重启后仍能恢复 torrent 标识，
/// 并在引擎会话就绪时自动重挂磁力 / 种子。
class MagnetDownloadService {
  MagnetDownloadService();

  final LibtorrentEngine _engine = LibtorrentEngine();

  Timer? _trackerTimer;
  Dio? _dio;

  bool _initialized = false;
  bool _disposed = false;

  /// 重启恢复阶段置位：期间忽略状态流，避免用旧的 gid 匹配到错误任务。
  bool _reconciling = false;

  /// 进度持久化节流：距上次保存超过该间隔才写一次设置，避免高频写盘。
  static const Duration _progressSaveInterval = Duration(seconds: 10);

  /// 状态轮询兜底定时器：引擎状态流之外定期拉取快照，保证进度/速度
  /// 持续刷新到 UI（插件流去重 / 订阅断档时的兜底）。
  Timer? _refreshTimer;
  static const Duration _refreshInterval = Duration(seconds: 2);

  /// 最近一次进度持久化时间。
  DateTime? _lastProgressSaveAt;

  /// 内置引擎状态变化回调（供 Controller 刷新 observable）。
  void Function(LibtorrentEngineState state)? onEngineStateChanged;

  LibtorrentEngine get engine => _engine;
  LibtorrentEngineState get engineState => _engine.state;

  /// 是否可用（设置中启用了引擎）。
  bool get engineEnabled => LibtorrentEngine.enabledBySettings;

  /// 当前内存中的任务快照，由 torrent 状态流维护。
  final List<MagnetDownloadEntry> _entries = [];
  List<MagnetDownloadEntry> get entries => List.unmodifiable(_entries);

  /// 状态变化回调，供 Controller 注册以驱动 MobX observable。
  void Function(List<MagnetDownloadEntry>)? onChanged;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadEntries();
    // 立即推送已加载的任务：当所有任务都已完成（或引擎未启用）时，
    // 引擎状态流不会有任何事件，UI 收不到首次刷新，列表会一直为空，
    // 表现为“重启后已完成任务消失”。
    onChanged?.call(_entries);
    _engine.onStateChanged = (state) => onEngineStateChanged?.call(state);
    _engine.onTorrents = _onTorrents;

    // 启用时随应用启动引擎。
    if (LibtorrentEngine.enabledBySettings && LibtorrentEngine.supported) {
      final ok = await _engine.start();
      if (ok) {
        _onTorrents(LibtorrentFlutter.instance.torrents);
        await _reconcileWithEngine();
      }
    }
    _startTrackerScheduler();
    _startRefreshScheduler();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _trackerTimer?.cancel();
    _trackerTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    // 退出前持久化一次进度，供下次启动断点续传时恢复显示。
    await _saveEntries();
    await _engine.dispose();
  }

  /// 手动启动内置引擎。
  Future<bool> startEngine() async {
    final ok = await _engine.start();
    if (ok) {
      _onTorrents(LibtorrentFlutter.instance.torrents);
      await _reconcileWithEngine();
    }
    _startRefreshScheduler();
    return ok;
  }

  Future<void> stopEngine() async {
    await _engine.stop();
  }

  /// 立即更新 tracker 列表；成功返回数量，失败返回 -1。
  Future<int> updateTrackers() async {
    return TrackerUpdater.instance.update();
  }

  /// 当前缓存 tracker 数量。
  int get cachedTrackerCount => TrackerUpdater.instance.cachedTrackers().length;

  /// 最近一次 tracker 更新时间。
  DateTime? get trackerLastUpdated => TrackerUpdater.instance.lastUpdated();

  /// 当设置中的引擎相关开关变化时调用。
  Future<void> applySettingsChanged() async {
    await _engine.applySettingsChanged();
    _startTrackerScheduler();
    _startRefreshScheduler();
  }

  /// Tracker 自动更新调度。
  void _startTrackerScheduler() {
    _trackerTimer?.cancel();
    _trackerTimer = null;
    if (!GStorage.getSetting(SettingsKeys.magnetTrackerAutoUpdate)) return;

    final last = TrackerUpdater.instance.lastUpdated();
    final hours = GStorage.getSetting(SettingsKeys.magnetTrackerUpdateHours);
    var delay = (last == null)
        ? const Duration(seconds: 5)
        : last.add(Duration(hours: hours)).difference(DateTime.now());
    if (delay.isNegative) delay = Duration.zero;
    if (delay > const Duration(days: 1)) delay = const Duration(days: 1);
    _trackerTimer = Timer(delay, () async {
      await TrackerUpdater.instance.update();
      _startTrackerScheduler();
    });
  }

  /// 状态轮询兜底调度：周期性拉取引擎快照刷新任务索引与 UI。
  ///
  /// 引擎状态流由插件侧去重（字段不全时可能不推送），且订阅一旦断档
  /// 便不再更新；这里以固定间隔兜底，保证下载进度能实时刷到界面。
  void _startRefreshScheduler() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => refresh());
  }

  // ---------------- 任务索引持久化 ----------------

  Future<void> _loadEntries() async {
    final raw = GStorage.getSetting(SettingsKeys.magnetDownloadEntries);
    if (raw.isEmpty) {
      _entries.clear();
      return;
    }
    try {
      final list = jsonDecode(raw) as List;
      _entries
        ..clear()
        ..addAll(list.map((e) => MagnetDownloadEntry.fromJson(
            Map<String, dynamic>.from(e as Map))));
    } catch (e) {
      KazumiLogger().w('MagnetDownloadService: load entries failed', error: e);
      _entries.clear();
    }
  }

  Future<void> _saveEntries() async {
    final json = _entries.map((e) => e.toJson()).toList();
    await GStorage.putSetting(
      SettingsKeys.magnetDownloadEntries,
      jsonEncode(json),
    );
  }

  /// 引擎会话新建（如重启后）时，为尚未挂载的任务重新提交磁力 / 种子。
  ///
  /// 恢复期间置位 [_reconciling]，让 [_onTorrents] 暂时忽略状态流，
  /// 防止旧 gid（上一会话的 torrent 序号）在重挂过程中匹配到新会话里
  /// 序号相同但内容不同的任务，造成进度/状态错乱。
  Future<void> _reconcileWithEngine() async {
    if (!LibtorrentFlutter.isInitialized) return;
    _reconciling = true;
    try {
      final existing = LibtorrentFlutter.instance.torrents;
      var changed = false;
      final reconciled = <MagnetDownloadEntry>[];
      for (final entry in _entries) {
        final id = int.tryParse(entry.gid);
        if (id != null && existing.containsKey(id)) {
          reconciled.add(entry);
          continue;
        }
        // 已完成 / 做种中任务的重挂策略：
        // - 原生引擎支持「重挂自动校验磁盘」（LibtorrentFlutter.resumeAware，
        //   即 no_recheck_incomplete_resume=false 的重编版本）且磁盘文件完整
        //   → 重挂，引擎校验后直接做种，不重下文件；
        // - 否则（当前 prebuilt 引擎 / 文件已丢失）→ 保持静态记录，
        //   避免整文件重下和假下载速度。
        //
        // 另：磁盘数据已完整（verified ≈ total）但状态仍是 active 的任务
        // （完成瞬间进程退出、完成态未落盘）同样保持静态——重挂只会让
        // 引擎从头重下已完整的文件，徒增带宽与假下载速度。
        final bool resumeCapable = LibtorrentFlutter.resumeAware;
        final bool activeish =
            entry.status != 'complete' && entry.status != 'seeding';
        final bool essentiallyDone = entry.totalLength > 0 &&
            entry.verifiedLength >= entry.totalLength;
        // 已完成任务（做种停止条件已满足）不再重挂；做种中任务在
        // 引擎支持校验且文件完整时重挂以续做种。
        final bool shouldRemount = resumeCapable
            ? (activeish ||
                (entry.status == 'seeding' && _isFileIntact(entry)))
            : (activeish && !essentiallyDone);
        if (!shouldRemount) {
          reconciled.add(entry);
          continue;
        }
        final newId = await _engineAdd(entry.sourceUri,
            savePath: entry.savePath.isNotEmpty
                ? entry.savePath
                : await LibtorrentEngine.resolveDownloadDir());
        if (newId != null && newId.isNotEmpty) {
          entry.gid = newId;
          if (entry.status == 'complete' || entry.status == 'seeding') {
            // 续做种重挂：引擎将校验磁盘（checking 期 totalDone 从 0
            // 爬升是校验而非下载），标记 _reseed 让 UI 保持 100% 显示；
            // 记录历史上传基数，做种率 = 基数 + 本会话新增上传。
            entry._reseed = true;
            entry._uploadBase = entry.totalUploaded;
            entry._restartFloor = null;
          } else {
            // 未完成任务：维持重启恢复混合基线（引擎校验生效前作为
            // 兜底；校验生效后 _wasRestoring 会以真实字节对齐）。
            entry._reseed = false;
            entry._uploadBase = 0;
            entry._restartFloor = entry.totalLength > 0
                ? (entry.verifiedLength / entry.totalLength).clamp(0.0, 1.0)
                : 0.0;
          }
          reconciled.add(entry);
          changed = true;
        } else {
          // 重挂失败：保留原记录，避免用户数据丢失。
          reconciled.add(entry);
        }
      }
      if (changed) {
        _entries
          ..clear()
          ..addAll(reconciled);
        await _saveEntries();
        onChanged?.call(_entries);
      }
    } finally {
      _reconciling = false;
    }
  }

  @visibleForTesting
  static bool isFileIntactForTest(MagnetDownloadEntry entry) =>
      _isFileIntact(entry);

  /// 判断任务的主文件是否仍完整存在于磁盘上（重挂续做种的守卫）。
  ///
  /// 以 `savePath/fileName` 的存在性为准；文件被改名 / 移走会保守地
  /// 判定为缺失（保持静态记录，不触发重挂重下）。
  static bool _isFileIntact(MagnetDownloadEntry entry) {
    if (entry.savePath.isEmpty || entry.fileName.isEmpty) return false;
    return File(p.join(entry.savePath, entry.fileName)).existsSync();
  }

  // ---------------- 任务操作 ----------------

  /// 提交磁力 / 种子链接到引擎。
  ///
  /// [dir] 指定下载目录，留空则使用引擎默认目录。
  /// 返回 torrent 标识；若引擎不可用则返回空字符串。
  Future<String> add(MagnetSearchItem item, {String? dir}) async {
    // 引擎未运行则先尝试启动。
    if (LibtorrentEngine.enabledBySettings &&
        LibtorrentEngine.supported &&
        !_engine.isRunning) {
      final ok = await _engine.start();
      if (!ok) return '';
    }
    if (!LibtorrentFlutter.isInitialized) {
      KazumiLogger()
          .w('MagnetDownloadService: engine not initialized, cannot add');
      return '';
    }
    final uri = item.magnetLink.isNotEmpty ? item.magnetLink : item.torrentUrl;
    if (uri.isEmpty) {
      KazumiLogger().w('MagnetDownloadService: empty magnet and torrent url');
      return '';
    }
    final savePath = (dir != null && dir.trim().isNotEmpty)
        ? dir.trim()
        : await LibtorrentEngine.resolveDownloadDir();
    final gid = await _engineAdd(uri, savePath: savePath);
    if (gid == null || gid.isEmpty) return '';
    final entry = MagnetDownloadEntry(
      gid: gid,
      title: item.title,
      sourceUri: uri,
      savePath: savePath,
      addedAt: DateTime.now(),
    );
    _entries.insert(0, entry);
    await _saveEntries();
    onChanged?.call(_entries);
    return gid;
  }

  Future<bool> pause(String gid) async {
    final id = int.tryParse(gid);
    if (id == null || !LibtorrentFlutter.isInitialized) return false;
    LibtorrentFlutter.instance.pauseTorrent(id);
    _find(gid)?.status = 'paused';
    onChanged?.call(_entries);
    return true;
  }

  Future<bool> unpause(String gid) async {
    final id = int.tryParse(gid);
    if (id == null || !LibtorrentFlutter.isInitialized) return false;
    LibtorrentFlutter.instance.resumeTorrent(id);
    await refresh();
    return true;
  }

  Future<bool> remove(String gid) async {
    final id = int.tryParse(gid);
    if (id == null || !LibtorrentFlutter.isInitialized) return false;
    // 仅移除任务，保留已下载文件。
    LibtorrentFlutter.instance.removeTorrent(id, deleteFiles: false);
    _entries.removeWhere((e) => e.gid == gid);
    await _saveEntries();
    onChanged?.call(_entries);
    return true;
  }

  /// 重新拉取所有任务的实时状态。
  Future<void> refresh() async {
    if (!LibtorrentFlutter.isInitialized) return;
    _onTorrents(LibtorrentFlutter.instance.torrents);
  }

  /// 测试引擎是否可用，返回 libtorrent 版本或 null。
  Future<String?> ping() async {
    if (!LibtorrentFlutter.isInitialized) return null;
    final version = LibtorrentFlutter.instance.libraryVersion;
    return version.isEmpty ? 'engine' : version;
  }

  MagnetDownloadEntry? _find(String gid) {
    for (final e in _entries) {
      if (e.gid == gid) return e;
    }
    return null;
  }

  /// 进度平滑：允许估算值领先已验证字节的时间窗口（秒）。
  static const double _progressInFlightSec = 3;

  /// 把引擎状态快照同步进任务索引。
  void _onTorrents(Map<int, TorrentInfo> torrents) {
    if (_reconciling) return;
    final now = DateTime.now();
    final seedingStopMode =
        GStorage.getSetting(SettingsKeys.magnetSeedingStopMode);
    final seedingStopRatio =
        GStorage.getSetting(SettingsKeys.magnetSeedingStopRatio);
    final seedingStopHours =
        GStorage.getSetting(SettingsKeys.magnetSeedingStopHours);
    var changed = false;
    for (final entry in _entries) {
      final id = int.tryParse(entry.gid);
      if (id == null) continue;
      final t = torrents[id];
      if (t == null) continue;
      final status = _mapStatus(t);
      final prevStatus = entry.status;
      applyTorrentStatus(
        entry,
        t,
        status,
        now,
        seedingStopMode: seedingStopMode,
        seedingStopRatio: seedingStopRatio,
        seedingStopHours: seedingStopHours,
      );
      // 做种状态流转：
      if (entry.status != prevStatus) {
        if (entry.status == 'seeding') {
          // 进入做种：记录开始时间（跨重启保留，不覆盖已有值）
          entry.seedingStartedAt ??= now;
        } else if (entry.status == 'complete') {
          // 进入已完成（从任意非完成状态）：做种停止条件已满足
          // （分享率达标 / 做种时长到 / 下载完成时分享率即达标），
          // 从引擎移除任务停止上传，保留已下载文件。
          // 注意：下载完成时分享率可能已达标，状态会从 active 直接
          // 变为 complete 而不经过 seeding，因此不能只匹配
          // prevStatus == 'seeding'。
          try {
            LibtorrentFlutter.instance.removeTorrent(id, deleteFiles: false);
          } catch (e) {
            KazumiLogger().w(
                'MagnetDownloadService: stop seeding failed',
                error: e);
          }
        }
      }
      // 关键状态切换立即持久化，避免进程退出 / 崩溃时把状态丢掉。
      if (prevStatus != entry.status &&
          (entry.status == 'complete' ||
              entry.status == 'seeding' ||
              entry.status == 'paused' ||
              entry.status == 'error')) {
        unawaited(_saveEntries());
      }
      changed = true;
    }
    // 已完成任务前置，便于 UI 展示。
    if (changed) {
      _entries.sort((a, b) {
        final aDone = a.status == 'complete';
        final bDone = b.status == 'complete';
        if (aDone != bDone) return aDone ? 1 : -1;
        return a.addedAt.compareTo(b.addedAt) * -1;
      });
      onChanged?.call(_entries);
      _maybePersistProgress(now);
    }
  }

  /// 做种停止策略（对应 SettingsKeys.magnetSeedingStopMode）。
  static const String seedingStopNone = 'none';
  static const String seedingStopTime = 'time';
  static const String seedingStopRatio = 'ratio';

  /// 做种时间模式判定：自 [startedAt] 起做种未满 [hours] 小时返回 true。
  ///
  /// [startedAt] 为 null（尚未记录开始时间，如任务刚完成）时视为
  /// 仍在做种期内，由 [_onTorrents] 在进入做种时补记。
  static bool _seedingWithinDuration(
      DateTime? startedAt, int hours, DateTime now) {
    if (startedAt == null) return true;
    return now.isBefore(startedAt.add(Duration(hours: hours)));
  }

  /// 把单条引擎状态应用到任务索引（纯函数，便于测试）。
  ///
  /// 进度口径：
  /// - 引擎拿到元数据前 `totalWanted / totalDone` 恒为 0，不能采纳，
  ///   否则会把持久化的总大小 / 进度清零（重启后重新拉取元数据期间
  ///   任务会显示 0%，且节流保存会把 0 写盘导致进度永久丢失）。
  /// - 重启恢复（[_restartFloor] 已置位）时，引擎无法校验磁盘已有数据、
  ///   会从零重新下载：展示进度按「恢复基线 + 剩余部分随引擎推进」
  ///   混合，避免进度瞬间归零，也避免卡在旧值不动。
  /// - 同一会话内的任务沿用「已验证字节 + 速度平滑」口径，校验 / 取
  ///   元数据期间保留上次进度，完成后对齐总量。
  ///
  /// [seedingStopMode] / [seedingStopRatio] / [seedingStopHours] 为做种
  /// 停止策略（默认按分享率 1.0，与历史行为一致）。
  @visibleForTesting
  static void applyTorrentStatus(
    MagnetDownloadEntry entry,
    TorrentInfo t,
    String status,
    DateTime now, {
    String seedingStopMode = seedingStopRatio,
    double seedingStopRatio = 1.0,
    int seedingStopHours = 24,
  }) {
    entry
      ..downloadSpeed = t.downloadRate
      ..uploadSpeed = t.uploadRate
      ..numSeeds = t.numSeeds
      ..numPeers = t.numPeers;
    // 上传量跨会话累计：续做种重挂时以 _uploadBase（历史累计）为基数，
    // 叠加本会话引擎从 0 起计的新增上传；未重挂的任务取历史与当前最大值。
    if (entry._uploadBase > 0) {
      entry.totalUploaded = entry._uploadBase + t.totalUploaded;
    } else if (t.totalUploaded > entry.totalUploaded) {
      entry.totalUploaded = t.totalUploaded;
    }
    // 用最新上传量判定：引擎完成下载后按做种停止策略决定做种中 / 已完成。
    if (status == 'complete') {
      final shouldSeed = switch (seedingStopMode) {
        seedingStopNone => true, // 不自动停止，一直做种
        seedingStopTime => _seedingWithinDuration(
            entry.seedingStartedAt, seedingStopHours, now),
        _ => entry.seedRatio < seedingStopRatio, // 分享率未达阈值
      };
      if (shouldSeed) {
        status = 'seeding';
      }
    }
    entry.status = status;
    final isRestoring = status == 'checking' || status == 'metadata';
    // 元数据未就绪时引擎上报 totalWanted / totalDone 恒为 0，保留旧值。
    // 总量只增不减：避免元数据总量修正或未来文件选择（总量变小）时
    // 进度百分比突变或出现假 100%。
    if (t.hasMetadata && t.totalWanted > 0) {
      final old = entry.totalLength;
      entry.totalLength = old > t.totalWanted ? old : t.totalWanted;
    }
    if (entry._reseed && isRestoring) {
      // 续做种校验期：引擎正在校验磁盘（totalDone 从 0 爬升是校验
      // 进度而非下载），保持 100% 显示、不采纳引擎的 verifiedLength、
      // 不显示下载速度。
      entry.completedLength = entry.totalLength;
      entry.verifiedLength = entry.totalLength;
      entry.downloadSpeed = 0;
    } else if (status == 'complete' || status == 'seeding') {
      // 下载已完成：对齐总量（做种中同样对齐——下载确实完成，只是
      // 上传任务未达标），避免平滑估算低于总量卡在 99.x%。
      if (entry.totalLength > 0) {
        entry.completedLength = entry.totalLength;
        entry.verifiedLength = entry.totalLength;
      }
      // 完成后引擎仍会上报残留的下载速率（实测完成后的几分钟内
      // 仍可达数 MB/s），清零避免「已完成 / 做种中」任务继续显示
      // 下载速度；做种上传速度保留展示。
      entry.downloadSpeed = 0;
      // 已完成任务已从引擎移除停止做种，不再有上传活动：
      // 清掉最后一次上报的上传速度，避免「已完成」任务长期显示
      // 残留的做种上传速度。
      if (status == 'complete') {
        entry.uploadSpeed = 0;
      }
    } else if (status == 'error') {
      entry.downloadSpeed = 0;
      entry.uploadSpeed = 0;
    } else if (entry._restartFloor != null && entry.totalLength > 0) {
      // 重启恢复混合进度：磁盘上已有 floor 比例的合法数据（引擎无法
      // 校验，只能从零重下），剩余部分随引擎已验证字节线性推进。
      final floor = entry._restartFloor!;
      final engineRatio = (t.totalDone / entry.totalLength).clamp(0.0, 1.0);
      final blended = floor + (1 - floor) * engineRatio;
      // 完成前持久化值永不等于总量（封顶 total-1）：引擎接近下完但
      // 未 complete 时 blend 趋近 1，直接写盘会让重启 floor 变成 1，
      // 任务在整个重下期间显示 100% 而磁盘实际缺片（假 100%）。
      final target = (blended * entry.totalLength)
          .round()
          .clamp(0, entry.totalLength - 1)
          .toInt();
      entry.verifiedLength = target;
      // 复用速度平滑：展示进度按下载速度连续推进，消除片级跳变；
      // 必须传入封顶后的 target，避免 completedLength 对齐回虚高值。
      _smoothProgress(entry, target, t.downloadRate, now);
      // 恢复期（引擎在重下磁盘上已有的数据，展示进度明显领先于引擎
      // 原始进度）不显示下载速度——这段“下载”只是补回已有数据的
      // 浪费带宽，对用户无意义且易被误读为“又在下整个文件”。
      // 引擎进度追近展示进度后恢复显示。
      if (blended - engineRatio > 0.1) {
        entry.downloadSpeed = 0;
      }
    } else if (t.hasMetadata) {
      // totalDone 仅在元数据就绪后才有意义。
      if (isRestoring) {
        // 重新校验 / 获取元数据期间保留上次已知进度，避免被“校验进度（从 0 起）”
        // 打回 0；同时标记“恢复中”，待恢复结束以引擎校验结果一次性对齐。
        entry._progressSampleAt = now;
        entry._wasRestoring = true;
      } else {
        if (entry._wasRestoring) {
          // 校验完成：以引擎重新校验出的真实字节对齐，消除恢复阶段的进度跳变。
          entry.completedLength = t.totalDone;
          entry._wasRestoring = false;
        }
        entry.verifiedLength = t.totalDone;
        _smoothProgress(entry, t.totalDone, t.downloadRate, now);
      }
    }
    // 校验结束（进入做种 / 下载 / 其他终态）后清除续做种标记，
    // 恢复正常进度口径。
    if (entry._reseed && !isRestoring) {
      entry._reseed = false;
    }
    if (entry.fileName.isEmpty && t.name.isNotEmpty) entry.fileName = t.name;
    if (t.savePath.isNotEmpty) entry.savePath = t.savePath;
  }

  /// 节流持久化任务进度，避免进程被杀时丢失过多进度。
  void _maybePersistProgress(DateTime now) {
    final last = _lastProgressSaveAt;
    if (last != null && now.difference(last) < _progressSaveInterval) return;
    _lastProgressSaveAt = now;
    unawaited(_saveEntries());
  }

  /// 平滑已完成字节数。
  ///
  /// 引擎的 `total_done` 只统计「整片已校验」的字节，会按片大小（常见 16MB）
  /// 呈 16 → 32 → 48 跳变。这里用两次状态轮询之间的下载速度估算已入队字节，
  /// 让进度连续推进。
  ///
  /// 进度只前进不回退：估算值不超过「已验证字节 + 在途窗口」时按速度推进，
  /// 超出则暂停等待校验追上；整片校验完成（verified 跳变）时向上对齐。
  static void _smoothProgress(
      MagnetDownloadEntry entry, int verifiedBytes, int rate, DateTime now) {
    final last = entry._progressSampleAt;
    if (last != null) {
      final dt = now.difference(last).inMilliseconds / 1000.0;
      if (dt > 0 && rate > 0) {
        final candidate = entry.completedLength + (rate * dt).round();
        final cap = verifiedBytes + (rate * _progressInFlightSec).round();
        if (candidate <= cap) {
          entry.completedLength = candidate;
        }
      }
    }
    entry._progressSampleAt = now;
    if (entry.completedLength < verifiedBytes) {
      entry.completedLength = verifiedBytes;
    }
    if (entry.totalLength > 0 && entry.completedLength > entry.totalLength) {
      entry.completedLength = entry.totalLength;
    }
  }

  /// 映射任务状态。
  ///
  /// libtorrent_flutter 的 `stateFromInt` 与原生 libtorrent 状态枚举存在一位偏移：
  /// 原生 checking_files(1) 上报为 [TorrentState.downloadingMetadata]、
  /// downloading_metadata(2) 上报为 [TorrentState.downloading]、
  /// downloading(3) 上报为 [TorrentState.finished]……本方法据此还原真实状态。
  ///
  /// 返回：waiting / metadata / checking / active / paused / complete / error。
  /// 完成态不依赖 state，改用 progress + isFinished（原生侧计算可靠）。
  String _mapStatus(TorrentInfo t) {
    if (t.isPaused) return 'paused';
    if (t.isFinished && t.progress >= 0.999) return 'complete';
    switch (t.state) {
      case TorrentState.error:
        return 'error';
      case TorrentState.downloadingMetadata:
        // 原生 checking_files：重新校验磁盘上已有数据（重启断点续传必经状态）。
        return t.hasMetadata ? 'checking' : 'waiting';
      case TorrentState.downloading:
        // 原生 downloading_metadata：磁力链接正在获取元数据。
        return t.hasMetadata ? 'active' : 'metadata';
      case TorrentState.checkingFiles:
      case TorrentState.checkingResume:
      case TorrentState.unknown:
        // 原生 queued_for_checking / allocating / checking_resume_data。
        return t.hasMetadata ? 'checking' : 'waiting';
      default:
        return 'active';
    }
  }

  // ---------------- 引擎调用 ----------------

  /// 把磁力 / 种子提交给引擎，返回 torrent 标识；失败返回 null。
  Future<String?> _engineAdd(String uri, {String? savePath}) async {
    if (!LibtorrentFlutter.isInitialized) return null;
    final engine = LibtorrentFlutter.instance;
    final trimmed = uri.trim();
    final int id;
    try {
      if (trimmed.toLowerCase().startsWith('magnet:')) {
        id = engine.addMagnet(trimmed, savePath);
      } else if (trimmed.toLowerCase().startsWith('http://') ||
          trimmed.toLowerCase().startsWith('https://')) {
        final torrentPath = await _downloadTorrent(trimmed);
        if (torrentPath == null) return null;
        id = engine.addTorrentFile(torrentPath, savePath);
      } else {
        id = engine.addTorrentFile(trimmed, savePath);
      }
    } catch (e) {
      // 重复添加 / 引擎异常都会抛错：返回 null，保留原记录。
      KazumiLogger().w('MagnetDownloadService: engine add failed', error: e);
      return null;
    }
    return '$id';
  }

  /// 下载 .torrent 到临时目录，返回本地路径。
  Future<String?> _downloadTorrent(String url) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File(p.join(
        tempDir.path,
        'kazumi_${DateTime.now().millisecondsSinceEpoch}.torrent',
      ));
      await _http.download(url, file.path);
      return await file.exists() ? file.path : null;
    } catch (e) {
      KazumiLogger().w('MagnetDownloadService: download torrent failed', error: e);
      return null;
    }
  }

  Dio get _http {
    return _dio ??= _createHttpClient();
  }

  Dio _createHttpClient() {
    final cfg = NetworkConfig.fromSettings(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    );
    final dio = Dio();
    dio.options.connectTimeout = cfg.connectTimeout;
    dio.options.receiveTimeout = cfg.receiveTimeout;
    dio.httpClientAdapter = cfg.createAdapter();
    return dio;
  }
}

/// 本地缓存的下载任务索引。状态字段随引擎状态流转更新。
class MagnetDownloadEntry {
  MagnetDownloadEntry({
    required this.gid,
    required this.title,
    required this.sourceUri,
    required this.addedAt,
    this.savePath = '',
    this.status = 'waiting',
    this.totalLength = 0,
    this.completedLength = 0,
    this.verifiedLength = 0,
    this.downloadSpeed = 0,
    this.uploadSpeed = 0,
    this.totalUploaded = 0,
    this.numSeeds = 0,
    this.numPeers = 0,
    this.fileName = '',
    this.seedingStartedAt,
  });

  String gid;
  final String title;
  final String sourceUri;
  final DateTime addedAt;
  String savePath;
  String status;
  int totalLength;

  /// 展示用已完成字节（含速度平滑估算，可能略领先于磁盘真实值）。
  int completedLength;

  /// 引擎上报的已验证字节（磁盘真实进度）。持久化以此为准，
  /// 重启后用它作为进度恢复基准，避免平滑估算值导致进度跳变。
  int verifiedLength;
  int downloadSpeed;
  int uploadSpeed;
  int totalUploaded;
  int numSeeds;
  int numPeers;
  String fileName;

  /// 进度平滑用的上一次采样时间（不持久化）。
  DateTime? _progressSampleAt;

  /// 是否正处于“校验 / 获取元数据”恢复阶段（不持久化）。
  bool _wasRestoring = false;

  /// 重启恢复基线（0..1，不持久化）：进程重启后引擎无法校验磁盘已有
  /// 数据，会从零重新下载；磁盘上仍保留着上次已验证的数据，展示进度
  /// 按「基线 + 剩余部分随引擎推进」混合，避免进度归零或卡死。
  /// 仅在 [_MagnetDownloadService._reconcileWithEngine] 重挂成功后置位。
  double? _restartFloor;

  /// 续做种重挂标记（不持久化）：已完成 / 做种中任务重挂后，引擎正在
  /// 校验磁盘（checking 期 totalDone 从 0 爬升是校验而非下载），
  /// 期间保持 100% 显示、不采纳引擎的 verifiedLength。
  bool _reseed = false;

  /// 续做种重挂时记录的历史上传基数（不持久化）：做种率 = 基数 +
  /// 本会话引擎新增上传，跨会话累计不重复计数。
  int _uploadBase = 0;

  /// 开始做种的时间（持久化）。做种停止策略为「按时间」时，
  /// 做种满 [SettingsKeys.magnetSeedingStopHours] 小时后停止。
  DateTime? seedingStartedAt;

  @visibleForTesting
  set restartFloorForTest(double? value) => _restartFloor = value;

  @visibleForTesting
  set reseedForTest(bool value) => _reseed = value;

  @visibleForTesting
  set uploadBaseForTest(int value) => _uploadBase = value;

  @visibleForTesting
  set seedingStartedAtForTest(DateTime? value) => seedingStartedAt = value;

  double get progress =>
      totalLength > 0 ? completedLength / totalLength : 0.0;

  /// 做种率：本会话累计上传 / 磁盘真实已下载字节（下载为 0 时返回 0）。
  ///
  /// 分母用 [verifiedLength] 而非含在途估算的 [completedLength]，
  /// 避免下载中做种率偏乐观；完成态两值相等（complete 分支同时对齐），
  /// 行为不变。
  double get seedRatio =>
      verifiedLength > 0 ? totalUploaded / verifiedLength : 0;

  /// 预计剩余秒数；未知（未在下载 / 无速度 / 总大小未知）返回 -1。
  ///
  /// 元数据未就绪时 [totalLength] 为 0，引擎可能仍在上报下载速率
  /// （获取元数据也算流量），此时剩余时间为 0，会误导 UI 显示
  /// 「剩余 0 秒」，因此总大小未知一律返回 -1。
  int get etaSeconds {
    if (totalLength <= 0 || downloadSpeed <= 0) return -1;
    final remaining = totalLength - completedLength;
    if (remaining <= 0) return 0;
    return (remaining / downloadSpeed).ceil();
  }

  bool get isCompleted => status == 'complete';
  bool get isSeeding => status == 'seeding';
  bool get isDownloading =>
      status == 'active' ||
      status == 'waiting' ||
      status == 'checking' ||
      status == 'metadata';
  bool get isActive => isDownloading || isSeeding;
  bool get isPaused => status == 'paused';
  bool get isError => status == 'error' || status == 'removed';

  factory MagnetDownloadEntry.fromJson(Map<String, dynamic> json) {
    // 兼容旧数据：新版本只持久化 verifiedLength，旧版本只有 completedLength。
    final verified = (json['verifiedLength'] as num?)?.toInt() ??
        (json['completedLength'] as num?)?.toInt() ??
        0;
    return MagnetDownloadEntry(
      gid: json['gid'] as String? ?? '',
      title: json['title'] as String? ?? '',
      sourceUri: json['sourceUri'] as String? ?? '',
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
      savePath: json['savePath'] as String? ?? '',
      status: json['status'] as String? ?? 'waiting',
      totalLength: (json['totalLength'] as num?)?.toInt() ?? 0,
      completedLength: verified,
      verifiedLength: verified,
      downloadSpeed: (json['downloadSpeed'] as num?)?.toInt() ?? 0,
      uploadSpeed: (json['uploadSpeed'] as num?)?.toInt() ?? 0,
      totalUploaded: (json['totalUploaded'] as num?)?.toInt() ?? 0,
      numSeeds: (json['numSeeds'] as num?)?.toInt() ?? 0,
      numPeers: (json['numPeers'] as num?)?.toInt() ?? 0,
      fileName: json['fileName'] as String? ?? '',
      seedingStartedAt:
          DateTime.tryParse(json['seedingStartedAt'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'gid': gid,
        'title': title,
        'sourceUri': sourceUri,
        'addedAt': addedAt.toIso8601String(),
        'savePath': savePath,
        'status': status,
        'totalLength': totalLength,
        'completedLength': verifiedLength,
        'verifiedLength': verifiedLength,
        'downloadSpeed': downloadSpeed,
        'uploadSpeed': uploadSpeed,
        'totalUploaded': totalUploaded,
        'numSeeds': numSeeds,
        'numPeers': numPeers,
        'fileName': fileName,
        'seedingStartedAt': seedingStartedAt?.toIso8601String() ?? '',
      };
}