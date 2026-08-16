import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:kazumi/services/logging/logger.dart';

/// Android 后台下载服务
///
/// 使用 Foreground Service 保持 app 进程存活，防止系统在后台时杀死下载进程。
/// 下载逻辑仍在主 Isolate 运行，此服务仅负责：
/// 1. 显示通知栏进度
/// 2. 保持进程存活
/// 3. 提供通知栏交互（暂停全部）
///
/// 该服务是应用级的单例前台服务，通过「租约」机制被多个下载功能共享：
/// - `http`：在线视频（DownloadController）
/// - `magnet`：磁力下载（MagnetController）
/// 任一功能持有租约期间服务保持运行；全部释放后才停止。
/// 通知栏内容按「最后更新的租约」渲染，租约释放时回退渲染仍活跃的租约。
class BackgroundDownloadService {
  static final BackgroundDownloadService _instance =
      BackgroundDownloadService._internal();
  factory BackgroundDownloadService() => _instance;
  BackgroundDownloadService._internal();

  /// 在线视频下载的租约名。
  static const String httpLease = 'http';

  /// 磁力下载的租约名。
  static const String magnetLease = 'magnet';

  bool _isInitialized = false;
  bool _isRunning = false;

  /// 当前持有租约的功能名。
  final Set<String> _leases = {};

  /// 服务启停串行化队列：startService 是异步的（含权限弹窗，可能数秒），
  /// 期间若租约全部释放，release 必须等服务启动完成后才能判断停止，
  /// 否则服务会以「零租约」状态常驻。
  Future<void> _opQueue = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _opQueue.then((_) => action());
    _opQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// 各租约最近一次的通知内容（租约释放时回退渲染用）。
  final Map<String, String> _leaseTitles = {};
  final Map<String, String> _leaseTexts = {};

  /// 当前渲染内容的租约名。
  String? _renderLease;

  void Function()? onPauseAll;
  void Function()? onNavigateToDownloadRequested;

  /// 返回 true 表示用户同意请求权限，false 表示用户拒绝
  Future<bool> Function()? onNotificationPermissionRequired;

  bool get isSupported => Platform.isAndroid;
  bool get isRunning => _isRunning;

  /// 指定功能是否持有租约（服务可能被其他功能持有）。
  bool isHeldBy(String lease) => _leases.contains(lease);

  Future<void> init() async {
    if (!isSupported || _isInitialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'kazumi_download_channel',
        channelName: '下载服务',
        channelDescription: '视频下载后台服务',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    FlutterForegroundTask.initCommunicationPort();

    _isInitialized = true;
    KazumiLogger().i('BackgroundDownloadService: initialized');
  }

  Future<bool> needsNotificationPermission() async {
    if (!isSupported) return false;
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    return permission != NotificationPermission.granted;
  }

  Future<bool> requestNotificationPermission() async {
    if (!isSupported) return true;
    final result = await FlutterForegroundTask.requestNotificationPermission();
    return result == NotificationPermission.granted;
  }

  /// 功能申请持有前台服务。返回服务是否可用（运行中）。
  Future<bool> acquire(String lease) async {
    if (!isSupported) return false;
    return _serialized(() async {
      if (_leases.add(lease)) {
        KazumiLogger().i('BackgroundDownloadService: acquired by "$lease"');
      }
      if (_isRunning) return true;
      final ok = await startService();
      return ok;
    });
  }

  /// 功能释放前台服务；全部租约释放后停止服务。
  Future<void> release(String lease) async {
    if (!isSupported) return;
    await _serialized(() async {
      if (!_leases.remove(lease)) return;
      KazumiLogger().i('BackgroundDownloadService: released by "$lease"');
      _leaseTitles.remove(lease);
      _leaseTexts.remove(lease);
      if (_renderLease == lease) {
        _renderLease = null;
        // 回退渲染仍活跃的租约内容（任一）。
        for (final other in _leases) {
          final title = _leaseTitles[other];
          if (title != null) {
            _renderLease = other;
            await updateServiceSafe(
              title: title,
              text: _leaseTexts[other] ?? '',
            );
            break;
          }
        }
      }
      if (_leases.isEmpty && _isRunning) {
        await stopService();
      }
    });
  }

  /// 更新指定租约的通知栏内容。仅当该租约最后更新时立即渲染；
  /// 其他租约更新时由 [release] 的回退逻辑接管。
  Future<void> updateNotification(
    String lease, {
    required String title,
    required String text,
  }) async {
    if (!isSupported || !_isRunning || !_leases.contains(lease)) return;
    _leaseTitles[lease] = title;
    _leaseTexts[lease] = text;
    _renderLease = lease;
    await updateServiceSafe(title: title, text: text);
  }

  Future<void> updateServiceSafe({
    required String title,
    required String text,
  }) async {
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    } catch (e) {
      // 忽略更新失败，不影响下载
    }
  }

