import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

/// 磁盘可用空间查询。
///
/// - Android：走 MainActivity 已有的 `getAvailableStorage` MethodChannel
///   （StatFs）
/// - Windows：win32 `GetDiskFreeSpaceExW`（无需新增原生代码）
/// - 其他平台返回 null（跳过检查）
class DiskSpace {
  DiskSpace._();

  static const _storageChannel = MethodChannel('com.predidit.kazumi/storage');

  /// 返回 [path] 所在分区的可用字节数；无法获取时返回 null。
  static Future<int?> availableBytes(String path) async {
    if (path.isEmpty) return null;
    if (Platform.isAndroid) {
      return _androidAvailableBytes(path);
    }
    if (Platform.isWindows) {
      return _windowsAvailableBytes(path);
    }
    return null;
  }

  static Future<int?> _androidAvailableBytes(String path) async {
    try {
      final result = await _storageChannel.invokeMethod<int>(
        'getAvailableStorage',
        {'path': path},
      );
      return (result == null || result < 0) ? null : result;
    } catch (e) {
      KazumiLogger().w('DiskSpace: android query failed', error: e);
      return null;
    }
  }

  static int? _windowsAvailableBytes(String path) {
    // 取盘符根目录（GetDiskFreeSpaceExW 接受任意路径，根目录最稳妥）。
    final root = p.rootPrefix(p.normalize(path));
    if (root.isEmpty) return null;
    final directory = root.toNativeUtf16();
    final available = calloc<Uint64>();
    final total = calloc<Uint64>();
    final totalFree = calloc<Uint64>();
    try {
      final ok = GetDiskFreeSpaceEx(directory, available, total, totalFree);
      return ok != 0 ? available.value : null;
    } catch (e) {
      KazumiLogger().w('DiskSpace: windows query failed', error: e);
      return null;
    } finally {
      free(directory);
      calloc.free(available);
      calloc.free(total);
      calloc.free(totalFree);
    }
  }
}
