import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/lan/lan_collect_store.dart';
import 'package:kazumi/services/lan/lan_discovery.dart';
import 'package:kazumi/services/lan/lan_history_store.dart';
import 'package:kazumi/services/lan/lan_media_paths.dart';
import 'package:kazumi/services/lan/lan_sync_models.dart';
import 'package:kazumi/services/lan/lan_sync_server.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

enum LanServerState { disabled, starting, running, error }

enum LanClientState {
  disabled,
  discovering,
  unpaired,
  connecting,
  connected,
  offline,
  error,
}

class LanPairResult {
  const LanPairResult({required this.success, required this.message});

  const LanPairResult.ok(this.message) : success = true;
  const LanPairResult.failed(this.message) : success = false;

  final bool success;
  final String message;
}

/// 局域网同步总控：桌面端服务、手机端发现 / 配对 / 同步与生命周期。
class LanSyncService extends ChangeNotifier with WidgetsBindingObserver {
  LanSyncService(
    this._mediaController,
    this._collectController,
    IHistoryRepository historyRepository,
  ) : _historyStore = LanHistoryStore(historyRepository);

  static const Duration _syncInterval = Duration(minutes: 3);

  /// 播放进度变化后追加推送的最小间隔：定时同步是 3 分钟一次，
  /// 单靠它会让「手机上看完一集，电脑上进度没动」持续几分钟。
  static const Duration _historyPushDelay = Duration(seconds: 20);

  final MediaController _mediaController;
  final CollectController _collectController;
  final LanHistoryStore _historyStore;
  final LanCollectStore _collectStore = LanCollectStore();

  LanSyncServer? _server;
  LanServerState _serverState = LanServerState.disabled;
  String _serverError = '';
  List<String> _serverAddresses = const [];

  LanClientState _clientState = LanClientState.disabled;
  String _clientError = '';
  List<LanDiscoveredServer> _discovered = const [];
  LanDiscoveredServer? _connected;
  DateTime? _lastSyncAt;
  int _lastFolderCount = 0;
  int _lastFileCount = 0;

  Timer? _timer;
  Timer? _historyPushTimer;
  StreamSubscription<void>? _historyChangesSubscription;
  bool _historyPushDirty = false;
  bool _initialized = false;
  bool _syncing = false;
  bool _pairing = false;
  bool _serverStarting = false;

  bool get isServerSupported => Platform.isWindows;

  bool get isClientSupported => Platform.isAndroid;

  bool get serverEnabled =>
      GStorage.getSetting(SettingsKeys.lanSyncServerEnable);

  bool get clientEnabled =>
      GStorage.getSetting(SettingsKeys.lanSyncClientEnable);

  bool get autoSync => GStorage.getSetting(SettingsKeys.lanSyncAutoSync);

  bool get collectEnabled =>
      GStorage.getSetting(SettingsKeys.lanSyncCollectEnable);

  LanServerState get serverState => _serverState;

  String get serverError => _serverError;

  List<String> get serverAddresses => List.unmodifiable(_serverAddresses);

  int get serverPort =>
      _server?.actualPort ??
      GStorage.getSetting(SettingsKeys.lanSyncServerPort);

  String get serverName {
    final stored = GStorage.getSetting(SettingsKeys.lanSyncServerName).trim();
    return stored.isEmpty ? Platform.localHostname : stored;
  }

  String get pairingCode =>
      _server?.pairingCode ??
      GStorage.getSetting(SettingsKeys.lanSyncServerPairingCode);

  LanClientState get clientState => _clientState;

  String get clientError => _clientError;

  List<LanDiscoveredServer> get discoveredServers =>
      List.unmodifiable(_discovered);

  LanDiscoveredServer? get connectedServer => _connected;

  bool get isClientConnected =>
      _clientState == LanClientState.connected && _connected != null;

  DateTime? get lastSyncAt => _lastSyncAt;

  int get lastFolderCount => _lastFolderCount;

  int get lastFileCount => _lastFileCount;

  bool get isPairing => _pairing;

  bool get isSyncing => _syncing;

  bool get hasClientToken =>
      GStorage.getSetting(SettingsKeys.lanSyncClientToken).isNotEmpty;

  String get clientServerName =>
      _connected?.name ??
      GStorage.getSetting(SettingsKeys.lanSyncClientServerName);

