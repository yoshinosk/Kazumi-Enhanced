import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/magnet/aria2_client.dart';
import 'package:kazumi/services/magnet/tracker_updater.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 内置 Aria2 引擎的运行状态。
enum Aria2EngineState {
  stopped,
  starting,
  running,
  stopping,
  error,
}

/// 内置磁力下载引擎：负责定位 / 启动 / 监护一个随应用运行的 aria2c 进程，
/// 并把 RPC 端点覆盖到 [Aria2Client]，使上层磁力下载完全托管给本引擎。
///
/// 仅面向桌面端（主要以 Windows 为目标）；进程以隐藏窗口方式运行，
/// 应用退出时自动清理，避免残留。
class Aria2Engine {
  final Aria2Client _aria2 = Aria2Client();

  Process? _process;
  Timer? _watchTimer;
  Timer? _restartTimer;
  bool _shouldRun = false;
  int _restartAttempts = 0;
  bool _stopping = false;

  String? _binary;
  String? _dataDir;
  String? _activeRpcUrl;

  Aria2EngineState _state = Aria2EngineState.stopped;
  Aria2EngineState get state => _state;

  String? _lastError;
  String? get lastError => _lastError;

  /// 引擎状态变化回调（供 Controller 刷新 observable）。
  void Function(Aria2EngineState state)? onStateChanged;

  int? get pid => _process?.pid;
  String? get activeRpcUrl => _activeRpcUrl;
  bool get isRunning => _state == Aria2EngineState.running && _process != null;

  static bool get supported => Platform.isWindows || Platform.isLinux;

  static bool get enabledBySettings =>
      GStorage.getSetting(SettingsKeys.magnetEngineMode) != 'remote';

  /// 定位 aria2c 可执行文件；找不到返回 null。
  Future<String?> resolveBinary() async {
    if (_binary != null) return _binary;
    final candidates = <String>[];

    final configured =
        GStorage.getSetting(SettingsKeys.aria2ExecutablePath).trim();
    if (configured.isNotEmpty) {
      candidates.add(configured);
      if (await File(configured).exists()) {
        _binary = configured;
        return _binary;
      }
    }

    // 应用可执行文件旁边捆绑的二进制。
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      candidates.addAll([
        p.join(exeDir, 'aria2c.exe'),
        p.join(exeDir, 'data', 'aria2', 'aria2c.exe'),
        p.join(exeDir, 'aria2', 'aria2c.exe'),
      ]);
    } catch (_) {}

    for (final c in candidates) {
      if (await File(c).exists()) {
        _binary = c;
        return _binary;
      }
    }

