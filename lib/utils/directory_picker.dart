import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/platform/android_storage_access.dart';
import 'package:path/path.dart' as p;

/// 选择下载目录的公共工具。
///
/// 只考虑 Android 与 Windows：
/// - Windows 等桌面端：直接选目录，再写探测文件确认可写；
/// - Android 11+：写入共享存储需要「所有文件访问」权限，探测失败时引导跳转
///   系统设置，用户返回应用后重新探测，避免 libtorrent 落盘时 EACCES 卡死任务。

/// 弹出系统目录选择器，并校验所选目录可写。
///
/// [initialDirectory] 为选择器初始位置，为空则由系统决定。
/// [verifyWritable] 关闭后只返回选择结果、不做写探测（调用方自行兜底）。
/// 返回用户选择的目录；取消选择或目录不可写时返回 null。
Future<String?> pickWritableDirectory({
  required String dialogTitle,
  String? initialDirectory,
  bool verifyWritable = true,
}) async {
  final dir = await FilePicker.platform.getDirectoryPath(
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
  );
  if (dir == null) return null;
  if (!verifyWritable) return dir;
  if (Platform.isAndroid) {
    final ok = await ensureAndroidWritableDirectory(dir);
    return ok ? dir : null;
  }
  if (await probeWritableDirectory(dir)) return dir;
  KazumiDialog.showToast(message: '所选目录不可写，请更换目录');
  return null;
}

/// Android 写入探测：向所选目录写临时文件验证可写。
///
/// 不可写且尚未授予「所有文件访问」时，引导跳转系统设置开启，
/// 用户返回应用后重新探测；仍不可写（或已授权却失败）则提示换目录。
/// 返回该目录是否可作为下载目录。
Future<bool> ensureAndroidWritableDirectory(String dir) async {
  if (await probeWritableDirectory(dir)) return true;
  if (await AndroidStorageAccess.hasAllFilesAccess()) {
    // 已有全文件权限仍不可写（目录只读等），直接提示。
    KazumiDialog.showToast(message: '所选目录不可写，请更换目录');
    return false;
  }
  final goSettings = await KazumiDialog.show<bool>(
    builder: (dialogContext) => AlertDialog(
      title: const Text('目录不可写'),
      content: const Text(
        'Android 11 及以上写入共享存储目录需要「所有文件访问」权限。\n'
        '是否前往系统设置开启？开启后返回应用会自动重新检测。',
      ),
      actions: [
        TextButton(
          onPressed: () => KazumiDialog.dismiss(popWith: false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => KazumiDialog.dismiss(popWith: true),
          child: const Text('去开启'),
        ),
      ],
    ),
  );
  if (goSettings != true) return false;
  await AndroidStorageAccess.requestAllFilesAccess();
  // 跳转系统设置后应用退到后台，等待用户返回（最长 5 分钟）。
  await AppLifecycleResumeWaiter.waitForResume(const Duration(minutes: 5));
  if (await probeWritableDirectory(dir)) return true;
  KazumiDialog.showToast(message: '目录仍不可写，请更换目录或检查权限');
  return false;
}

/// 向目录写入临时探测文件并清理，返回是否可写。
Future<bool> probeWritableDirectory(String dir) async {
  final probe = File(p.join(dir, '.kazumi_write_probe'));
  try {
    await probe.writeAsString('');
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
}

/// 等待应用从后台回到前台（用于「跳转系统设置后返回」这类场景）。
///
/// 超时后直接结束等待，由调用方重新探测。
class AppLifecycleResumeWaiter with WidgetsBindingObserver {
  AppLifecycleResumeWaiter._();

  final Completer<void> _completer = Completer<void>();
  bool _finished = false;

  /// 注册生命周期监听，直到应用回到前台或 [timeout] 超时。
  static Future<void> waitForResume(Duration timeout) {
    final waiter = AppLifecycleResumeWaiter._();
    WidgetsBinding.instance.addObserver(waiter);
    return waiter._completer.future
        .timeout(timeout, onTimeout: () => waiter._finish());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _finish();
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    WidgetsBinding.instance.removeObserver(this);
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}
