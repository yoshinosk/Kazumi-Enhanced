import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/magnet/libtorrent_engine.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/magnet/tracker_updater.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/disk_space.dart';
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

  /// 元数据获取超时：超过该时长仍未拿到种子元数据则自动重试。
  static const Duration _metadataTimeout = Duration(minutes: 10);

  /// 元数据超时自动重试上限，超出后放弃并标记错误。
  static const int _maxMetadataRetries = 5;

  /// 环境策略调度周期（限速时段 / 仅 WiFi 检查）。
  static const Duration _policyInterval = Duration(minutes: 1);

  /// 限速时段内当前已应用的下载限速（字节/秒，-1 表示未应用）。
  int _appliedScheduledLimitBps = -1;

  /// 最近一次「仅 WiFi」策略判定结果（避免重复暂停 / 恢复）。
  bool? _lastWifiOnlyEnforced;

  /// 添加任务时的可用空间下限：低于该值提示用户（不阻断添加，
  /// 元数据就绪后会按真实大小再校验）。
  static const int _minFreeSpaceForAdd = 300 * 1024 * 1024;

  /// 元数据就绪后保留的磁盘余量：可用空间小于「剩余需下载 + 该余量」时
  /// 自动暂停任务并提示。
  static const int _freeSpaceMargin = 200 * 1024 * 1024;

  /// 最近一次进度持久化时间。
  DateTime? _lastProgressSaveAt;

  /// 当前有活跃边下边播流的任务（不持久化）。这类任务不能被降级 / WiFi
  /// 暂停 / 完成移除打断，否则正在播放的 HTTP 流会断流或卡缓冲。
  final Set<String> _streamingTaskIds = {};

  /// 本次会话内已做过「元数据就绪磁盘空间校验」的任务（不持久化），
  /// 重启后重新校验一次（files 已持久化，不能再用 files.isEmpty 判定）。
  final Set<String> _diskSpaceCheckedTaskIds = {};

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
    _startPolicyScheduler();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _trackerTimer?.cancel();
    _trackerTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _policyTimer?.cancel();
    _policyTimer = null;
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
    final count = await TrackerUpdater.instance.update();
    // 把缓存 tracker 注入引擎会话内的现有任务，让用户配置的
    // tracker 源真正参与下载（libtorrent 按 URL 去重，重复注入安全）。
    if (count > 0 && LibtorrentFlutter.isInitialized) {
      final trackers = _cachedTrackersForEngine();
      if (trackers.isNotEmpty) {
        final engine = LibtorrentFlutter.instance;
        for (final id in engine.torrents.keys) {
          try {
            engine.addTrackers(id, trackers);
          } catch (e) {
            KazumiLogger()
                .w('MagnetDownloadService: add trackers failed', error: e);
          }
        }
      }
    }
    return count;
  }

  /// 当前缓存 tracker 数量。
  int get cachedTrackerCount => TrackerUpdater.instance.cachedTrackers().length;

  /// 最近一次 tracker 更新时间。
  DateTime? get trackerLastUpdated => TrackerUpdater.instance.lastUpdated();

  /// 当设置中的引擎相关开关变化时调用。
  Future<void> applySettingsChanged() async {
    final wasRunning = _engine.isRunning;
    // 限速相关设置变更后立即失效缓存，让新值马上生效（否则最长
    // 延迟一个策略周期 60s）。
    _appliedScheduledLimitBps = -1;
    await _engine.applySettingsChanged();
    _startTrackerScheduler();
    _startRefreshScheduler();
    // 引擎由停用变为启用（或在设置页启动新会话）时，为尚未挂载的
    // 持久化任务重挂，否则历史任务会一直保持静态记录。
    if (!wasRunning && _engine.isRunning) {
      _onTorrents(LibtorrentFlutter.instance.torrents);
      await _reconcileWithEngine();
    }
    // 并发上限等参数变化后重算队列并持久化。
    _reconcileQueue();
    await _saveEntries();
    onChanged?.call(_entries);
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

  // ---------------- 环境策略（限速时段 / 仅 WiFi） ----------------

  Timer? _policyTimer;

  void _startPolicyScheduler() {
    _policyTimer?.cancel();
    _policyTimer = Timer.periodic(_policyInterval, (_) {
      unawaited(_applyEnvironmentPolicies());
    });
    unawaited(_applyEnvironmentPolicies());
  }

  /// 应用环境策略：限速时段内覆盖全局下载限速；「仅 WiFi」开启时
  /// 非 WiFi 网络暂停下载任务、恢复 WiFi 后自动继续。
  Future<void> _applyEnvironmentPolicies() async {
    _applyScheduledLimit();
    await _applyWifiOnlyPolicy();
  }

  void _applyScheduledLimit() {
    if (!LibtorrentFlutter.isInitialized) return;
    final enabled = GStorage.getSetting(SettingsKeys.magnetScheduledLimitEnabled);
    final targetBps = enabled
        ? _scheduledLimitBpsNow()
        : GStorage.getSetting(SettingsKeys.magnetMaxDownloadLimitKb) * 1024;
    if (targetBps == _appliedScheduledLimitBps) return;
    _appliedScheduledLimitBps = targetBps;
    try {
      LibtorrentFlutter.instance.setDownloadLimit(targetBps);
      KazumiLogger().i(
          'MagnetDownloadService: download limit -> ${targetBps ~/ 1024} KiB/s');
    } catch (e) {
      KazumiLogger().w('MagnetDownloadService: apply scheduled limit failed',
          error: e);
    }
  }

  /// 当前时刻的生效下载限速（字节/秒）：在限速时段内返回时段限速，
  /// 否则返回全局设置值。
  int _scheduledLimitBpsNow() {
    final start = _parseHm(GStorage.getSetting(SettingsKeys.magnetScheduledLimitStart));
    final end = _parseHm(GStorage.getSetting(SettingsKeys.magnetScheduledLimitEnd));
    final global = GStorage.getSetting(SettingsKeys.magnetMaxDownloadLimitKb) * 1024;
    if (start == null || end == null) return global;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final inWindow = start <= end
        ? (nowMin >= start && nowMin < end)
        : (nowMin >= start || nowMin < end); // 跨天窗口（如 23:00-08:00）
    if (!inWindow) return global;
    final kb = GStorage.getSetting(SettingsKeys.magnetScheduledLimitKb);
    // 时段限速 0 表示不限（引擎 setDownloadLimit(0)），与设置文案一致。
    return kb <= 0 ? 0 : kb * 1024;
  }

  static int? _parseHm(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return h * 60 + m;
  }

  @visibleForTesting
  static int? parseHmForTest(String value) => _parseHm(value);

  @visibleForTesting
  static bool inWindowForTest(int nowMin, int? start, int? end) {
    if (start == null || end == null) return false;
    return start <= end
        ? (nowMin >= start && nowMin < end)
        : (nowMin >= start || nowMin < end);
  }

  /// 「仅 WiFi 下载」策略：非 WiFi 时暂停所有下载中任务，
  /// 恢复 WiFi 时把被该策略暂停的任务继续。
  Future<void> _applyWifiOnlyPolicy() async {
    if (!LibtorrentFlutter.isInitialized) return;
    final wifiOnly = GStorage.getSetting(SettingsKeys.magnetWifiOnly);
    if (!wifiOnly) {
      _lastWifiOnlyEnforced = null;
      // 关闭「仅 WiFi」：继续被该策略暂停的任务（用户手动暂停的不动，
      // 其 _pausedByWifi 已在 pause() 时清除）。
      var resumed = 0;
      for (final entry in _entries) {
        if (!entry._pausedByWifi) continue;
        entry._pausedByWifi = false;
        if (entry.status == 'paused') {
          unawaited(unpause(entry.taskId));
          resumed++;
        }
      }
      if (resumed > 0) {
        KazumiLogger()
            .i('MagnetDownloadService: wifi only disabled, resumed $resumed');
      }
      return;
    }
    final isWifi = await _isWifiNetwork();
    if (isWifi == _lastWifiOnlyEnforced) return;
    _lastWifiOnlyEnforced = isWifi;
    if (isWifi) {
      // 恢复 WiFi：继续被该策略暂停的任务。
      var resumed = 0;
      for (final entry in _entries) {
        if (!entry._pausedByWifi) continue;
        entry._pausedByWifi = false;
        unawaited(unpause(entry.taskId));
        resumed++;
      }
      if (resumed > 0) {
        KazumiLogger().i('MagnetDownloadService: wifi restored, resumed $resumed');
      }
    } else {
      // 非 WiFi：暂停所有下载中任务（在播边下边播任务豁免，断流即卡死）。
      var paused = 0;
      for (final entry in _entries) {
        if (!entry.isDownloading ||
            entry._pausedByWifi ||
            _streamingTaskIds.contains(entry.taskId)) {
          continue;
        }
        entry._pausedByWifi = true;
        unawaited(pause(entry.taskId));
        paused++;
      }
      if (paused > 0) {
        KazumiLogger()
            .i('MagnetDownloadService: wifi lost, paused $paused tasks');
      }
    }
  }

  /// 当前网络是否为 WiFi / 有线。查询失败或无法判断时返回 true（不误停）。
  Future<bool> _isWifiNetwork() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet) ||
          results.contains(ConnectivityResult.vpn) ||
          results.contains(ConnectivityResult.none);
    } catch (e) {
      KazumiLogger().w('MagnetDownloadService: connectivity check failed',
          error: e);
      return true;
    }
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
      final parsed = <MagnetDownloadEntry>[];
      final taskIds = <String>{};
      var migrated = false;
      for (final e in list) {
        try {
          final json = Map<String, dynamic>.from(e as Map);
          final persistedTaskId = json['taskId'] as String?;
          if (persistedTaskId == null ||
              persistedTaskId.isEmpty ||
              taskIds.contains(persistedTaskId)) {
            json.remove('taskId');
            migrated = true;
          }
          final entry = MagnetDownloadEntry.fromJson(json);
          taskIds.add(entry.taskId);
          parsed.add(entry);
        } catch (e) {
          // 单条数据损坏时跳过该条，避免整份任务索引被清空。
          KazumiLogger()
              .w('MagnetDownloadService: skip corrupt entry', error: e);
        }
      }
      _entries
        ..clear()
        ..addAll(parsed);
      if (migrated) await _saveEntries();
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
  /// 防止旧会话的 torrent 序号在重挂过程中匹配到新会话里
  /// 序号相同但内容不同的任务，造成进度/状态错乱。
  Future<void> _reconcileWithEngine() async {
    if (!LibtorrentFlutter.isInitialized) return;
    _reconciling = true;
    try {
      final existing = LibtorrentFlutter.instance.torrents;
      var changed = false;
      final reconciled = <MagnetDownloadEntry>[];
      for (final entry in _entries) {
        final id = int.tryParse(entry.sessionGid ?? '');
        if (id != null && existing.containsKey(id)) {
          reconciled.add(entry);
          continue;
        }
        if (entry.sessionGid != null) {
          entry.sessionGid = null;
          changed = true;
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
        final bool essentiallyDone =
            entry.totalLength > 0 && entry.verifiedLength >= entry.totalLength;
        // 已完成任务（做种停止条件已满足）不再重挂；做种中任务在
        // 引擎支持校验且文件完整时重挂以续做种。
        final bool shouldRemount = resumeCapable
            ? (activeish || (entry.status == 'seeding' && _isFileIntact(entry)))
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
          entry.sessionGid = newId;
          // 重挂后文件选择需要重新应用（元数据就绪时由 _onTorrents 处理）。
          entry._fileSelectionApplied = false;
          if (entry.status == 'complete' || entry.status == 'seeding') {
            // 续做种重挂：引擎将校验磁盘（checking 期 totalDone 从 0
            // 爬升是校验而非下载），标记 _reseed 让 UI 保持 100% 显示；
            // 记录历史上传基数，做种率 = 基数 + 本会话新增上传。
            entry._reseed = true;
            entry._uploadBase = entry.totalUploaded;
            entry._restartFloor = null;
          } else {
            // 未完成任务：resumeAware 引擎重挂后会真实校验磁盘（checking
            // 期 totalDone 从 0 爬升是校验而非下载），置位 _wasRestoring
            // 让校验期保留旧进度、校验完成后按真实字节对齐，避免
            // 「从零重下」混合基线导致的进度虚高。
            entry._reseed = false;
            entry._uploadBase = 0;
            if (resumeCapable) {
              entry._restartFloor = null;
              entry._wasRestoring = true;
            } else {
              entry._restartFloor = entry.totalLength > 0
                  ? (entry.verifiedLength / entry.totalLength).clamp(0.0, 1.0)
                  : 0.0;
            }
          }
          // 用户手动暂停 / 排队等待槽位的任务重挂后保持暂停，避免恢复下载。
          if (entry.status == 'paused' || entry.status == 'queued') {
            try {
              final pausedId = int.tryParse(entry.sessionGid ?? '');
              if (pausedId != null) {
                LibtorrentFlutter.instance.pauseTorrent(pausedId);
              }
            } catch (e) {
              KazumiLogger().w(
                  'MagnetDownloadService: re-pause remounted torrent failed',
                  error: e);
            }
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
        // 重启重挂后重算队列：所有任务默认恢复下载，超出上限的自动降级排队。
        _reconcileQueue();
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

  /// 判断已选择的种子文件是否仍完整存在于磁盘上（重挂续做种的守卫）。
  static bool _isFileIntact(MagnetDownloadEntry entry) {
    if (entry.savePath.isEmpty) return false;
    if (entry.files.isNotEmpty) {
      final selected = entry.selectedFileIndexes?.toSet();
      final requiredFiles = selected == null
          ? entry.files
          : entry.files.where((file) => selected.contains(file.index));
      var found = false;
      for (final file in requiredFiles) {
        found = true;
        final path = entry.absolutePathFor(file);
        if (path == null) return false;
        final diskFile = File(path);
        if (!diskFile.existsSync() || diskFile.lengthSync() != file.size) {
          return false;
        }
      }
      return found;
    }
    if (entry.fileName.isEmpty) return false;
    final candidate = p.join(entry.savePath, entry.fileName);
    return File(candidate).existsSync() || Directory(candidate).existsSync();
  }

  // ---------------- 任务操作 ----------------

  /// 提交磁力 / 种子链接到引擎。
  ///
  /// [dir] 指定下载目录，留空则使用引擎默认目录。
  /// [scrapeInfo] 为已关联的番剧信息（如从番剧详情页发起搜索时携带），
  /// 此时任务默认为「已搜刮」的番剧，下载完成后会自动同步到媒体库。
  /// 返回 torrent 标识；若引擎不可用则返回空字符串。
  Future<String> add(
    MagnetSearchItem item, {
    String? dir,
    MediaScrapeInfo? scrapeInfo,
  }) async {
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
    // 添加前检查可用空间：明显不足时提示，避免无谓的元数据下载与写盘失败。
    unawaited(_warnLowDiskSpace(savePath));
    final sessionGid = await _engineAdd(uri, savePath: savePath);
    if (sessionGid == null || sessionGid.isEmpty) return '';
    final entry = MagnetDownloadEntry(
      sessionGid: sessionGid,
      title: item.title,
      sourceUri: uri,
      savePath: savePath,
      addedAt: DateTime.now(),
      scrapeInfo: scrapeInfo,
      // 详情页携带的番剧信息是用户主动关联，置信度视为 1.0，
      // 自动入库时无需额外校验阈值。
      scrapeConfidence: scrapeInfo != null ? 1.0 : 0,
    );
    _entries.insert(0, entry);
    _reconcileQueue();
    await _saveEntries();
    onChanged?.call(_entries);
    return entry.taskId;
  }

  Future<bool> pause(String taskId) async {
    final entry = _find(taskId);
    if (entry == null) return false;
    // 用户手动暂停：清除「仅 WiFi」自动暂停标记，避免 WiFi 恢复时被
    // 策略自动继续，覆盖用户意图。
    entry._pausedByWifi = false;
    // 在播边下边播任务先停止流：引擎暂停后流取片停滞，播放器会永久
    // 缓冲；显式停止让播放器进入错误态，用户可自行恢复后重新开始播放。
    if (_streamingTaskIds.contains(taskId)) {
      stopStreamsForTask(taskId);
    }
    final id = int.tryParse(entry.sessionGid ?? '');
    if (id != null && LibtorrentFlutter.isInitialized) {
      try {
        LibtorrentFlutter.instance.pauseTorrent(id);
      } catch (e) {
        KazumiLogger()
            .w('MagnetDownloadService: pause torrent failed', error: e);
      }
    }
    entry.status = 'paused';
    _reconcileQueue();
    await _saveEntries();
    onChanged?.call(_entries);
    return true;
  }

  Future<bool> unpause(String taskId) async {
    final entry = _find(taskId);
    if (entry == null) return false;
    final id = int.tryParse(entry.sessionGid ?? '');
    if (id != null && LibtorrentFlutter.isInitialized && _engine.isRunning) {
      try {
        LibtorrentFlutter.instance.resumeTorrent(id);
      } catch (e) {
        KazumiLogger()
            .w('MagnetDownloadService: resume torrent failed', error: e);
      }
    }
    // 引擎未运行时仅更新索引状态，待引擎启动后由 reconcile 重挂。
    // 排队任务手动恢复视为「立即开始」，随后由队列策略再平衡。
    entry.status = 'waiting';
    _reconcileQueue();
    await _saveEntries();
    onChanged?.call(_entries);
    return true;
  }

  Future<bool> remove(String taskId, {bool deleteFiles = false}) async {
    final entry = _find(taskId);
    if (entry == null) return false;
    final id = int.tryParse(entry.sessionGid ?? '');
    // 引擎可用时同步移除引擎中的任务；引擎不可用（启动失败 / 旧数据）
    // 时直接移除索引，避免任务永久无法删除。
    if (id != null && LibtorrentFlutter.isInitialized) {
      // 先停止该任务的边下边播流，避免播放器继续从已删除任务拉流。
      stopStreamsForTask(taskId);
      try {
        LibtorrentFlutter.instance.removeTorrent(id, deleteFiles: deleteFiles);
      } catch (e) {
        KazumiLogger()
            .w('MagnetDownloadService: remove torrent failed', error: e);
      }
    }
    if (deleteFiles) {
      // 引擎可能已把任务移除（如已完成任务停止做种后）、删除失败或不可用：
      // 兜底按落盘路径清理（幂等，引擎已删除时 no-op）。
      try {
        await _deleteOnDisk(entry);
      } catch (e) {
        KazumiLogger()
            .w('MagnetDownloadService: delete files failed', error: e);
      }
    }
    _entries.removeWhere((e) => e.taskId == taskId);
    _reconcileQueue();
    await _saveEntries();
    onChanged?.call(_entries);
    return true;
  }

  // ---------------- 并发限制与队列调度 ----------------

  int get _maxActiveDownloads =>
      GStorage.getSetting(SettingsKeys.magnetMaxActiveDownloads);

  /// 添加任务前的可用空间提示（不阻断）。
  Future<void> _warnLowDiskSpace(String savePath) async {
    final available = await DiskSpace.availableBytes(savePath);
    if (available == null || available >= _minFreeSpaceForAdd) return;
    KazumiLogger().w(
        'MagnetDownloadService: low disk space ($available bytes) for $savePath');
  }

  /// 元数据就绪后校验磁盘空间：剩余空间不足以容纳「剩余需下载字节 +
  /// 余量」时自动暂停任务。
  void _checkDiskSpaceForEntry(MagnetDownloadEntry entry) {
    if (entry.status != 'active' && entry.status != 'checking') return;
    if (entry.totalLength <= 0) return;
    final remaining = entry.totalLength - entry.verifiedLength;
    if (remaining <= 0) return;
    unawaited(DiskSpace.availableBytes(entry.savePath).then((bytes) {
      if (bytes == null || bytes >= remaining + _freeSpaceMargin) return;
      KazumiLogger().w(
          'MagnetDownloadService: out of disk space, pausing ${entry.fileName} '
          '(free $bytes, need ${remaining + _freeSpaceMargin})');
      unawaited(pause(entry.taskId));
    }));
  }

  /// 队列策略纯函数：根据活动下载任务数与上限计算需要提升 / 降级的任务。
  ///
  /// 排队任务按添加时间升序提升（先添加先下载）；需要降级时按添加时间
  /// 倒序挑选（最后添加的活动任务先让位）。上限 <= 0 表示不限。
  ///
  /// [keepActive] 中的任务计入活动槽位（占用并发）但永不被降级：
  /// 用于边下边播在播任务，降级暂停会直接掐断正在播放的 HTTP 流。
  @visibleForTesting
  static ({List<String> promote, List<String> demote}) computeQueueChanges(
    List<MagnetDownloadEntry> entries,
    int maxActive, {
    Set<String> keepActive = const {},
  }) {
    if (maxActive <= 0) {
      return (promote: const [], demote: const []);
    }
    final active = entries.where((e) => e.isDownloading).toList();
    final demotable =
        active.where((e) => !keepActive.contains(e.taskId)).toList();
    var activeCount = active.length;
    final promote = <String>[];
    final demote = <String>[];
    final queued = entries.where((e) => e.isQueued).toList()
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    for (final entry in queued) {
      if (activeCount >= maxActive) break;
      promote.add(entry.taskId);
      activeCount++;
    }
    if (activeCount > maxActive) {
      final extras = demotable.toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      var excess = activeCount - maxActive;
      for (final entry in extras) {
        if (excess <= 0) break;
        demote.add(entry.taskId);
        excess--;
      }
    }
    return (promote: promote, demote: demote);
  }

  /// 依据 [computeQueueChanges] 应用队列变更：提升排队任务（引擎恢复）、
  /// 降级超出上限的活动任务（引擎暂停）。
  void _reconcileQueue() {
    final changes =
        computeQueueChanges(_entries, _maxActiveDownloads, keepActive: _streamingTaskIds);
    for (final taskId in changes.promote) {
      final entry = _find(taskId);
      if (entry == null) continue;
      entry.status = 'waiting';
      final id = int.tryParse(entry.sessionGid ?? '');
      if (id != null && LibtorrentFlutter.isInitialized && _engine.isRunning) {
        try {
          LibtorrentFlutter.instance.resumeTorrent(id);
        } catch (e) {
          KazumiLogger()
              .w('MagnetDownloadService: promote queued torrent failed',
                  error: e);
        }
      }
    }
    for (final taskId in changes.demote) {
      final entry = _find(taskId);
      if (entry == null) continue;
      entry.status = 'queued';
      final id = int.tryParse(entry.sessionGid ?? '');
      if (id != null && LibtorrentFlutter.isInitialized) {
        try {
          LibtorrentFlutter.instance.pauseTorrent(id);
        } catch (e) {
          KazumiLogger()
              .w('MagnetDownloadService: demote torrent failed', error: e);
        }
      }
    }
  }

  /// 删除任务落盘文件：多文件种子为 `<savePath>/<种子名>` 目录，
  /// 单文件种子为 `<savePath>/<文件名>`。
  /// [fileName] 为空（从未拿到元数据）时跳过，避免误删整个下载目录。
  static Future<void> _deleteOnDisk(MagnetDownloadEntry entry) async {
    if (entry.savePath.isEmpty) return;
    if (entry.files.isNotEmpty) {
      final selected = entry.selectedFileIndexes?.toSet();
      final parentDirs = <String>{};
      for (final torrentFile in entry.files) {
        if (selected != null && !selected.contains(torrentFile.index)) continue;
        final path = entry.absolutePathFor(torrentFile);
        if (path == null) continue;
        final file = File(path);
        if (await file.exists()) await file.delete();
        var parent = p.dirname(path);
        while (p.isWithin(p.absolute(entry.savePath), parent)) {
          parentDirs.add(parent);
          parent = p.dirname(parent);
        }
      }
      final deepestFirst = parentDirs.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final path in deepestFirst) {
        final directory = Directory(path);
        if (!await directory.exists()) continue;
        if (await directory.list().isEmpty) await directory.delete();
      }
      return;
    }
    if (entry.savePath.isEmpty || entry.fileName.isEmpty) return;
    final candidate = p.join(entry.savePath, entry.fileName);
    final dir = Directory(candidate);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      return;
    }
    final file = File(candidate);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 重新拉取所有任务的实时状态。
  Future<void> refresh() async {
    if (!LibtorrentFlutter.isInitialized) return;
    _onTorrents(LibtorrentFlutter.instance.torrents);
  }

  /// 清除全部已完成任务的记录（保留磁盘文件）。返回清除数量。
  Future<int> clearCompleted() async {
    final completed =
        _entries.where((e) => e.isCompleted).toList();
    if (completed.isEmpty) return 0;
    for (final entry in completed) {
      _entries.removeWhere((e) => e.taskId == entry.taskId);
    }
    _reconcileQueue();
    await _saveEntries();
    onChanged?.call(_entries);
    return completed.length;
  }

  /// 手动校验任务文件：让引擎重新扫描磁盘（force_recheck）。
  /// 返回是否已提交校验；任务需已挂载到引擎。
  Future<bool> recheck(String taskId) async {
    final entry = _find(taskId);
    if (entry == null) return false;
    final id = int.tryParse(entry.sessionGid ?? '');
    if (id == null || !LibtorrentFlutter.isInitialized) return false;
    try {
      LibtorrentFlutter.instance.recheckTorrent(id);
      return true;
    } catch (e) {
      KazumiLogger().w('MagnetDownloadService: recheck failed', error: e);
      return false;
    }
  }

  /// 错误任务一键重试：把源重新提交到引擎（保留磁盘数据与进度）。
  Future<bool> retry(String taskId) async {    final entry = _find(taskId);
    if (entry == null) return false;
    entry._metadataRetries = 0;
    entry._metadataStartedAt = null;
    final ok = await _remountForRetry(entry);
    entry.status = ok ? 'waiting' : 'error';
    _reconcileQueue();
    await _saveEntries();
    onChanged?.call(_entries);
    return ok;
  }

  /// 重新把任务提交到引擎（重试 / 元数据超时用）。
  ///
  /// 先移除引擎中的旧任务（不删文件），再重加磁力 / 种子；resumeAware
  /// 引擎重加后会校验磁盘续传，非 resumeAware 引擎按已验证字节设恢复基线。
  Future<bool> _remountForRetry(MagnetDownloadEntry entry) async {
    final oldId = int.tryParse(entry.sessionGid ?? '');
    if (oldId != null && LibtorrentFlutter.isInitialized) {
      try {
        LibtorrentFlutter.instance.removeTorrent(oldId, deleteFiles: false);
      } catch (e) {
        KazumiLogger().w(
            'MagnetDownloadService: remove torrent for retry failed',
            error: e);
      }
    }
    final newId = await _engineAdd(entry.sourceUri, savePath: entry.savePath);
    if (newId == null || newId.isEmpty) {
      return false;
    }
    entry.sessionGid = newId;
    entry._fileSelectionApplied = false;
    entry._reseed = false;
    entry._uploadBase = 0;
    if (LibtorrentFlutter.resumeAware) {
      entry._restartFloor = null;
      entry._wasRestoring = true;
    } else {
      entry._restartFloor = entry.totalLength > 0
          ? (entry.verifiedLength / entry.totalLength).clamp(0.0, 1.0)
          : 0.0;
    }
    return true;
  }

  /// 列出任务的种子文件（元数据就绪后才可用）。
  Future<List<FileInfo>> listFiles(String taskId) async {
    final entry = _find(taskId);
    if (entry == null) return const [];
    final id = int.tryParse(entry.sessionGid ?? '');
    if (id == null || !LibtorrentFlutter.isInitialized) {
      return entry.files.map((file) => file.toFileInfo()).toList();
    }
    try {
      final files = LibtorrentFlutter.instance.getFiles(id);
      if (files.isNotEmpty) {
        entry.files = files.map(MagnetDownloadFile.fromFileInfo).toList();
        await _saveEntries();
      }
      return files;
    } catch (e) {
      KazumiLogger().w('MagnetDownloadService: list files failed', error: e);
      return entry.files.map((file) => file.toFileInfo()).toList();
    }
  }

  /// 设置任务的文件选择（部分下载）。
  ///
  /// [selectedIndexes] 为需要下载的文件索引集合；与当前全部文件一致
  /// （即全选）时归一为 null。返回是否成功。
  Future<bool> setFileSelection(
      String taskId, List<int> selectedIndexes) async {
    final entry = _find(taskId);
    if (entry == null) return false;
    final id = int.tryParse(entry.sessionGid ?? '');
    if (id == null || !LibtorrentFlutter.isInitialized) return false;
    try {
      final files = LibtorrentFlutter.instance.getFiles(id);
      if (files.isEmpty) return false;
      entry.files = files.map(MagnetDownloadFile.fromFileInfo).toList();
      final selected = selectedIndexes.toSet();
      final priorities = [
        for (var i = 0; i < files.length; i++) selected.contains(i) ? 4 : 0,
      ];
      LibtorrentFlutter.instance.setFilePriorities(id, priorities);
      // 总量切换为所选文件大小之和，保证进度口径与引擎 totalWanted 一致。
      var newTotal = 0;
      for (final i in selected) {
        if (i >= 0 && i < files.length) newTotal += files[i].size;
      }
      entry.totalLength = newTotal;
      entry.selectedFileIndexes =
          selected.length == files.length ? null : (selected.toList()..sort());
      entry._fileSelectionApplied = true;
      await _saveEntries();
      onChanged?.call(_entries);
      return true;
    } catch (e) {
      KazumiLogger()
          .w('MagnetDownloadService: set file selection failed', error: e);
      return false;
    }
  }

  /// 记录已完成任务的媒体库目标目录，避免重启后重复自动入库。
  Future<void> markImported(String taskId, String importedPath) async {
    final entry = _find(taskId);
    if (entry == null) return;
    entry.importedPath = p.normalize(importedPath);
    await _saveEntries();
    onChanged?.call(_entries);
  }

  /// 写入任务的搜刮结果（自动搜刮命中或用户手动匹配）。
  Future<void> setScrapeInfo(
    String taskId,
    MediaScrapeInfo info, {
    double confidence = 1.0,
  }) async {
    final entry = _find(taskId);
    if (entry == null) return;
    entry.scrapeInfo = info;
    entry.scrapeConfidence = confidence.clamp(0.0, 1.0);
    entry.scrapeAttempted = true;
    await _saveEntries();
    onChanged?.call(_entries);
  }

  /// 标记自动搜刮已尝试但未命中，任务进入「待确认」状态。
  Future<void> markScrapeAttempted(String taskId) async {
    final entry = _find(taskId);
    if (entry == null) return;
    entry.scrapeAttempted = true;
    await _saveEntries();
    onChanged?.call(_entries);
  }

  /// 复位搜刮状态（清除匹配结果与尝试标记），供用户重新搜刮 / 重新匹配。
  Future<void> resetScrape(String taskId) async {
    final entry = _find(taskId);
    if (entry == null) return;
    entry.scrapeInfo = null;
    entry.scrapeConfidence = 0;
    entry.scrapeAttempted = false;
    await _saveEntries();
    onChanged?.call(_entries);
  }

  /// 测试引擎是否可用，返回 libtorrent 版本或 null。
  Future<String?> ping() async {
    if (!LibtorrentFlutter.isInitialized) return null;
    final version = LibtorrentFlutter.instance.libraryVersion;
    return version.isEmpty ? 'engine' : version;
  }

  /// 启动边下边播：让引擎流媒体服务器流式提供指定文件，
  /// 返回可交给播放器的 HTTP URL；失败返回 null。
  ///
  /// 任务需已挂载到引擎（有 sessionGid）且引擎已初始化；暂停 / 排队中
  /// 的任务需先恢复下载，否则流无数据。
  Future<String?> startStream(String taskId, int fileIndex) async {
    final entry = _find(taskId);
    if (entry == null) return null;
    final id = int.tryParse(entry.sessionGid ?? '');
    if (id == null || !LibtorrentFlutter.isInitialized) return null;
    try {
      final info = LibtorrentFlutter.instance.startStream(
        id,
        fileIndex: fileIndex,
      );
      if (info.url.isEmpty) return null;
      _streamingTaskIds.add(taskId);
      KazumiLogger().i(
          'MagnetDownloadService: stream started for $taskId file $fileIndex -> ${info.url}');
      return info.url;
    } catch (e) {
      KazumiLogger()
          .w('MagnetDownloadService: start stream failed', error: e);
      return null;
    }
  }

  /// 停止任务关联的全部流（删除任务 / 暂停 / 播放页退出时调用）。
  ///
  /// 任务已完成但仍在播时，流停止后补做「停止做种」清理（引擎移除），
  /// 因为完成分支会为在播任务保留引擎句柄。
  void stopStreamsForTask(String taskId) {
    _streamingTaskIds.remove(taskId);
    final entry = _find(taskId);
    if (entry == null) return;
    final id = int.tryParse(entry.sessionGid ?? '');
    if (id != null && LibtorrentFlutter.isInitialized) {
      try {
        LibtorrentFlutter.instance.stopAllStreamsForTorrent(id);
      } catch (e) {
        KazumiLogger().w('MagnetDownloadService: stop streams failed', error: e);
      }
    }
    // 流停止后若任务已处于 complete（完成分支为其保留引擎句柄），
    // 补做移除，避免残留做种上传。
    if (id != null && entry.status == 'complete') {
      try {
        LibtorrentFlutter.instance.removeTorrent(id, deleteFiles: false);
        entry.sessionGid = null;
      } catch (e) {
        KazumiLogger().w(
            'MagnetDownloadService: stop seeding after stream end failed',
            error: e);
      }
    }
  }

  MagnetDownloadEntry? _find(String taskId) {
    for (final e in _entries) {
      if (e.taskId == taskId) return e;
    }
    return null;
  }

  /// 是否已存在使用同一磁力链 / 种子地址的任务（订阅自动下载去重用）。
  bool hasDownload(String uri) {
    if (uri.isEmpty) return false;
    return _entries.any((e) => e.sourceUri == uri);
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
      // 排队任务在引擎中保持暂停：跳过状态应用，避免引擎的 paused 状态
      // 覆盖索引中的 queued 标记。但引擎报错时必须流转，否则 UI 恒显示
      // 「排队中」且「重试」菜单只对 error 开放，任务永远无法处理。
      if (entry.isQueued) {
        final queuedId = int.tryParse(entry.sessionGid ?? '');
        if (queuedId != null) {
          final queuedTorrent = torrents[queuedId];
          if (queuedTorrent != null && _mapStatus(queuedTorrent) == 'error') {
            entry.status = 'error';
            unawaited(_saveEntries());
            changed = true;
          }
        }
        continue;
      }
      final id = int.tryParse(entry.sessionGid ?? '');
      if (id == null) continue;
      final t = torrents[id];
      if (t == null) continue;
      final status = _mapStatus(t);
      final prevStatus = entry.status;
      if (t.hasMetadata && entry.files.isEmpty) {
        try {
          final files = LibtorrentFlutter.instance.getFiles(id);
          if (files.isNotEmpty) {
            entry.files = files.map(MagnetDownloadFile.fromFileInfo).toList();
          }
        } catch (e) {
          KazumiLogger()
              .w('MagnetDownloadService: cache torrent files failed', error: e);
        }
      }
      if (t.hasMetadata) {
        // 元数据就绪后按真实大小校验磁盘空间，不足则自动暂停。
        // 用会话级集合防重：files 已持久化，重启后仍会重新校验一次。
        if (_diskSpaceCheckedTaskIds.add(entry.taskId)) {
          _checkDiskSpaceForEntry(entry);
        }
      }
      applyTorrentStatus(
        entry,
        t,
        status,
        now,
        seedingStopMode: seedingStopMode,
        seedingStopRatio: seedingStopRatio,
        seedingStopHours: seedingStopHours,
      );
      // 元数据超时跟踪：记录进入 metadata 状态的时间，超时自动重试；
      // 离开 metadata 后复位，进入真实下载 / 校验时清零重试计数。
      if (entry.status == 'metadata') {
        entry._metadataStartedAt ??= now;
        if (entry._metadataStartedAt != null &&
            now.difference(entry._metadataStartedAt!) >= _metadataTimeout) {
          if (entry._metadataRetries < _maxMetadataRetries) {
            entry._metadataRetries++;
            entry._metadataStartedAt = now;
            KazumiLogger().w(
                'MagnetDownloadService: metadata timeout, auto retry #${entry._metadataRetries} for "${entry.fileName}"');
            unawaited(_remountForRetry(entry).then((ok) {
              if (!ok) {
                entry.status = 'error';
                unawaited(_saveEntries());
                onChanged?.call(_entries);
              }
            }));
          } else {
            KazumiLogger().w(
                'MagnetDownloadService: metadata retries exhausted, mark error for "${entry.fileName}"');
            entry.status = 'error';
          }
        }
      } else {
        entry._metadataStartedAt = null;
        if (entry.status == 'active' || entry.status == 'checking') {
          entry._metadataRetries = 0;
        }
      }
      // 文件选择尚未应用到引擎（如重启重挂后）：元数据就绪时应用。
      if (entry.selectedFileIndexes != null &&
          !entry._fileSelectionApplied &&
          t.hasMetadata) {
        try {
          final files = LibtorrentFlutter.instance.getFiles(id);
          if (files.isNotEmpty) {
            final selected = entry.selectedFileIndexes!.toSet();
            final priorities = [
              for (var i = 0; i < files.length; i++)
                selected.contains(i) ? 4 : 0,
            ];
            LibtorrentFlutter.instance.setFilePriorities(id, priorities);
            entry._fileSelectionApplied = true;
            // 原生 set_file_priorities 会 resume 任务：暂停态任务恢复暂停。
            if (entry.status == 'paused') {
              LibtorrentFlutter.instance.pauseTorrent(id);
            }
          }
        } catch (e) {
          KazumiLogger().w('MagnetDownloadService: apply file selection failed',
              error: e);
        }
      }
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
          if (_streamingTaskIds.contains(entry.taskId)) {
            // 边下边播在播：保留引擎句柄，否则流取片立即失败；
            // 流停止后由 stopStreamsForTask 补做移除。
            KazumiLogger().i(
                'MagnetDownloadService: ${entry.fileName} completed while '
                'streaming, defer engine removal');
          } else {
            try {
              LibtorrentFlutter.instance.removeTorrent(id, deleteFiles: false);
              entry.sessionGid = null;
            } catch (e) {
              KazumiLogger()
                  .w('MagnetDownloadService: stop seeding failed', error: e);
            }
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
    // 状态流转后重算队列：有任务离开下载态（完成 / 暂停 / 错误）时
    // 自动提升排队任务。
    _reconcileQueue();
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
        seedingStopTime =>
          _seedingWithinDuration(entry.seedingStartedAt, seedingStopHours, now),
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
        if (entry._wasRestoring && status == 'active') {
          // 校验完成、真正开始下载：以引擎重新校验出的真实字节对齐，
          // 消除恢复阶段的进度跳变。暂停 / 等待 / 错误等尚未进入
          // 真实下载的状态保留旧进度，避免被 0 值打回。
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
  /// 返回：waiting / metadata / checking / active / paused / complete / error。
  static String _mapStatus(TorrentInfo t) {
    if (t.isPaused) return 'paused';
    if ((t.isFinished && t.progress >= 0.999) ||
        t.state == TorrentState.finished ||
        t.state == TorrentState.seeding) {
      return 'complete';
    }
    switch (t.state) {
      case TorrentState.error:
        return 'error';
      case TorrentState.downloadingMetadata:
        return 'metadata';
      case TorrentState.downloading:
        return 'active';
      case TorrentState.checkingFiles:
      case TorrentState.checkingResume:
      case TorrentState.allocating:
        return t.hasMetadata ? 'checking' : 'waiting';
      case TorrentState.unknown:
        return 'waiting';
      default:
        return 'active';
    }
  }

  @visibleForTesting
  static String mapStatusForTest(TorrentInfo info) => _mapStatus(info);

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
        // 临时 .torrent 已在原生侧同步解析为 torrent_info，删除防堆积。
        try {
          await File(torrentPath).delete();
        } catch (e) {
          KazumiLogger()
              .w('MagnetDownloadService: cleanup torrent temp file failed',
                  error: e);
        }
      } else {
        id = engine.addTorrentFile(trimmed, savePath);
      }
    } catch (e) {
      // 重复添加 / 引擎异常都会抛错：返回 null，保留原记录。
      KazumiLogger().w('MagnetDownloadService: engine add failed', error: e);
      return null;
    }
    // 注入用户缓存的 tracker，加速冷启动时的 peer 发现。
    final trackers = _cachedTrackersForEngine();
    if (trackers.isNotEmpty) {
      try {
        engine.addTrackers(id, trackers);
      } catch (e) {
        KazumiLogger()
            .w('MagnetDownloadService: add trackers failed', error: e);
      }
    }
    return '$id';
  }

  /// 取缓存 tracker 中适合注入引擎的数量上限（过多 tracker 反而拖慢握手）。
  static List<String> _cachedTrackersForEngine() =>
      TrackerUpdater.instance.cachedTrackers().take(20).toList();

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
      KazumiLogger()
          .w('MagnetDownloadService: download torrent failed', error: e);
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
    String? taskId,
    this.sessionGid,
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
    this.scrapeInfo,
    this.selectedFileIndexes,
    this.seedingStartedAt,
    this.importedPath = '',
    this.scrapeConfidence = 0,
    this.scrapeAttempted = false,
    List<MagnetDownloadFile>? files,
  })  : taskId = taskId ?? _newTaskId(),
        files = files ?? <MagnetDownloadFile>[];

  /// Kazumi 持久任务 ID。界面和业务操作只使用该 ID。
  final String taskId;

  /// libtorrent 当前进程内的临时任务 ID。重启后必须重新绑定，不持久化。
  String? sessionGid;

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

  /// 元数据就绪后缓存的种子文件清单。完成任务从引擎移除后仍可展示和导入。
  List<MagnetDownloadFile> files;

  /// 已关联的番剧信息（持久化）。非空表示该任务默认为「已搜刮」的番剧，
  /// 来源为番剧详情页发起的磁力搜索；下载完成后会自动同步到媒体库搜刮结果。
  MediaScrapeInfo? scrapeInfo;

  bool get isScraped => scrapeInfo != null;

  /// 搜刮置信度（持久化，0~1）：详情页发起的任务恒为 1.0，自动搜刮按
  /// 匹配得分记录。自动入库需达到设置阈值，避免把文件错搬进错误番剧目录。
  double scrapeConfidence;

  /// 是否已尝试过自动搜刮（持久化）。搜刮失败 / 未命中时置位，
  /// 任务显示「待确认」供手动匹配；手动重搜刮时复位。
  bool scrapeAttempted;

  /// 自动搜刮未命中、等待用户手动匹配的任务。
  bool get scrapePending => scrapeAttempted && scrapeInfo == null;

  /// 文件选择（持久化）：需要下载的文件索引集合；null 表示全部文件。
  List<int>? selectedFileIndexes;

  /// 文件选择是否已应用到引擎会话（不持久化，重挂后需重新应用）。
  bool _fileSelectionApplied = false;

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

  /// 进入 metadata 状态的时间（不持久化），元数据超时自动重试用。
  DateTime? _metadataStartedAt;

  /// 元数据超时重试次数（不持久化）。
  int _metadataRetries = 0;

  /// 是否因「仅 WiFi 下载」策略被自动暂停（不持久化），
  /// 恢复 WiFi 后由策略调度器自动继续。
  bool _pausedByWifi = false;

  /// 开始做种的时间（持久化）。做种停止策略为「按时间」时，
  /// 做种满 [SettingsKeys.magnetSeedingStopHours] 小时后停止。
  DateTime? seedingStartedAt;

  /// 自动入库成功后的目标目录。非空时不再移动原下载路径。
  String importedPath;

  @visibleForTesting
  set restartFloorForTest(double? value) => _restartFloor = value;

  @visibleForTesting
  set reseedForTest(bool value) => _reseed = value;

  @visibleForTesting
  set uploadBaseForTest(int value) => _uploadBase = value;

  @visibleForTesting
  set seedingStartedAtForTest(DateTime? value) => seedingStartedAt = value;

  @visibleForTesting
  set fileSelectionAppliedForTest(bool value) => _fileSelectionApplied = value;

  double get progress => totalLength > 0 ? completedLength / totalLength : 0.0;

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

  /// 排队等待下载槽位的任务（受并发上限约束，引擎中保持暂停）。
  bool get isQueued => status == 'queued';
  bool get isActive => isDownloading || isSeeding;
  bool get isPaused => status == 'paused';
  bool get isError => status == 'error' || status == 'removed';

  factory MagnetDownloadEntry.fromJson(Map<String, dynamic> json) {
    // 兼容旧数据：新版本只持久化 verifiedLength，旧版本只有 completedLength。
    final verified =
        _toInt(json['verifiedLength']) ?? _toInt(json['completedLength']) ?? 0;
    final rawInfo = json['scrapeInfo'];
    final rawFiles = json['files'];
    final persistedTaskId = json['taskId'] as String?;
    return MagnetDownloadEntry(
      taskId: persistedTaskId != null && persistedTaskId.isNotEmpty
          ? persistedTaskId
          : null,
      // 旧 gid 属于上一次进程的引擎会话，不能恢复为 sessionGid。
      sessionGid: null,
      title: json['title'] as String? ?? '',
      sourceUri: json['sourceUri'] as String? ?? '',
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
      savePath: json['savePath'] as String? ?? '',
      status: json['status'] as String? ?? 'waiting',
      totalLength: _toInt(json['totalLength']) ?? 0,
      completedLength: verified,
      verifiedLength: verified,
      downloadSpeed: _toInt(json['downloadSpeed']) ?? 0,
      uploadSpeed: _toInt(json['uploadSpeed']) ?? 0,
      totalUploaded: _toInt(json['totalUploaded']) ?? 0,
      numSeeds: _toInt(json['numSeeds']) ?? 0,
      numPeers: _toInt(json['numPeers']) ?? 0,
      fileName: json['fileName'] as String? ?? '',
      scrapeInfo: rawInfo is Map
          ? MediaScrapeInfo.fromJson(Map<String, dynamic>.from(rawInfo))
          : null,
      selectedFileIndexes: (json['selectedFileIndexes'] as List?)
          ?.whereType<num>()
          .map((e) => e.toInt())
          .toList(),
      seedingStartedAt:
          DateTime.tryParse(json['seedingStartedAt'] as String? ?? ''),
      importedPath: json['importedPath'] as String? ?? '',
      scrapeConfidence: (json['scrapeConfidence'] as num?)?.toDouble() ?? 0,
      scrapeAttempted: json['scrapeAttempted'] as bool? ?? false,
      files: rawFiles is List
          ? rawFiles
              .whereType<Map>()
              .map((file) =>
                  MagnetDownloadFile.fromJson(Map<String, dynamic>.from(file)))
              .toList()
          : null,
    );
  }

  /// 返回种子相对路径对应的安全绝对路径；越过下载目录时返回 null。
  String? absolutePathFor(MagnetDownloadFile file) {
    if (savePath.isEmpty || file.path.isEmpty || p.isAbsolute(file.path)) {
      return null;
    }
    final base = p.normalize(p.absolute(savePath));
    final candidate = p.normalize(p.join(base, file.path));
    if (candidate != base && !p.isWithin(base, candidate)) return null;
    return candidate;
  }

  /// 容错解析数值字段：兼容历史数据中可能存在的字符串数值。
  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  Map<String, dynamic> toJson() => {
        'version': 2,
        'taskId': taskId,
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
        if (scrapeInfo != null) 'scrapeInfo': scrapeInfo!.toJson(),
        if (selectedFileIndexes != null)
          'selectedFileIndexes': selectedFileIndexes,
        if (files.isNotEmpty)
          'files': files.map((file) => file.toJson()).toList(),
        'seedingStartedAt': seedingStartedAt?.toIso8601String() ?? '',
        if (importedPath.isNotEmpty) 'importedPath': importedPath,
        if (scrapeConfidence > 0) 'scrapeConfidence': scrapeConfidence,
        if (scrapeAttempted) 'scrapeAttempted': true,
      };

  static final Random _taskIdRandom = Random.secure();
  static int _taskIdSequence = 0;

  static String _newTaskId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final entropy = _taskIdRandom.nextInt(0x7fffffff).toRadixString(36);
    final sequence = (_taskIdSequence++ & 0xffff).toRadixString(36);
    return '$timestamp-$entropy-$sequence';
  }
}

/// 可持久化的种子文件清单项。
class MagnetDownloadFile {
  const MagnetDownloadFile({
    required this.index,
    required this.name,
    required this.path,
    required this.size,
    required this.isStreamable,
  });

  final int index;
  final String name;
  final String path;
  final int size;
  final bool isStreamable;

  factory MagnetDownloadFile.fromFileInfo(FileInfo file) => MagnetDownloadFile(
        index: file.index,
        name: file.name,
        path: file.path,
        size: file.size,
        isStreamable: file.isStreamable,
      );

  factory MagnetDownloadFile.fromJson(Map<String, dynamic> json) =>
      MagnetDownloadFile(
        index: MagnetDownloadEntry._toInt(json['index']) ?? 0,
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        size: MagnetDownloadEntry._toInt(json['size']) ?? 0,
        isStreamable: json['isStreamable'] as bool? ?? false,
      );

  FileInfo toFileInfo() => FileInfo(
        index: index,
        name: name,
        path: path,
        size: size,
        isStreamable: isStreamable,
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'name': name,
        'path': path,
        'size': size,
        'isStreamable': isStreamable,
      };
}
