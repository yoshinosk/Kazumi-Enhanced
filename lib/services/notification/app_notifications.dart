import 'dart:io';

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:local_notifier/local_notifier.dart';

/// 系统级通知：下载完成 / 失败等事件。
///
/// - Android：awesome_notifications（完整 Android 实现，含通知通道与
///   Android 13+ 运行时权限申请）
/// - Windows：local_notifier（WinToast，需要应用快捷方式注册 AppUserModelID）
/// - 其余平台静默忽略
class AppNotifications {
  AppNotifications._();

  static const String _channelKey = 'kazumi_download';

  static bool _windowsReady = false;

  /// 应用启动时初始化（幂等）。
  static Future<void> init() async {
    if (Platform.isAndroid) {
      await _initAndroid();
    } else if (Platform.isWindows) {
      await _initWindows();
    }
  }

  static Future<void> _initAndroid() async {
    try {
      await AwesomeNotifications().initialize(
        // 使用应用默认图标
        'resource://mipmap/ic_launcher',
        [
          NotificationChannel(
            channelGroupKey: 'kazumi_download_group',
            channelKey: _channelKey,
            channelName: '下载通知',
            channelDescription: '磁力下载任务完成或失败时提醒',
            importance: NotificationImportance.High,
            defaultColor: const Color(0xFF9D50DD),
            ledColor: const Color(0xFF9D50DD),
          ),
        ],
        channelGroups: [
          NotificationChannelGroup(
            channelGroupKey: 'kazumi_download_group',
            channelGroupName: '下载通知',
          ),
        ],
        debug: false,
      );
      // Android 13+ 通知属于运行时权限：未授权时请求一次。
      final allowed = await AwesomeNotifications().isNotificationAllowed();
      if (!allowed) {
        await AwesomeNotifications().requestPermissionToSendNotifications();
      }
    } catch (e) {
      KazumiLogger().w('AppNotifications: android init failed', error: e);
    }
  }

  static Future<void> _initWindows() async {
    try {
      await localNotifier.setup(
        appName: 'Kazumi',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _windowsReady = true;
    } catch (e) {
      KazumiLogger().w('AppNotifications: windows init failed', error: e);
    }
  }

  /// 发送一条通知。平台不支持时静默忽略。
  static Future<void> show({
    required String title,
    String? body,
  }) async {
    if (Platform.isAndroid) {
      try {
        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: DateTime.now().millisecondsSinceEpoch % 0x7FFFFFFF,
            channelKey: _channelKey,
            title: title,
            body: body ?? '',
            notificationLayout: NotificationLayout.BigText,
            category: NotificationCategory.Message,
          ),
        );
      } catch (e) {
        KazumiLogger().w('AppNotifications: android show failed', error: e);
      }
    } else if (Platform.isWindows && _windowsReady) {
      try {
        await localNotifier.notify(
          LocalNotification(
            title: title,
            body: body ?? '',
          ),
        );
      } catch (e) {
        KazumiLogger().w('AppNotifications: windows show failed', error: e);
      }
    }
  }
}
