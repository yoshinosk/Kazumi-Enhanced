import 'dart:io';
import 'dart:typed_data';

import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path/path.dart' as p;

/// 桌面端（Windows）播放器截图保存服务。
///
/// 默认保存到软件（exe）所在目录下的 [defaultFolderName] 文件夹；
/// 可在 播放设置 → 截图 中自定义保存目录（见 screenshotSavePath 设置）。
class ScreenshotSaveService {
  const ScreenshotSaveService();

  static const String defaultFolderName = 'screenshots';
  static const int _maxTitleLength = 40;

  /// 截图保存目录：自定义目录优先，留空则回落到软件目录下。
  Directory resolveDirectory() {
    final custom = GStorage.getSetting<String>(
      SettingsKeys.screenshotSavePath,
    ).trim();
    if (custom.isNotEmpty) {
      return Directory(custom);
    }
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return Directory(p.join(exeDir, defaultFolderName));
  }

  /// 保存 PNG 截图并返回文件路径。
  ///
  /// [title] 为当前播放的番剧标题，用于生成可辨识的文件名（自动过滤
  /// Windows 非法字符并截断）。目录不存在时自动创建；写入失败时抛出
  /// [FileSystemException]，由调用方提示用户修改保存位置。
  Future<File> savePng(Uint8List bytes, {String? title}) async {
    final directory = resolveDirectory();
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final file = File(p.join(directory.path, _buildFileName(title)));
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } on FileSystemException catch (e) {
      KazumiLogger().w(
        'ScreenshotSaveService: failed to save screenshot to '
        '${directory.path}',
        error: e,
      );
      throw FileSystemException(
        '无法写入截图目录 ${directory.path}',
        e.path,
        e.osError,
      );
    }
  }

  /// 生成形如 `Kazumi_20260924_161234_标题.png` 的文件名。
  String _buildFileName(String? title) {
    final now = DateTime.now();
    final stamp = StringBuffer()
      ..write(now.year.toString().padLeft(4, '0'))
      ..write(now.month.toString().padLeft(2, '0'))
      ..write(now.day.toString().padLeft(2, '0'))
      ..write('_')
      ..write(now.hour.toString().padLeft(2, '0'))
      ..write(now.minute.toString().padLeft(2, '0'))
      ..write(now.second.toString().padLeft(2, '0'));

    final name = StringBuffer('Kazumi_');
    name.write(stamp);
    final sanitized = _sanitizeTitle(title);
    if (sanitized.isNotEmpty) {
      name
        ..write('_')
        ..write(sanitized);
    }
    name.write('.png');
    return name.toString();
  }

  /// 过滤 Windows 文件名非法字符（\\ / : * ? " < > | 与控制字符），
  /// 合并空白并截断；去除首尾空白与点号（Windows 不允许结尾是点/空格）。
  String _sanitizeTitle(String? title) {
    if (title == null) return '';
    var sanitized = title
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (sanitized.length > _maxTitleLength) {
      sanitized = sanitized.substring(0, _maxTitleLength).trim();
    }
    return sanitized.replaceAll(RegExp(r'[. ]+$'), '');
  }
}
