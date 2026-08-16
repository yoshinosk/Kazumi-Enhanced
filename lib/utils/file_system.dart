import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Custom download directories are supported on desktop platforms where the
/// user can grant persistent access to an arbitrary directory. On macOS this
/// additionally requires a security-scoped bookmark (SecureBookmarkService).
bool get supportsCustomDownloadDirectory =>
    Platform.isWindows || Platform.isMacOS;

Future<String> getDefaultDownloadDirectory() async {
  final appSupport = await getApplicationSupportDirectory();
  return path.join(appSupport.path, 'downloads');
}

Future<void> ensureDirectoryWritable(String directoryPath) async {
  final directory = Directory(directoryPath);
  await directory.create(recursive: true);

  final probe = File(path.join(
    directoryPath,
    '.kazumi_write_test_${DateTime.now().microsecondsSinceEpoch}.tmp',
  ));

  try {
    await probe.writeAsString('ok', flush: true);
  } finally {
    try {
      if (await probe.exists()) {
        await probe.delete();
      }
    } on FileSystemException {
      // The write check already succeeded; a leftover probe is not fatal.
    }
  }
}

/// 在系统文件管理器中显示文件（选中该文件）或目录。
///
/// Windows 用 explorer /select，macOS 用 open -R，Linux 用 xdg-open。
/// 文件不存在或平台不支持时返回 false。
Future<bool> revealInFileManager(String filePath) async {
  try {
    final type = await FileSystemEntity.type(filePath);
    if (type == FileSystemEntityType.notFound) {
      return false;
    }
    if (Platform.isWindows) {
      if (type == FileSystemEntityType.file) {
        // /select, 与路径必须作为两个独立参数传递：合并成一个参数时，
        // 含空格的路径会被 Dart 整体加引号，explorer 解析失败后
        // 回退打开默认目录（「我的文档」）。
        await Process.start(
          'explorer.exe',
          ['/select,', filePath.replaceAll('/', r'\')],
          runInShell: false,
        );
      } else {
        await Process.start(
          'explorer.exe',
          [filePath.replaceAll('/', r'\')],
          runInShell: false,
        );
      }
    } else if (Platform.isMacOS) {
      if (type == FileSystemEntityType.file) {
        await Process.start('open', ['-R', filePath]);
      } else {
        await Process.start('open', [filePath]);
      }
    } else if (Platform.isLinux) {
      final target =
          type == FileSystemEntityType.file ? path.dirname(filePath) : filePath;
      await Process.start('xdg-open', [target]);
    } else {
      return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}
