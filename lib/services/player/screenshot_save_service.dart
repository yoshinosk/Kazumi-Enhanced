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
  /// [title]（番剧标题）、[episode]（集数）与 [position]（播放进度）
  /// 共同生成可辨识的文件名（自动过滤 Windows 非法字符并截断）。
  /// 目录不存在时自动创建；文件名冲突时自动追加序号，避免连续截图
  /// 静默覆盖；写入失败时抛出 [FileSystemException]，由调用方提示
  /// 用户修改保存位置。
  Future<File> savePng(
    Uint8List bytes, {
    String? title,
    int? episode,
    Duration? position,
  }) async {
    final directory = resolveDirectory();
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final fileName = await _resolveUniqueFileName(
        directory,
        buildFileBaseName(title: title, episode: episode, position: position),
      );
      final file = File(p.join(directory.path, fileName));
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

  /// 生成形如 `标题_第01话_12-34` 的基础文件名（不含扩展名）。
  ///
  /// 缺失的部分自动跳过；全部缺失时回落到 `Kazumi_时间戳`，保证
  /// 文件名始终非空。播放进度超过 1 小时才带小时段（`01-02-03`）。
  String buildFileBaseName({String? title, int? episode, Duration? position}) {
    final sanitized = _sanitizeTitle(title);
    final parts = <String>[
      if (sanitized.isNotEmpty) sanitized,
      if (episode != null && episode > 0)
        '第${episode.toString().padLeft(2, '0')}话',
      if (position != null) _formatPosition(position),
    ];
    if (parts.isEmpty) {
      final now = DateTime.now();
      return 'Kazumi_'
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}_'
          '${now.millisecond.toString().padLeft(3, '0')}';
    }
    return parts.join('_');
  }

  /// 进度格式化为文件名安全的 `分-秒` / `时-分-秒`（冒号在 Windows
  /// 文件名中非法，故用连字符）。
  String _formatPosition(Duration position) {
    String pad(int n) => n.toString().padLeft(2, '0');
    final hours = position.inHours;
    final minutes = position.inMinutes % 60;
    final seconds = position.inSeconds % 60;
    if (hours > 0) {
      return '${pad(hours)}-${pad(minutes)}-${pad(seconds)}';
    }
    return '${pad(minutes)}-${pad(seconds)}';
  }

  /// 文件名已存在时追加 `_2`、`_3`… 序号，保证不覆盖旧截图。
  Future<String> _resolveUniqueFileName(
    Directory directory,
    String baseName,
  ) async {
    var name = '$baseName.png';
    var counter = 2;
    while (await File(p.join(directory.path, name)).exists()) {
      name = '$baseName$counter.png';
      counter++;
    }
    return name;
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
