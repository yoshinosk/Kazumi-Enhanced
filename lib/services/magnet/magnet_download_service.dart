import 'dart:async';
import 'dart:convert';

import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/magnet/aria2_client.dart';
import 'package:kazumi/services/magnet/aria2_engine.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/magnet/peer_protection_monitor.dart';
import 'package:kazumi/services/magnet/tracker_updater.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 磁力下载服务：在 Aria2 之上维护本地任务索引与轮询，
/// 并管理内置引擎、Tracker 自动更新、对等节点行为监控。
///
/// 任务索引持久化在设置盒子中（JSON 字符串），重启后仍能恢复 GID。
class MagnetDownloadService {
  MagnetDownloadService();

  final Aria2Client _aria2 = Aria2Client();
  final Aria2Engine _engine = Aria2Engine();
  final PeerProtectionMonitor _monitor = PeerProtectionMonitor();

  Timer? _pollTimer;
  Timer? _trackerTimer;

  /// 内置引擎状态变化回调（供 Controller 刷新 observable）。
  void Function(Aria2EngineState state)? onEngineStateChanged;

  Aria2Engine get engine => _engine;
  Aria2EngineState get engineState => _engine.state;

  bool get aria2Enabled => _aria2.isEnabled;
  Aria2Client get aria2 => _aria2;

  /// 当前内存中的任务快照，由 [refresh] 维护。
  final List<MagnetDownloadEntry> _entries = [];
  List<MagnetDownloadEntry> get entries => List.unmodifiable(_entries);

  /// 状态变化回调，供 Controller 注册以驱动 MobX observable。
  void Function(List<MagnetDownloadEntry>)? onChanged;

  /// 新封禁事件回调。
  void Function(BannedPeer peer)? onPeerBanned;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadEntries();
    _engine.onStateChanged = (state) => onEngineStateChanged?.call(state);
    _monitor.onBanned = (peer) => onPeerBanned?.call(peer);

