import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 开机自启（Android / Windows）。
///
/// - Windows：原生层写入注册表 HKCU\...\CurrentVersion\Run（见
///   windows/runner/auto_start_utils.cpp）。
/// - Android：原生层把开关写入 SharedPreferences，开机广播由
///   BootCompletedReceiver 读取后决定是否拉起应用（此时 Flutter 引擎
///   尚未运行，不能读 Hive）。
class AutoStartService {
  static const _channel = MethodChannel('com.predidit.kazumi/auto_start');

  static bool get isSupported => Platform.isWindows || Platform.isAndroid;

  /// 读取系统侧当前是否已注册开机自启。
  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (e) {
      debugPrint('Failed to read auto start state: $e');
      return false;
    }
  }

  /// 注册 / 取消注册开机自启，返回是否成功。
  static Future<bool> setEnabled(bool enabled) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('setEnabled', {
            'enabled': enabled,
          }) ??
          false;
    } catch (e) {
      debugPrint('Failed to set auto start: $e');
      return false;
    }
  }
}
