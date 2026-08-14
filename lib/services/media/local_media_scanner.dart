import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/media/media_scraper.dart';
import 'package:kazumi/utils/chinese_convert.dart';
import 'package:kazumi/utils/local_episode_parser.dart';
import 'package:path/path.dart' as p;

/// 本地媒体库扫描器：递归遍历文件夹，收集视频文件。
///
/// 对混合存放多部番剧的目录（如按日期命名的下载目录），会按文件名的
/// 清洗后标题特征拆成多个逻辑分组，每个分组单独构成一个
/// [LocalMediaFolder]，从而在后续搜刮时能逐个匹配番剧。
///
/// 扫描在后台 isolate 中执行（目录遍历 + 逐文件 stat 不阻塞 UI）；
/// 多个根目录的结果按文件绝对路径去重，避免嵌套根目录产生重复条目。
class LocalMediaScanner {
  LocalMediaScanner();

  /// 扫描单个文件夹。当 [groupByFolder] 为 true 时，每个子目录（含自身）
  /// 成为一个 [LocalMediaFolder] 的基础，并按标题特征分组；否则所有视频
  /// 归入一个以根目录命名的文件夹（同样会按标题特征分组）。
  Future<List<LocalMediaFolder>> scan(
    String rootPath, {
    bool groupByFolder = true,
  }) async {
    if (!await Directory(rootPath).exists()) {
      KazumiLogger().w('LocalMediaScanner: folder not found: $rootPath');
      return const [];
    }
    try {
      return await compute(_scanRoot,
          _ScanArgs(rootPath: rootPath, groupByFolder: groupByFolder));
    } catch (e) {
      KazumiLogger().w('LocalMediaScanner: scan failed: $rootPath', error: e);
      return const [];
    }
  }

  /// 扫描多个文件夹并合并结果。Windows 路径大小写不敏感，其他平台保留大小写。
  Future<List<LocalMediaFolder>> scanAll(
    List<String> paths, {
    bool groupByFolder = true,
  }) async {
    final result = <LocalMediaFolder>[];
    final seenFiles = <String>{};
    for (final path in paths) {
      final folders = await scan(path, groupByFolder: groupByFolder);
      for (final folder in folders) {
        final files = folder.files
            .where((f) => seenFiles.add(localMediaPathKey(f.path)))
            .toList();
        if (files.isEmpty) continue;
        result.add(
          LocalMediaFolder(path: folder.path, name: folder.name, files: files),
        );
      }
    }
    return result;
  }
}

class _ScanArgs {
  const _ScanArgs({required this.rootPath, required this.groupByFolder});

  final String rootPath;
  final bool groupByFolder;
}

List<LocalMediaFolder> _scanRoot(_ScanArgs args) {
  final rootPath = args.rootPath;
  final groupByFolder = args.groupByFolder;
  final result = <LocalMediaFolder>[];
  final root = Directory(rootPath);
  if (groupByFolder) {
    final byFolder = <String, List<LocalMediaFile>>{};
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!isSupportedVideoFile(entity.path)) continue;
      final file = LocalMediaFile.fromFileSystemEntitySync(entity);
      final dir = p.dirname(entity.path);
      (byFolder[dir] ??= []).add(file);
    }
    byFolder.forEach((dir, files) {
      files.sort(_compareMediaFiles);
      result.addAll(_splitIntoTitleGroups(dir, files));
    });
  } else {
    final files = <LocalMediaFile>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!isSupportedVideoFile(entity.path)) continue;
      files.add(LocalMediaFile.fromFileSystemEntitySync(entity));
    }
    files.sort(_compareMediaFiles);
    result.addAll(_splitIntoTitleGroups(rootPath, files));
  }
  result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}

int _compareMediaFiles(LocalMediaFile a, LocalMediaFile b) {
  final aEpisode = parseLocalEpisodeNumber(a.name);
  final bEpisode = parseLocalEpisodeNumber(b.name);
  if (aEpisode > 0 && bEpisode > 0 && aEpisode != bEpisode) {
    return aEpisode.compareTo(bEpisode);
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

@visibleForTesting
String localMediaPathIdentityForTest(String path) => localMediaPathKey(path);

@visibleForTesting
int compareLocalMediaFilesForTest(LocalMediaFile a, LocalMediaFile b) =>
    _compareMediaFiles(a, b);

/// 把一个目录下的视频文件按清洗后的标题特征分组。
///
/// 当全部文件可归入同一个标题（如 `[LoliHouse] Beheneko - 01.mkv` 与
/// `... - 02.mkv` 均清洗为 `Beheneko`）时返回单个文件夹
/// （`name` 用目录名，保证既有行为不变）。
///
/// 当存在多个不同标题（如按日期混存多部番剧的下载目录）时，每个标题
/// 生成一个逻辑分组文件夹，`name` 为该标题、`path` 为该标题在目录下的
/// 逻辑路径，以便搜刮结果按分组独立持久化。无有效标题的文件并入
/// 以目录名命名的「其他」分组。
List<LocalMediaFolder> _splitIntoTitleGroups(
  String dir,
  List<LocalMediaFile> files,
) {
  final fallback = p.basename(dir).isEmpty ? dir : p.basename(dir);
  if (files.isEmpty) {
    return [LocalMediaFolder(path: dir, name: fallback, files: files)];
  }

  final scraper = MediaScraper();
  final byKey = <String, _TitleGroup>{};
  for (final f in files) {
    final raw = scraper.cleanName(f.name);
    final title = raw.isNotEmpty ? raw : fallback;
    final key = _normalize(title);
    (byKey[key] ??= _TitleGroup(title)).files.add(f);
  }

  // 只有一个关键字时，保持整目录为一个文件夹（与旧行为一致）。
  if (byKey.length <= 1) {
    return [LocalMediaFolder(path: dir, name: fallback, files: files)];
  }

  final groups = byKey.values.toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return [
    for (final g in groups)
      LocalMediaFolder(
        path: p.join(dir, _safeSegment(g.title)),
        name: g.title,
        files: g.files,
      ),
  ];
}

/// 归一化标题：繁转简 + 小写 + 去除装饰符号（与 MediaScraper 匹配逻辑一致）。
///
/// 繁简归一让同一部番的繁体版（`[ANi] 杖與劍的魔劍譚`）与简体版
/// （`[某组] 杖与剑的魔剑谭`）落进同一个分组，而不是被拆成两部番。
String _normalize(String title) {
  return toSimplifiedChinese(title)
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_·・.。:：（）()\[\]【】{}「」『』"' '~～+×x*]'), '');
}

/// 将分组标题清洗为可用于路径的片段（去掉 Windows 不允许的字符）。
String _safeSegment(String title) {
  return title
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

class _TitleGroup {
  _TitleGroup(this.title) : files = <LocalMediaFile>[];

  final String title;
  final List<LocalMediaFile> files;
}