    // PATH 中的 aria2c.exe。
    try {
      final which = await Process.run(
        Platform.isWindows ? 'where.exe' : 'which',
        [Platform.isWindows ? 'aria2c.exe' : 'aria2c'],
        runInShell: true,
      );
      final out = which.stdout.toString().trim();
      if (which.exitCode == 0 && out.isNotEmpty) {
        final firstLine = out.split(RegExp(r'\r?\n')).first.trim();
        if (await File(firstLine).exists()) {
          _binary = firstLine;
          return _binary;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<String> _ensureDataDir() async {
    if (_dataDir != null) return _dataDir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'aria2'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dataDir = dir.path;
    return dir.path;
  }

  Future<int> _pickFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<int> _resolveRpcPort() async {
    final cfg = GStorage.getSetting(SettingsKeys.aria2RpcPort);
    if (cfg > 0) return cfg;
    return _pickFreePort();
  }

  Future<int> _resolveListenPort() async {
    final v = GStorage.getSetting(SettingsKeys.aria2ListenPort);
    return v > 0 ? v : 6881;
  }

  String _newSecret() {
    final rand = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final sb = StringBuffer('kazumi-');
    for (var i = 0; i < 24; i++) {
      sb.write(chars[rand.nextInt(chars.length)]);
    }
    return sb.toString();
  }

  /// 根据设置生成 aria2.conf 内容。
  Future<String> _buildConfig(
    String dataDir,
    int rpcPort,
    String secret,
    int listenPort,
  ) async {
    final g = GStorage.getSetting;
    final lines = <String>[];

    final configuredDir = GStorage.getSetting(SettingsKeys.aria2DownloadDir).trim();
    final String dir;
    if (configuredDir.isEmpty) {
      final downloadsPath = (await getDownloadsDirectory())?.path;
      dir = (downloadsPath != null && downloadsPath.isNotEmpty)
          ? downloadsPath
          : (await getApplicationDocumentsDirectory()).path;
    } else {
      dir = configuredDir;
    }
    lines.add('dir=$dir');
    lines.add('file-allocation=falloc');

    lines.add(
        'max-concurrent-downloads=${g(SettingsKeys.aria2MaxConcurrentDownloads)}');
    lines.add('max-connection-per-server=16');
    lines.add('split=16');
    lines.add('continue=true');
    lines.add('allow-overwrite=false');

    lines.add('listen-port=$listenPort');
    lines.add('dht-listen-port=$listenPort');
    lines.add('bt-tracker-interval=120');
    lines.add('timeout=60');
    lines.add('connect-timeout=20');
    lines.add('bt-tracker-connect-timeout=20');
    lines.add('bt-tracker-timeout=20');
    lines.add('peer-connect-timeout=20');

    lines.add('seed-time=${g(SettingsKeys.aria2SeedTime)}');
    lines.add('seed-ratio=${g(SettingsKeys.aria2SeedRatio).toStringAsFixed(1)}');

    final upLimitKb = g(SettingsKeys.aria2MaxUploadLimitKb);
    lines.add(upLimitKb > 0
        ? 'max-overall-upload-limit=${upLimitKb * 1024}'
        : 'max-overall-upload-limit=0');
    lines.add('max-overall-download-limit=0');
    lines.add('bt-max-peers=${g(SettingsKeys.aria2MaxPeers)}');

    lines.add('auto-save-interval=30');
    lines.add('save-session=${p.join(dataDir, 'session.txt')}');
    lines.add('save-session-interval=600');
    lines.add('bt-save-metadata=true');
    lines.add('bt-load-saved-metadata=true');

    lines.add(
        'enable-dht=${g(SettingsKeys.aria2EnableDht) ? 'true' : 'false'}');
    lines
        .add('enable-dht6=${g(SettingsKeys.aria2EnableDht6) ? 'true' : 'false'}');
    lines.add('dht-file-path=${p.join(dataDir, 'dht.dat')}');
    lines.add('dht-file-path6=${p.join(dataDir, 'dht6.dat')}');

    lines.add(
        'enable-upnp=${g(SettingsKeys.aria2EnableUpnp) ? 'true' : 'false'}');
    lines.add(
        'enable-nat-pmp=${g(SettingsKeys.aria2EnableNatPmp) ? 'true' : 'false'}');

    // 对等保护基础参数
    lines.add('bt-request-peer-speed-limit=512K');
    lines.add('bt-min-crypto-level=arc4');

    // RPC
    lines.add('enable-rpc=true');
    lines.add('rpc-listen-all=false');
    lines.add('rpc-listen-port=$rpcPort');
    lines.add('rpc-secret=$secret');

    final trackers = TrackerUpdater.instance.cachedTrackers();
    if (trackers.isNotEmpty) {
      lines.add('bt-tracker=${trackers.join(',')}');
    }
    return lines.join('\n');
  }

  /// 启动引擎，返回 RPC 是否就绪。
  Future<bool> start() async {
    await _shutdownProcess();
    _state = Aria2EngineState.starting;
    _notify();
    _shouldRun = true;
    _stopping = false;
    _restartAttempts = 0;

    try {
      final binary = await resolveBinary();
      if (binary == null) {
        _lastError = '未找到 aria2c.exe：请在“磁力下载”设置中指定，'
            '或将其放入应用目录（data/aria2/）并重启应用';
        _state = Aria2EngineState.error;
        _notify();
        return false;
      }

      final dataDir = await _ensureDataDir();
      final rpcPort = await _resolveRpcPort();
      final secret = _newSecret();
      final listenPort = await _resolveListenPort();
      final confPath = p.join(dataDir, 'aria2.conf');
      final conf = await _buildConfig(dataDir, rpcPort, secret, listenPort);
      await File(confPath).writeAsString(conf);

      _process = await Process.start(
        binary,
        ['--conf-path=$confPath'],
        runInShell: false,
      );
      _watchProcess(_process!);

      final ready = await _waitRpc(rpcPort, secret);
      if (!ready) {
        _lastError = '引擎已启动但 RPC 未就绪，端口可能被占用，请调整监听端口';
        _state = Aria2EngineState.error;
        _notify();
        return false;
      }

      _activeRpcUrl = 'http://127.0.0.1:$rpcPort/jsonrpc';
      Aria2Client.overrideRpcUrl = _activeRpcUrl;
      Aria2Client.overrideSecret = secret;

      // 将已缓存的 tracker 立即应用到运行中的引擎（尽力而为）。
      await _pushTrackersToRuntime();

      _state = Aria2EngineState.running;
      _notify();
      KazumiLogger().i(
          'Aria2Engine: started rpc=$_activeRpcUrl pid=${_process?.pid}');
      return true;
    } catch (e) {
      _lastError = '启动内置引擎失败：$e';
      _state = Aria2EngineState.error;
      _notify();
      KazumiLogger().e('Aria2Engine: start failed', error: e);
      return false;
    }
  }

  Future<void> _pushTrackersToRuntime() async {
    final trackers = TrackerUpdater.instance.cachedTrackers();
    if (trackers.isEmpty) return;
    await _aria2.changeGlobalOptionValue('bt-tracker', trackers.join(','));
  }

  /// 运行中的引擎若存在，立即下发缓存的 tracker 列表。
  Future<void> applyTrackers() => _pushTrackersToRuntime();

  void _notify() => onStateChanged?.call(_state);

  Future<bool> _waitRpc(int port, String secret) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (_process == null) return false;
      final ok = await Aria2Client.rpcProbe(
        'http://127.0.0.1:$port/jsonrpc',
        secret,
      );
      if (ok) return true;
      await Future.delayed(const Duration(milliseconds: 350));
    }
    return false;
  }

  void _watchProcess(Process process) {
    process.exitCode.then((_) => _onProcessExited());

    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      if (_process != process) return;
      final alive = await _isAlive(process.pid);
      if (!alive) _onProcessExited();
    });
  }

  Future<bool> _isAlive(int pid) async {
    try {
      final result = await Process.run(
        Platform.isWindows ? 'tasklist' : 'ps',
        Platform.isWindows ? ['/FI', 'PID eq $pid', '/NH'] : ['-p', '$pid'],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return true;
    }
  }

  void _onProcessExited() {
    _watchTimer?.cancel();
    _watchTimer = null;
    if (_stopping || !_shouldRun) return;
    _process = null;
    Aria2Client.overrideRpcUrl = null;
    Aria2Client.overrideSecret = null;
    _activeRpcUrl = null;
    _state = Aria2EngineState.error;
    _lastError = 'aria2c 进程意外退出，准备自动重启';
    _notify();
    _scheduleRestart();
  }

  void _scheduleRestart() {
    if (!_shouldRun || _restartAttempts >= 5) return;
    _restartAttempts++;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(seconds: 8), () {
      _restartTimer = null;
      if (_shouldRun) {
        KazumiLogger().i('Aria2Engine: auto restart attempt');
        // 重新走一遍 start 的信号：保留 _restartAttempts 计数，见 start() 内清零。
        _restartAttempts = 0;
        start();
      }
    });
  }

  /// 停止引擎并清理（不重启）。
  Future<void> stop() async {
    _shouldRun = false;
    await _shutdownProcess();
    _notify();
  }

  /// 设置变化后调用：引擎运行中且仍启用则重启使配置生效。
  Future<void> applySettingsChanged() async {
    if (!enabledBySettings) {
      await stop();
      return;
    }
    if (!_shouldRun) return;
    final wasRunning = _shouldRun;
    await _shutdownNow();
    if (wasRunning) {
      await start();
    }
  }

  Future<void> _shutdownNow() async {
    _stopping = true;
    _stopTimers();
    _clearEndpointOverride();
    final process = _process;
    _process = null;
    if (process != null) {
      try {
        process.kill();
      } catch (_) {}
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    _stopping = false;
    _state = Aria2EngineState.stopped;
  }

  Future<void> _shutdownProcess() async {
    if (_process == null) return;
    await _shutdownNow();
  }

  void _stopTimers() {
    _watchTimer?.cancel();
    _watchTimer = null;
    _restartTimer?.cancel();
    _restartTimer = null;
  }

  void _clearEndpointOverride() {
    Aria2Client.overrideRpcUrl = null;
    Aria2Client.overrideSecret = null;
    _activeRpcUrl = null;
  }

  /// 应用退出时调用：终止引擎进程并清理资源。
  Future<void> dispose() async {
    _shouldRun = false;
    await _shutdownNow();
  }
}