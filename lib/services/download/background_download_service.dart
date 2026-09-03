import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/notification/app_notifications.dart';

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

  /// 最近一次 startService 失败时间：失败后冷却期内不再重试，
  /// 避免调用方（如磁力下载每 2s 一轮的租约同步）反复触发必败的
  /// 原生调用与异常日志。
  DateTime? _lastStartFailedAt;
  static const Duration _startRetryCooldown = Duration(minutes: 5);

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

  /// 本会话对通知权限询问的结果（null 表示尚未询问）。
  ///
  /// 权限被拒后（自定义弹窗「稍后再说」或系统弹窗拒绝）不再反复弹窗：
  /// startService 会在每次 acquire 时被重入，若不记忆拒绝结果，
  /// 磁力下载每 2 秒一次的状态同步会让权限弹窗无限重弹。
  bool? _notificationPermissionConsented;

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

    // 前台服务事件统一在本类处理（服务超时停止等），
    // 各 Controller 的回调只处理自己的按钮 / 导航消息，避免重复处理。
    FlutterForegroundTask.addTaskDataCallback(_onForegroundServiceEvent);

    _isInitialized = true;
    KazumiLogger().i('BackgroundDownloadService: initialized');
  }

  /// 前台服务事件（主 isolate）：目前处理系统超时停止。
  void _onForegroundServiceEvent(Object data) {
    if (data is Map && data['action'] == 'service_timeout') {
      _handleServiceTimeout();
    }
  }

  /// 前台服务因达到系统时限被停止（Android 15+ 对 dataSync 类型
  /// 前台服务有每日约 6 小时的限制）。
  ///
  /// 服务已实际停止但进程仍在运行：标记未运行并清空全部租约
  /// （当天再启动会被系统拒绝，保留租约只会挡住调用方的重试门控），
  /// 下载在进程存活期间仍继续；发通知告知用户。
  void _handleServiceTimeout() {
    if (!_isRunning) return;
    _isRunning = false;
    _leases.clear();
    _leaseTitles.clear();
    _leaseTexts.clear();
    _renderLease = null;
    KazumiLogger().w(
        'BackgroundDownloadService: service stopped by system timeout');
    unawaited(AppNotifications.show(
      title: '后台下载已暂停',
      body: '前台服务达到系统时限（Android 15+ 每日约 6 小时），'
          '重新打开应用后可继续下载',
    ));
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
      if (!_isRunning) {
        // 冷却期内（上次启动失败后 5 分钟）：不持有租约直接返回不可用，
        // 避免调用方高频重入（磁力下载每 2s 同步一次租约）反复触发
        // 必败的启动调用；冷却结束后下一轮 acquire 自动重试。
        final lastFailed = _lastStartFailedAt;
        if (lastFailed != null &&
            DateTime.now().difference(lastFailed) < _startRetryCooldown) {
          return false;
        }
      }
      final isNew = _leases.add(lease);
      if (isNew) {
        KazumiLogger().i('BackgroundDownloadService: acquired by "$lease"');
      }
      if (_isRunning) return true;
      try {
        final ok = await startService();
        if (!ok && isNew) {
          // 启动失败：回滚本次新增的租约，避免租约悬挂。否则
          // isHeldBy(lease) 会一直为真，调用方（如 DownloadController
          // 的 isHeldBy 门控）会误以为服务可用而不再重试。
          _rollbackLease(lease);
          KazumiLogger().w(
              'BackgroundDownloadService: lease "$lease" rolled back '
              '(service failed to start)');
        }
        return ok;
      } catch (e) {
        if (isNew) {
          _rollbackLease(lease);
        }
        KazumiLogger()
            .e('BackgroundDownloadService: acquire failed', error: e);
        return false;
      }
    });
  }

  void _rollbackLease(String lease) {
    _leases.remove(lease);
    _leaseTitles.remove(lease);
    _leaseTexts.remove(lease);
    if (_renderLease == lease) {
      _renderLease = null;
    }
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
      // 权限弹窗会话级去重：本会话已询问过（同意或拒绝）就不再重复
      // 弹自定义窗，避免每批任务 / 每次 acquire 重入时弹窗风暴；
      // 用户后续在系统设置手动授权后 needsPermission 自然变为 false。
      final consented = _notificationPermissionConsented;
      if (consented == null) {
        if (onNotificationPermissionRequired != null) {
          final userAgreed = await onNotificationPermissionRequired!();
          if (userAgreed) {
            final granted = await requestNotificationPermission();
            _notificationPermissionConsented = granted;
            if (!granted) {
              KazumiLogger().w(
                  'BackgroundDownloadService: notification permission denied by user');
            }
          } else {
            _notificationPermissionConsented = false;
            KazumiLogger()
                .i('BackgroundDownloadService: user declined permission dialog');
          }
        } else {
          // 没有设置回调，直接请求权限（兼容旧行为）
          final granted = await requestNotificationPermission();
          _notificationPermissionConsented = granted;
          if (!granted) {
            KazumiLogger()
                .w('BackgroundDownloadService: notification permission denied');
          }
        }
      } else if (consented) {
        // 本会话曾同意但系统层仍未授予（用户在系统设置关闭了通知）：
        // 不弹自定义窗，直接再请求一次系统授权。
        final granted = await requestNotificationPermission();
        _notificationPermissionConsented = granted;
      }
      // consented == false：本会话不再询问，直接尝试启动服务。
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
        _lastStartFailedAt = null;
        KazumiLogger().i('BackgroundDownloadService: service started');
      } else {
        _lastStartFailedAt = DateTime.now();
        KazumiLogger().w(
            'BackgroundDownloadService: service start returned non-success: $result');
      }
      return _isRunning;
    } catch (e) {
      _lastStartFailedAt = DateTime.now();
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
    if (isTimeout) {
      // Android 15+ dataSync 前台服务达到每日时限被系统停止：
      // 通知主 isolate 标记服务已停止并提醒用户（进程仍在运行）。
      FlutterForegroundTask.sendDataToMain({'action': 'service_timeout'});
    }
  }

  @override
  void onReceiveData(Object data) {
    debugPrint('BackgroundDownloadService: received data: $data');
  }
}