  String get clientServerAddress => _connected?.displayAddress ?? '';

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    final syncAt = GStorage.getSetting(SettingsKeys.lanSyncLastSyncAt);
    if (syncAt > 0) {
      _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(syncAt);
    }
    if (isServerSupported) {
      if (serverEnabled) {
        await _startServer();
      } else {
        _serverState = LanServerState.disabled;
      }
    }
    if (isClientSupported) {
      _watchHistoryChanges();
      if (clientEnabled) {
        _mediaController.restoreCachedLanLibrary();
        _startTimer();
        _clientState = LanClientState.discovering;
        unawaited(_discoverAndSync(quiet: true));
      } else {
        _clientState = LanClientState.disabled;
      }
    }
    notifyListeners();
  }

  // ============ 桌面端服务 ============

  Future<void> setServerEnabled(bool enabled) async {
    await GStorage.putSetting(SettingsKeys.lanSyncServerEnable, enabled);
    if (enabled) {
      await _startServer();
    } else {
      await _stopServer();
    }
    notifyListeners();
  }

  Future<void> _startServer() async {
    if (!isServerSupported) return;
    if (_server?.isRunning ?? false) {
      _serverState = LanServerState.running;
      notifyListeners();
      return;
    }
    if (_serverStarting) return;
    _serverStarting = true;
    _serverState = LanServerState.starting;
    _serverError = '';
    notifyListeners();
    try {
      final serverId = await _ensureSetting(
        SettingsKeys.lanSyncServerId,
        () => LanSyncServer.randomHex(8),
      );
      final token = await _ensureSetting(
        SettingsKeys.lanSyncServerToken,
        () => LanSyncServer.randomHex(24),
      );
      final code = await _ensureSetting(
        SettingsKeys.lanSyncServerPairingCode,
        LanSyncServer.randomPairingCode,
      );
      final name = await _ensureSetting(
        SettingsKeys.lanSyncServerName,
        () => Platform.localHostname,
      );
      final port = GStorage.getSetting(SettingsKeys.lanSyncServerPort);
      final server = LanSyncServer(
        serverId: serverId,
        serverName: name,
        token: token,
        pairingCode: code,
        port: port <= 0 ? kLanSyncHttpPort : port,
        mediaController: _mediaController,
        historyStore: _historyStore,
        collectStore: _collectStore,
        onCollectChanged: _collectController.loadCollectibles,
      );
      _server = server;
      await server.start();
      if (!serverEnabled) {
        // 启动期间用户关闭了共享：立即回收监听。
        _server = null;
        _serverState = LanServerState.disabled;
        await server.stop();
      } else {
        await GStorage.putSetting(
          SettingsKeys.lanSyncServerPort,
          server.actualPort,
        );
        _serverAddresses = await server.localAddresses();
        _serverState = LanServerState.running;
        KazumiLogger().i(
          'LanSync: server running at ${_serverAddresses.join(", ")}:'
          '${server.actualPort}',
          // INFO 默认不落文件，关键状态用 forceLog 才能在日志里回溯。
          forceLog: true,
        );
      }
    } catch (e, stackTrace) {
      _server = null;
      _serverState = LanServerState.error;
      _serverError = e.toString();
      KazumiLogger().e(
        'LanSync: failed to start server',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _serverStarting = false;
    }
    notifyListeners();
  }

  Future<void> _stopServer() async {
    final server = _server;
    _server = null;
    _serverState = LanServerState.disabled;
    _serverError = '';
    _serverAddresses = const [];
    if (server != null) await server.stop();
    notifyListeners();
  }

  Future<void> refreshPairingCode() async {
    final code = LanSyncServer.randomPairingCode();
    await GStorage.putSetting(SettingsKeys.lanSyncServerPairingCode, code);
    _server?.pairingCode = code;
    notifyListeners();
  }

  /// 重新生成访问 token：已配对的手机需要重新输入配对码。
  Future<void> regenerateServerToken() async {
    final token = LanSyncServer.randomHex(24);
    await GStorage.putSetting(SettingsKeys.lanSyncServerToken, token);
    _server?.token = token;
    notifyListeners();
  }

  Future<String> _ensureSetting(
    SettingKey<String> key,
    String Function() generator,
  ) async {
    final current = GStorage.getSetting(key).trim();
    if (current.isNotEmpty) return current;
    final value = generator();
    await GStorage.putSetting(key, value);
    return value;
  }

  // ============ 手机端客户端 ============

  Future<void> setClientEnabled(bool enabled) async {
    await GStorage.putSetting(SettingsKeys.lanSyncClientEnable, enabled);
    if (enabled) {
      _mediaController.restoreCachedLanLibrary();
      _clientState = LanClientState.discovering;
      _startTimer();
      unawaited(_discoverAndSync());
    } else {
      _stopTimer();
      _historyPushTimer?.cancel();
      _historyPushTimer = null;
      _historyPushDirty = false;
      _clientState = LanClientState.disabled;
      _connected = null;
      _clientError = '';
      await LanLibraryCache.clear();
      _mediaController.clearLanLibrary();
    }
    notifyListeners();
  }

  Future<void> setAutoSync(bool enabled) async {
    await GStorage.putSetting(SettingsKeys.lanSyncAutoSync, enabled);
    if (enabled && clientEnabled) {
      _startTimer();
      unawaited(_discoverAndSync(quiet: true));
    } else {
      _stopTimer();
    }
    notifyListeners();
  }

  Future<void> setCollectEnabled(bool enabled) async {
    await GStorage.putSetting(SettingsKeys.lanSyncCollectEnable, enabled);
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!isClientSupported || !clientEnabled || !autoSync) return;
    _timer = Timer.periodic(_syncInterval, (_) {
      unawaited(_discoverAndSync(quiet: true));
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// 播放进度落库后择机推给桌面端。
  ///
  /// 播放时历史每秒写一次，因此这里用「触发后固定间隔再推一次」的节流，
  /// 而不是每次变更都重置的防抖——否则连续播放期间永远不会真正推送。
  void _watchHistoryChanges() {
    _historyChangesSubscription ??= _historyStore.changes.listen((_) {
      _scheduleHistoryPush();
    });
  }

  void _scheduleHistoryPush() {
    if (!isClientSupported || !clientEnabled || !autoSync) return;
    // 未连接时不做额外探测，交给 3 分钟的定时同步去重连。
    if (!isClientConnected) return;
    if (!GStorage.getSetting(SettingsKeys.lanSyncClientToken).isNotEmpty) {
      return;
    }
    _historyPushDirty = true;
    if (_historyPushTimer?.isActive ?? false) return;
    _historyPushTimer = Timer(_historyPushDelay, () {
      if (!_historyPushDirty) return;
      _historyPushDirty = false;
      if (_syncing) {
        // 正在同步：留给下一次变更触发。
        return;
      }
      unawaited(_discoverAndSync(quiet: true));
    });
  }

  /// 立即同步（设置页按钮 / 媒体库刷新）。
  Future<void> syncNow({bool quiet = false}) => _discoverAndSync(quiet: quiet);

  Future<void> discoverServers() async {
    if (!isClientSupported) return;
    _clientError = '';
    if (!isClientConnected) {
      _clientState = LanClientState.discovering;
    }
    notifyListeners();
    final servers = await LanDiscovery.discover();
    final known = _knownServer();
    _discovered = _mergeServers(servers, known);
    if (_discovered.isEmpty) {
      _clientState = clientEnabled
          ? LanClientState.offline
          : LanClientState.disabled;
    } else if (!isClientConnected) {
      _clientState = hasClientToken
          ? LanClientState.offline
          : LanClientState.unpaired;
    }
    notifyListeners();
  }

  LanDiscoveredServer? _knownServer() {
    final host = GStorage.getSetting(SettingsKeys.lanSyncClientHost);
    final port = GStorage.getSetting(SettingsKeys.lanSyncClientPort);
    final id = GStorage.getSetting(SettingsKeys.lanSyncClientServerId);
    final name = GStorage.getSetting(SettingsKeys.lanSyncClientServerName);
    if (host.isEmpty || port <= 0 || id.isEmpty) return null;
    return LanDiscoveredServer(
      host: host,
      info: LanServerInfo(
        protocol: kLanSyncProtocolVersion,
        serverId: id,
        name: name,
        version: '',
        httpPort: port,
      ),
    );
  }

  List<LanDiscoveredServer> _mergeServers(
    List<LanDiscoveredServer> discovered,
    LanDiscoveredServer? known,
  ) {
    final byId = <String, LanDiscoveredServer>{
      for (final server in discovered) server.serverId: server,
    };
    if (known != null && !byId.containsKey(known.serverId)) {
      byId[known.serverId] = known;
    }
    return byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> _discoverAndSync({bool quiet = false}) async {
    if (!isClientSupported || !clientEnabled) return;
    if (_syncing) return;
    _syncing = true;
    if (!quiet && !isClientConnected) {
      _clientState = LanClientState.discovering;
      notifyListeners();
    }
    try {
      final token = GStorage.getSetting(SettingsKeys.lanSyncClientToken);
      if (token.isEmpty) {
        final servers = await LanDiscovery.discover();
        _discovered = _mergeServers(servers, _knownServer());
        _clientState = _discovered.isEmpty
            ? LanClientState.offline
            : LanClientState.unpaired;
        _clientError = _discovered.isEmpty ? '未发现桌面端' : '';
        return;
      }

      final server = await _findPairedServer();
      if (server == null) {
        if (_discovered.isNotEmpty) {
          _clientState = LanClientState.unpaired;
          _clientError = '桌面端配对信息已变化，请重新输入配对码';
        } else {
          _clientState = LanClientState.offline;
          _clientError = '桌面端未连接';
        }
        return;
      }
      _connected = server;
      _clientState = LanClientState.connecting;
      notifyListeners();
      await _syncWithServer(server);
    } on LanUnauthorizedException {
      await GStorage.putSetting(SettingsKeys.lanSyncClientToken, '');
      _connected = null;
      _clientState = LanClientState.unpaired;
      _clientError = '配对已失效，请重新输入桌面端配对码';
      KazumiLogger().w('LanSync: client token rejected');
    } catch (e, stackTrace) {
      _clientState = LanClientState.offline;
      _clientError = '同步失败：$e';
      KazumiLogger().w(
        'LanSync: client sync failed',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<LanDiscoveredServer?> _findPairedServer() async {
    final storedId = GStorage.getSetting(SettingsKeys.lanSyncClientServerId);
    final storedHost = GStorage.getSetting(SettingsKeys.lanSyncClientHost);
    final storedPort = GStorage.getSetting(SettingsKeys.lanSyncClientPort);

    if (storedHost.isNotEmpty && storedPort > 0) {
      final probed = await LanDiscovery.probe(storedHost, storedPort);
      if (probed != null && (storedId.isEmpty || probed.serverId == storedId)) {
        _discovered = _mergeServers(_discovered, probed);
        return probed;
      }
    }

    final servers = await LanDiscovery.discover();
    _discovered = _mergeServers(servers, _knownServer());
    for (final server in _discovered) {
      if (storedId.isNotEmpty && server.serverId == storedId) return server;
    }
    // token 存在但 serverId 为空（旧数据）：只接受唯一在线服务端。
    if (storedId.isEmpty && _discovered.length == 1) return _discovered.first;
    return null;
  }

  Future<void> _syncWithServer(LanDiscoveredServer server) async {
    final token = GStorage.getSetting(SettingsKeys.lanSyncClientToken);
    final history = _historyStore.exportForServer(server.serverId);
    final collectEnabled = this.collectEnabled;
    final localCollectibles = collectEnabled
        ? _collectStore.exportCollectibles()
        : const <LanCollectibleEntry>[];
    final localTombstones = collectEnabled
        ? _collectStore.exportTombstones()
        : const <LanCollectTombstone>[];
    final response = await _requestJson(
      method: 'POST',
      uri: server.baseUri.replace(path: '/api/v1/sync'),
      token: token,
      body: {
        'protocol': kLanSyncProtocolVersion,
        'history': history.map((entry) => entry.toJson()).toList(),
        if (collectEnabled) ...{
          'collectibles': localCollectibles
              .map((entry) => entry.toJson())
              .toList(),
          'collectTombstones': localTombstones
              .map((entry) => entry.toJson())
              .toList(),
        },
      },
      timeout: const Duration(seconds: 60),
    );
    final payload = LanSyncPayload.fromJson(response);
    if (payload.server.protocol != kLanSyncProtocolVersion ||
        payload.server.serverId != server.serverId) {
      throw const LanProtocolException('桌面端数据版本不兼容');
    }

    await GStorage.putSetting(SettingsKeys.lanSyncClientHost, server.host);
    await GStorage.putSetting(SettingsKeys.lanSyncClientPort, server.port);
    await GStorage.putSetting(
      SettingsKeys.lanSyncClientServerId,
      server.serverId,
    );
    await GStorage.putSetting(
      SettingsKeys.lanSyncClientServerName,
      payload.server.name.isNotEmpty ? payload.server.name : server.name,
    );

    await LanLibraryCache.save(payload);
    _mediaController.applyLanLibrary(
      serverName: payload.server.name.isNotEmpty
          ? payload.server.name
          : server.name,
      folders: payload.toLocalFolders(
        (remotePath) => buildLanStreamUrl(
          host: server.host,
          port: server.port,
          token: token,
          remotePath: remotePath,
        ),
      ),
      folderScrapeResults: payload.toLocalFolderScrapeResults(),
      remoteFileScrapeResults: payload.toLocalFileScrapeResults(),
    );

    final mappedHistory = [
      for (final entry in payload.history)
        entry.copyWith(
          episodePageUrl: entry.episodePageUrl.isEmpty
              ? entry.episodePageUrl
              : lanFilePath(server.serverId, entry.episodePageUrl),
        ),
    ];
    final writtenHistory = await _historyStore.applyEntries(mappedHistory);
    _mediaController.refreshLanResumePoints();

    if (collectEnabled) {
      // 请求期间用户可能又改了状态，落盘前用最新本地数据再合并一次。
      final mergedCollect = mergeLanCollectibles(
        localCollectibles: _collectStore.exportCollectibles(),
        localTombstones: _collectStore.exportTombstones(),
        remoteCollectibles: payload.collectibles,
        remoteTombstones: payload.collectTombstones,
      );
      final applied = await _collectStore.applyMerged(mergedCollect);
      if (applied > 0) {
        _collectController.loadCollectibles();
      }
    }

    _lastSyncAt = DateTime.now();
    _lastFolderCount = payload.folders.length;
    _lastFileCount = payload.folders.fold(
      0,
      (sum, folder) => sum + folder.files.length,
    );
    await GStorage.putSetting(
      SettingsKeys.lanSyncLastSyncAt,
      _lastSyncAt!.millisecondsSinceEpoch,
    );
    _connected = server;
    _clientState = LanClientState.connected;
    _clientError = '';
    KazumiLogger().i(
      'LanSync: synced $_lastFolderCount folders / $_lastFileCount files '
      'from $server.name (${server.displayAddress}), '
      '${payload.history.length} history entries, '
      'wrote $writtenHistory',
      forceLog: true,
    );
    notifyListeners();
  }

  bool hasTokenFor(String serverId) {
    final token = GStorage.getSetting(SettingsKeys.lanSyncClientToken);
    final storedId = GStorage.getSetting(SettingsKeys.lanSyncClientServerId);
    return token.isNotEmpty && storedId == serverId;
  }

  Future<LanPairResult> connectServer(LanDiscoveredServer server) async {
    if (hasTokenFor(server.serverId)) {
      _connected = server;
      _syncing = true;
      _clientState = LanClientState.connecting;
      notifyListeners();
      try {
        await _syncWithServer(server);
        return const LanPairResult.ok('已连接桌面端并完成同步');
      } catch (e) {
        if (e is LanUnauthorizedException) {
          await GStorage.putSetting(SettingsKeys.lanSyncClientToken, '');
          _clientState = LanClientState.unpaired;
          return const LanPairResult.failed('配对已失效，请重新输入配对码');
        }
        _clientState = LanClientState.offline;
        return LanPairResult.failed('连接失败：$e');
      } finally {
        _syncing = false;
        notifyListeners();
      }
    }
    return const LanPairResult.failed('需要输入桌面端显示的 6 位配对码');
  }

  Future<LanPairResult> pairWithCode(
    LanDiscoveredServer server,
    String code,
  ) async {
    final trimmed = code.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(trimmed)) {
      return const LanPairResult.failed('请输入 6 位数字配对码');
    }
    if (_pairing) return const LanPairResult.failed('正在配对，请稍候');
    _pairing = true;
    _clientError = '';
    notifyListeners();
    try {
      final response = await _requestJson(
        method: 'POST',
        uri: server.baseUri.replace(path: '/api/v1/pair'),
        body: {'code': trimmed, 'deviceName': Platform.localHostname},
        timeout: const Duration(seconds: 10),
      );
      final token = response['token']?.toString() ?? '';
      if (token.isEmpty) {
        return const LanPairResult.failed('桌面端返回的配对信息无效');
      }
      final infoRaw = response['server'];
      final info = infoRaw is Map
          ? LanServerInfo.fromJson(Map<String, dynamic>.from(infoRaw))
          : server.info;
      final paired = LanDiscoveredServer(host: server.host, info: info);
      await GStorage.putSetting(SettingsKeys.lanSyncClientToken, token);
      await GStorage.putSetting(
        SettingsKeys.lanSyncClientServerId,
        info.serverId,
      );
      await GStorage.putSetting(
        SettingsKeys.lanSyncClientServerName,
        info.name,
      );
      await GStorage.putSetting(SettingsKeys.lanSyncClientHost, paired.host);
      await GStorage.putSetting(SettingsKeys.lanSyncClientPort, paired.port);
      _discovered = _mergeServers(_discovered, paired);
      _connected = paired;
      _syncing = true;
      _clientState = LanClientState.connecting;
      notifyListeners();
      await _syncWithServer(paired);
      return const LanPairResult.ok('配对成功，已同步桌面端媒体库');
    } on LanUnauthorizedException {
      _clientState = LanClientState.unpaired;
      return const LanPairResult.failed('配对码已过期，请在桌面端刷新后重试');
    } catch (e) {
      _clientState = LanClientState.error;
      _clientError = e.toString();
      return LanPairResult.failed('配对失败：$e');
    } finally {
      _pairing = false;
      _syncing = false;
      notifyListeners();
    }
  }

  Future<LanPairResult> connectManual(String address, {String? code}) async {
    final parsed = parseManualAddress(address);
    if (parsed == null) {
      return const LanPairResult.failed('地址格式应为 192.168.1.2:45870');
    }
    final server = await LanDiscovery.probe(parsed.$1, parsed.$2);
    if (server == null) {
      return const LanPairResult.failed('无法连接该地址，请检查 IP、端口与防火墙');
    }
    _discovered = _mergeServers(_discovered, server);
    notifyListeners();
    if (code != null && code.trim().isNotEmpty) {
      return pairWithCode(server, code);
    }
    return connectServer(server);
  }

  Future<void> forgetPairing() async {
    await GStorage.putSetting(SettingsKeys.lanSyncClientToken, '');
    await GStorage.putSetting(SettingsKeys.lanSyncClientServerId, '');
    await GStorage.putSetting(SettingsKeys.lanSyncClientServerName, '');
    await GStorage.putSetting(SettingsKeys.lanSyncClientHost, '');
    await GStorage.putSetting(SettingsKeys.lanSyncClientPort, 0);
    await GStorage.putSetting(SettingsKeys.lanSyncLastSyncAt, 0);
    await LanLibraryCache.clear();
    _connected = null;
    _lastSyncAt = null;
    _lastFolderCount = 0;
    _lastFileCount = 0;
    _clientState = clientEnabled
        ? LanClientState.discovering
        : LanClientState.disabled;
    await _mediaController.clearLanLibrary();
    notifyListeners();
    if (clientEnabled) {
      unawaited(_discoverAndSync(quiet: true));
    }
  }

  /// 解析 `host` / `host:port` / `http://host:port`。
  static (String host, int port)? parseManualAddress(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    final port = uri.hasPort ? uri.port : kLanSyncHttpPort;
    if (port <= 0 || port > 65535) return null;
    return (uri.host, port);
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required Uri uri,
    String? token,
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null && token.isNotEmpty) {
        request.headers.set('x-kazumi-token', token);
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode == HttpStatus.unauthorized) {
        throw const LanUnauthorizedException();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LanHttpException(response.statusCode, text);
      }
      final json = jsonDecode(text);
      if (json is! Map) {
        throw const LanProtocolException('响应格式无效');
      }
      return Map<String, dynamic>.from(json);
    } finally {
      client.close(force: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_initialized) return;
    if (state == AppLifecycleState.resumed) {
      if (isServerSupported &&
          serverEnabled &&
          !(_server?.isRunning ?? false)) {
        unawaited(_startServer());
      }
      if (isClientSupported && clientEnabled && autoSync) {
        unawaited(_discoverAndSync(quiet: true));
      }
    } else if (state == AppLifecycleState.paused) {
      // 退到后台前把最新进度推回桌面端（失败静默，下次启动重试）。
      if (isClientSupported && clientEnabled && autoSync) {
        unawaited(_discoverAndSync(quiet: true));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    _historyPushTimer?.cancel();
    _historyPushTimer = null;
    unawaited(_historyChangesSubscription?.cancel());
    _historyChangesSubscription = null;
    unawaited(_server?.stop());
    _server = null;
    super.dispose();
  }
}

class LanUnauthorizedException implements Exception {
  const LanUnauthorizedException();
}

class LanProtocolException implements Exception {
  const LanProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LanHttpException implements Exception {
  const LanHttpException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'HTTP $statusCode';
}
