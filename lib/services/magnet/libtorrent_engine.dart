import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// 内置 Libtorrent 引擎的运行状态。
enum LibtorrentEngineState {
  stopped,
  starting,
  running,
  stopping,
  error,
}

/// 内置磁力下载引擎：基于 libtorrent_flutter（libtorrent 2.0）的进程内引擎。
///
/// 随应用启动 / 停止，负责初始化原生会话、按设置应用 [BtConfig] 限速 / 监听等
/// 参数，并把 torrent 状态流转交给上层 [LibtorrentEngine.onTorrents]。
class LibtorrentEngine {
  LibtorrentEngine();

  LibtorrentEngineState _state = LibtorrentEngineState.stopped;
  LibtorrentEngineState get state => _state;

  String? _lastError;
  String? get lastError => _lastError;

  StreamSubscription<Map<int, TorrentInfo>>? _statusSub;
  bool _sessionActive = false;

  /// 引擎状态变化回调（供 Controller 刷新 observable）。
  void Function(LibtorrentEngineState state)? onStateChanged;

  /// torrent 状态流转发（引擎启动 / 会话就绪后持续通知上层）。
  void Function(Map<int, TorrentInfo> torrents)? onTorrents;

  bool get isRunning => _sessionActive && _state == LibtorrentEngineState.running;

  String? get libraryVersion =>
      LibtorrentFlutter.isInitialized ? LibtorrentFlutter.instance.libraryVersion : null;

  static bool get supported => !kIsWeb;

  static bool get enabledBySettings =>
      GStorage.getSetting(SettingsKeys.magnetEngineEnabled);

  /// 解析默认下载目录：优先设置值，其次系统“下载”目录，最后应用文档目录。
  static Future<String> resolveDownloadDir() async {
    final configured = GStorage.getSetting(SettingsKeys.magnetDownloadDir).trim();
    if (configured.isNotEmpty) return configured;
    final downloads = await getDownloadsDirectory();
    if (downloads != null && downloads.path.isNotEmpty) return downloads.path;
    return (await getApplicationDocumentsDirectory()).path;
  }

  BtConfig _buildConfig() {
    final g = GStorage.getSetting;
    return BtConfig(
      connectionsLimit: g(SettingsKeys.magnetMaxPeers),
      peersListenPort: g(SettingsKeys.magnetListenPort),
      disableDht: !g(SettingsKeys.magnetEnableDht),
      disableUpnp: !g(SettingsKeys.magnetEnableUpnp),
      forceEncrypt: g(SettingsKeys.magnetForceEncrypt),
      enableIpv6: g(SettingsKeys.magnetEnableIpv6),
      uploadRateLimit: g(SettingsKeys.magnetMaxUploadLimitKb),
      downloadRateLimit: g(SettingsKeys.magnetMaxDownloadLimitKb),
    );
  }

  Future<int> _uploadLimitBytes() async {
    final kb = GStorage.getSetting(SettingsKeys.magnetMaxUploadLimitKb);
    return kb <= 0 ? 0 : kb * 1024;
  }

  Future<int> _downloadLimitBytes() async {
    final kb = GStorage.getSetting(SettingsKeys.magnetMaxDownloadLimitKb);
    return kb <= 0 ? 0 : kb * 1024;
  }

  /// 启动引擎：初始化原生会话（如尚未初始化），应用配置并开始接收状态推送。
  Future<bool> start() async {
    _state = LibtorrentEngineState.starting;
    _notify();
    try {
      if (!LibtorrentFlutter.isInitialized) {
        final savePath = await resolveDownloadDir();
        await LibtorrentFlutter.init(
          defaultSavePath: savePath,
          uploadLimit: await _uploadLimitBytes(),
          fetchTrackers: true,
          pollInterval: const Duration(milliseconds: 600),
        );
      }
      _applySettingsToSession();
      _listenStatus();
      _sessionActive = true;
      _lastError = null;
      _state = LibtorrentEngineState.running;
      _notify();
      KazumiLogger().i(
          'LibtorrentEngine: started (libtorrent ${libraryVersion ?? 'unknown'})');
      return true;
    } catch (e) {
      _lastError = '启动磁力引擎失败：$e';
      _state = LibtorrentEngineState.error;
      _notify();
      KazumiLogger().e('LibtorrentEngine: start failed', error: e);
      return false;
    }
  }

  /// 将当前设置实时应用到运行中的会话。
  void _applySettingsToSession() {
    if (!LibtorrentFlutter.isInitialized) return;
    final engine = LibtorrentFlutter.instance;
    engine.configureSession(_buildConfig());
    _uploadLimitBytes().then((bytes) => engine.setUploadLimit(bytes));
    _downloadLimitBytes().then((bytes) => engine.setDownloadLimit(bytes));
  }

  void _listenStatus() {
    _statusSub?.cancel();
    _statusSub = LibtorrentFlutter.instance.torrentUpdates.listen(
      onTorrents,
      onError: (Object e) {
        KazumiLogger().w('LibtorrentEngine: torrentUpdates error', error: e);
      },
    );
  }

  void _notify() => onStateChanged?.call(_state);

  /// 停止引擎：暂停所有任务并退出“运行中”状态，保留会话与已下载数据。
  Future<void> stop() async {
    _state = LibtorrentEngineState.stopping;
    _notify();
    if (LibtorrentFlutter.isInitialized) {
      final engine = LibtorrentFlutter.instance;
      for (final id in engine.torrents.keys) {
        engine.pauseTorrent(id);
      }
    }
    _sessionActive = false;
    _state = LibtorrentEngineState.stopped;
    _notify();
  }

  /// 设置变化后调用：禁用则停止；运行中则实时应用新参数。
  Future<void> applySettingsChanged() async {
    if (!enabledBySettings) {
      await stop();
      return;
    }
    if (!_sessionActive) {
      await start();
      return;
    }
    if (LibtorrentFlutter.isInitialized) {
      try {
        _applySettingsToSession();
      } catch (e) {
        KazumiLogger().w('LibtorrentEngine: apply settings failed', error: e);
      }
    }
  }

  /// 应用退出时调用：暂停一切任务并清理订阅（不销毁原生会话，避免误删文件）。
  Future<void> dispose() async {
    await stop();
    _statusSub?.cancel();
    _statusSub = null;
  }
}