import 'dart:io';

import 'package:flutter/services.dart';
import 'package:kazumi/services/logging/logger.dart';

/// Android 存储读取权限访问：媒体库扫描与本地视频应用内播放需要读取
/// 共享存储中的视频文件。
///
/// - API 33+ 使用 READ_MEDIA_VIDEO；
/// - API 30~32 使用 READ_EXTERNAL_STORAGE；
/// - 目录遍历与播放都基于文件原始路径（与扫描器 / media_kit 一致），
///   具备读取权限时媒体文件对 File API 可见。
class AndroidStorageAccess {
  AndroidStorageAccess._();

  static const _storageChannel = MethodChannel('com.predidit.kazumi/storage');

  /// 是否已授予读取媒体视频文件的运行时权限。
  static Future<bool> hasMediaReadPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _storageChannel
              .invokeMethod<bool>('hasMediaReadPermission') ??
          false;
    } on MissingPluginException {
      return true;
    } catch (e) {
      KazumiLogger().w(
          'AndroidStorageAccess: check media read permission failed',
          error: e);
      return false;
    }
  }

  /// 请求读取媒体视频文件的运行时权限，返回是否已授权。
  static Future<bool> requestMediaReadPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _storageChannel
              .invokeMethod<bool>('requestMediaReadPermission') ??
          false;
    } on MissingPluginException {
      return true;
    } catch (e) {
      KazumiLogger().w(
          'AndroidStorageAccess: request media read permission failed',
          error: e);
      return false;
    }
  }

  /// 是否持有「所有文件访问」权限（MANAGE_EXTERNAL_STORAGE，API 30+）。
  /// 仅读取权限下共享存储目录只暴露媒体文件；需要遍历任意文件时可引导开启。
  static Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _storageChannel.invokeMethod<bool>('hasAllFilesAccess') ??
          false;
    } on MissingPluginException {
      return true;
    } catch (e) {
      KazumiLogger().w('AndroidStorageAccess: check all files access failed',
          error: e);
      return false;
    }
  }

  /// 跳转系统设置申请「所有文件访问」权限。
  static Future<void> requestAllFilesAccess() async {
    if (!Platform.isAndroid) return;
    try {
      await _storageChannel.invokeMethod('requestAllFilesAccess');
    } catch (e) {
      KazumiLogger().w(
          'AndroidStorageAccess: request all files access failed',
          error: e);
    }
  }
}