    // 启动引擎（内置模式）或直接使用外部 RPC。
    if (Aria2Engine.enabledBySettings && Aria2Engine.supported) {
      await _engine.start();
    }
    if (_aria2.isEnabled) {
      await refresh();
      _startPolling();
    }
    _startTrackerScheduler();
    await _monitor.start();
  }

  Future<void> dispose() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _trackerTimer?.cancel();
    _trackerTimer = null;
    await _monitor.stop();
    await _engine.dispose();
  }

  /// 内置引擎状态绑定。
  Future<void> _syncMonitor() async {
    if (_engine.isRunning || _aria2.isEnabled) {
      await _monitor.start();
    } else {
      await _monitor.stop();
    }
  }

  /// 手动启动 / 停止内置引擎。
  Future<bool> startEngine() async {
    final ok = await _engine.start();
    if (ok) {
      await refresh();
      _startPolling();
    }
    await _syncMonitor();
    return ok;
  }

  Future<void> stopEngine() async {
    await _engine.stop();
    _pollTimer?.cancel();
    _pollTimer = null;
    await _syncMonitor();
  }

  /// 立即更新 tracker 列表；成功返回数量，失败返回 -1。
  Future<int> updateTrackers() async {
    final count = await TrackerUpdater.instance.update();
    if (count > 0 && _engine.isRunning) {
      await _engine.applyTrackers();
    }
    return count;
  }

  /// 当前缓存 tracker 数量。
  int get cachedTrackerCount => TrackerUpdater.instance.cachedTrackers().length;

  /// 最近一次 tracker 更新时间。
  DateTime? get trackerLastUpdated => TrackerUpdater.instance.lastUpdated();

  /// 对等节点黑名单。
  List<BannedPeer> get bannedPeers => _monitor.banned;

  Future<void> unbanIp(String ip) async {
    await _monitor.unban(ip);
  }

  Future<void> clearBans() async {
    await _monitor.clearAll();
  }

  /// 当设置中的引擎 / RPC 开关变化时调用。
  Future<void> applySettingsChanged() async {
    // 引擎相关设置变化。
    await _engine.applySettingsChanged();

    if (_aria2.isEnabled) {
      await refresh();
      _startPolling();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
      onChanged?.call(_entries);
    }
    _startTrackerScheduler();
    await _syncMonitor();
  }

  /// Tracker 自动更新调度。
  void _startTrackerScheduler() {
    _trackerTimer?.cancel();
    _trackerTimer = null;
    if (!GStorage.getSetting(SettingsKeys.aria2TrackerAutoUpdate)) return;

    final last = TrackerUpdater.instance.lastUpdated();
    final hours = GStorage.getSetting(SettingsKeys.aria2TrackerUpdateHours);
    var delay = (last == null)
        ? const Duration(seconds: 5)
        : last.add(Duration(hours: hours)).difference(DateTime.now());
    if (delay.isNegative) delay = Duration.zero;
    if (delay > const Duration(days: 1)) delay = const Duration(days: 1);
    _trackerTimer = Timer(delay, () async {
      await TrackerUpdater.instance.update();
      if (_engine.isRunning) await _engine.applyTrackers();
      _startTrackerScheduler();
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
  }

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

  /// 提交磁力 / 种子链接到 Aria2。
  ///
  /// [dir] 指定下载目录，留空则使用引擎 / Aria2 默认目录。
  /// 返回 GID；若引擎或 Aria2 不可用则返回空字符串。
  Future<String> add(MagnetSearchItem item, {String? dir}) async {
    // 内置模式：引擎未运行则先尝试启动。
    if (Aria2Engine.enabledBySettings &&
        Aria2Engine.supported &&
        !_engine.isRunning) {
      final ok = await _engine.start();
      if (ok) {
        await refresh();
        _startPolling();
      }
    }
    if (!_aria2.isEnabled) {
      KazumiLogger().w('MagnetDownloadService: aria2 not available, cannot add');
      return '';
    }
    final uri = item.magnetLink.isNotEmpty ? item.magnetLink : item.torrentUrl;
    if (uri.isEmpty) {
      KazumiLogger().w('MagnetDownloadService: empty magnet and torrent url');
      return '';
    }
    final options = <String, String>{};
    if (dir != null && dir.trim().isNotEmpty) {
      options['dir'] = dir.trim();
    }
    final gid = await _aria2.addUri(uri, options: options.isEmpty ? null : options);
    if (gid == null || gid.isEmpty) return '';
    final entry = MagnetDownloadEntry(
      gid: gid,
      title: item.title,
      sourceUri: uri,
      addedAt: DateTime.now(),
    );
    _entries.insert(0, entry);
    await _saveEntries();
    onChanged?.call(_entries);
    return gid;
  }

  Future<bool> pause(String gid) async {
    final ok = await _aria2.pause(gid);
    if (ok) await refresh();
    return ok;
  }

  Future<bool> unpause(String gid) async {
    final ok = await _aria2.unpause(gid);
    if (ok) await refresh();
    return ok;
  }

  Future<bool> remove(String gid) async {
    final ok = await _aria2.remove(gid);
    if (ok) {
      _entries.removeWhere((e) => e.gid == gid);
      await _saveEntries();
      onChanged?.call(_entries);
    }
    return ok;
  }

  /// 重新拉取所有任务的实时状态。
  Future<void> refresh() async {
    if (!_aria2.isEnabled) return;
    if (_entries.isEmpty) {
      onChanged?.call(_entries);
      return;
    }
    var changed = false;
    for (final entry in _entries) {
      final status = await _aria2.tellStatus(entry.gid);
      if (status == null) continue;
      entry
        ..status = status.status
        ..totalLength = status.totalLength
        ..completedLength = status.completedLength
        ..downloadSpeed = status.downloadSpeed
        ..fileName = status.fileName.isNotEmpty ? status.fileName : entry.fileName;
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
    }
  }

  /// 测试 RPC 连接，仅用于设置页。
  Future<String?> ping() => _aria2.ping();
}

/// 本地缓存的下载任务索引。状态字段在 [MagnetDownloadService.refresh] 时更新。
class MagnetDownloadEntry {
  MagnetDownloadEntry({
    required this.gid,
    required this.title,
    required this.sourceUri,
    required this.addedAt,
    this.status = 'waiting',
    this.totalLength = 0,
    this.completedLength = 0,
    this.downloadSpeed = 0,
    this.fileName = '',
  });

  final String gid;
  final String title;
  final String sourceUri;
  final DateTime addedAt;
  String status;
  int totalLength;
  int completedLength;
  int downloadSpeed;
  String fileName;

  double get progress =>
      totalLength > 0 ? completedLength / totalLength : 0.0;

  bool get isCompleted => status == 'complete';
  bool get isActive => status == 'active' || status == 'waiting';
  bool get isPaused => status == 'paused';
  bool get isError => status == 'error' || status == 'removed';

  factory MagnetDownloadEntry.fromJson(Map<String, dynamic> json) {
    return MagnetDownloadEntry(
      gid: json['gid'] as String? ?? '',
      title: json['title'] as String? ?? '',
      sourceUri: json['sourceUri'] as String? ?? '',
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
      status: json['status'] as String? ?? 'waiting',
      totalLength: (json['totalLength'] as num?)?.toInt() ?? 0,
      completedLength: (json['completedLength'] as num?)?.toInt() ?? 0,
      downloadSpeed: (json['downloadSpeed'] as num?)?.toInt() ?? 0,
      fileName: json['fileName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'gid': gid,
        'title': title,
        'sourceUri': sourceUri,
        'addedAt': addedAt.toIso8601String(),
        'status': status,
        'totalLength': totalLength,
        'completedLength': completedLength,
        'downloadSpeed': downloadSpeed,
        'fileName': fileName,
      };
}