  Future<bool> startService() async {
    if (!isSupported) return false;
    if (_isRunning) return true;

    if (!_isInitialized) {
      await init();
    }

    final needsPermission = await needsNotificationPermission();
    if (needsPermission) {
      if (onNotificationPermissionRequired != null) {
        final userAgreed = await onNotificationPermissionRequired!();
        if (userAgreed) {
          final granted = await requestNotificationPermission();
          if (!granted) {
            KazumiLogger().w(
                'BackgroundDownloadService: notification permission denied by user');
          }
        } else {
          KazumiLogger()
              .i('BackgroundDownloadService: user declined permission dialog');
        }
      } else {
        // 没有设置回调，直接请求权限（兼容旧行为）
        final granted = await requestNotificationPermission();
        if (!granted) {
          KazumiLogger()
              .w('BackgroundDownloadService: notification permission denied');
        }
      }
    }

    try {
      final result = await FlutterForegroundTask.startService(
        notificationTitle: '正在下载',
        notificationText: '准备中...',
        notificationButtons: [
          const NotificationButton(id: 'pause_all', text: '暂停全部'),
        ],
        callback: _backgroundCallback,
      );

      _isRunning = result is ServiceRequestSuccess;

      if (_isRunning) {
        KazumiLogger().i('BackgroundDownloadService: service started');
      } else {
        KazumiLogger().w(
            'BackgroundDownloadService: service start returned non-success: $result');
      }
      return _isRunning;
    } catch (e) {
      KazumiLogger()
          .e('BackgroundDownloadService: failed to start service', error: e);
      return false;
    }
  }

  Future<void> stopService() async {
    if (!isSupported || !_isRunning) return;

    try {
      await FlutterForegroundTask.stopService();
      _isRunning = false;
      KazumiLogger().i('BackgroundDownloadService: service stopped');
    } catch (e) {
      KazumiLogger()
          .e('BackgroundDownloadService: failed to stop service', error: e);
    }
  }

  Future<void> updateProgress({
    required int activeCount,
    required int totalCount,
    required double overallProgress,
    required String speedText,
  }) async {
    if (!isSupported || !_isRunning) return;

    String title;
    String text;

    if (activeCount == 0) {
      title = '下载已暂停';
      text = '共 $totalCount 个任务';
    } else {
      final percent = (overallProgress * 100).toInt();
      title = '正在下载 ($activeCount/$totalCount)';
      text = '$percent% · $speedText';
    }

    await updateNotification(httpLease, title: title, text: text);
  }

  void handleNotificationAction(String buttonId) {
    if (buttonId == 'pause_all') {
      onPauseAll?.call();
    }
  }

  void handleNavigateToDownload() {
    onNavigateToDownloadRequested?.call();
  }

  void addTaskDataCallback(void Function(Object) callback) {
    FlutterForegroundTask.addTaskDataCallback(callback);
  }

  void removeTaskDataCallback(void Function(Object) callback) {
    FlutterForegroundTask.removeTaskDataCallback(callback);
  }
}

/// 后台任务回调（在独立 Isolate 中运行）
///
/// 注意：此回调主要用于保持服务存活和处理通知交互。
/// 实际下载逻辑在主 Isolate 中运行。
@pragma('vm:entry-point')
void _backgroundCallback() {
  FlutterForegroundTask.setTaskHandler(_DownloadTaskHandler());
}

class _DownloadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('BackgroundDownloadService: task handler started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // eventAction 配置为 nothing，不会触发
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('BackgroundDownloadService: notification button pressed: $id');
    FlutterForegroundTask.sendDataToMain(
        {'action': 'button_pressed', 'id': id});
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.sendDataToMain({'action': 'navigate_to_download'});
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {
    // 前台服务通知通常不可划掉
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint(
        'BackgroundDownloadService: task handler destroyed (isTimeout: $isTimeout)');
  }

  @override
  void onReceiveData(Object data) {
    debugPrint('BackgroundDownloadService: received data: $data');
  }
}
