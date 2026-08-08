import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:kazumi/modules/search/image_search_module.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 本地媒体库支持的视频扩展名。
const Set<String> kLocalMediaExtensions = {
  '.mp4', '.mkv', '.avi', '.mov', '.flv', '.wmv', '.webm', '.m4v', '.ts', '.m2ts',
};

/// 判断文件是否是支持的视频类型。
bool isSupportedVideoFile(String path) {
  final ext = p.extension(path).toLowerCase();
  return kLocalMediaExtensions.contains(ext);
}

/// 一个本地视频文件。
class LocalMediaFile {
  const LocalMediaFile({
    required this.path,
    required this.name,
    required this.size,
    required this.modifiedAt,
  });

  final String path;
  final String name;
  final int size;
  final DateTime modifiedAt;

  String get sizeLabel {
    if (size <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var s = size.toDouble();
    var unit = 0;
    while (s >= 1024 && unit < units.length - 1) {
      s /= 1024;
      unit++;
    }
    return '${s.toStringAsFixed(s >= 100 ? 0 : 1)} ${units[unit]}';
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'size': size,
        'modifiedAt': modifiedAt.toIso8601String(),
      };

  factory LocalMediaFile.fromJson(Map<String, dynamic> json) {
    return LocalMediaFile(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      modifiedAt:
          DateTime.tryParse(json['modifiedAt'] as String? ?? '') ??
              DateTime.now(),
    );
  }

  static Future<LocalMediaFile> fromFileSystemEntity(File file) async {
    final stat = await file.stat();
    return LocalMediaFile(
      path: file.path,
      name: p.basename(file.path),
      size: stat.size,
      modifiedAt: stat.modified,
    );
  }
}

/// 一个媒体文件夹，包含其下的视频文件。
class LocalMediaFolder {
  const LocalMediaFolder({
    required this.path,
    required this.name,
    required this.files,
  });

  final String path;
  final String name;
  final List<LocalMediaFile> files;

  int get count => files.length;

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'files': files.map((e) => e.toJson()).toList(),
      };

  factory LocalMediaFolder.fromJson(Map<String, dynamic> json) {
    final fileList = json['files'] as List? ?? const [];
    return LocalMediaFolder(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      files: fileList
          .map((e) => LocalMediaFile.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

/// 本地媒体库文件夹路径仓库：以 JSON 字符串形式持久化在设置盒子中。
class LocalMediaFolderStore {
  LocalMediaFolderStore._();

  static List<String> load() {
    final raw = GStorage.getSetting(SettingsKeys.localMediaFolders);
    if (raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<String> folders) async {
    await GStorage.putSetting(
      SettingsKeys.localMediaFolders,
      jsonEncode(folders),
    );
  }
}

/// 番剧搜刮结果：仅保存展示所需的轻量字段。
class MediaScrapeInfo {
  const MediaScrapeInfo({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.airDate,
    required this.coverUrl,
  });

  final int id;
  final String name;
  final String nameCn;
  final String summary;
  final String airDate;
  final String coverUrl;

  /// 优先显示中文名，为空时回退原名。
  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nameCn': nameCn,
        'summary': summary,
        'airDate': airDate,
        'coverUrl': coverUrl,
      };

  factory MediaScrapeInfo.fromJson(Map<String, dynamic> json) {
    return MediaScrapeInfo(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      nameCn: json['nameCn'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      airDate: json['airDate'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
    );
  }

  /// 从 trace.moe / AniList 识别结果提取展示字段（图片识别的兜底结果）。
  factory MediaScrapeInfo.fromAniList(Anilist anilist) {
    final title = anilist.title;
    final airDate = anilist.startDate != null
        ? '${anilist.startDate!.year}-${(anilist.startDate!.month ?? 1).toString().padLeft(2, '0')}-${(anilist.startDate!.day ?? 1).toString().padLeft(2, '0')}'
        : '';
    return MediaScrapeInfo(
      id: anilist.id ?? anilist.idMal ?? 0,
      name: title?.romaji ?? title?.native ?? title?.english ?? '',
      nameCn: title?.chinese ?? title?.english ?? title?.native ?? '',
      summary: '',
      airDate: airDate,
      coverUrl: anilist.coverImage?.large ??
          anilist.coverImage?.medium ??
          anilist.coverImage?.extraLarge ??
          '',
    );
  }

  /// 从 BangumiItem 提取展示字段。
  factory MediaScrapeInfo.fromBangumiItem(dynamic item) {
    final images = item.images;
    String? cover;
    if (images is Map) {
      cover = images['large'] as String? ?? images['common'] as String?;
    }
    return MediaScrapeInfo(
      id: item.id as int,
      name: item.name as String? ?? '',
      nameCn: item.nameCn as String? ?? '',
      summary: item.summary as String? ?? '',
      airDate: item.airDate as String? ?? '',
      coverUrl: cover ?? '',
    );
  }
}

/// 搜刮结果仓库：以 JSON 字符串形式持久化「文件夹路径 → 番剧信息」映射。
class MediaScrapeStore {
  MediaScrapeStore._();

  static Map<String, MediaScrapeInfo> load() {
    final raw = GStorage.getSetting(SettingsKeys.localMediaScrapeResults);
    if (raw.isEmpty) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (key, value) => MapEntry(
          key,
          MediaScrapeInfo.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      );
    } catch (_) {
      return const {};
    }
  }

  static Future<void> save(Map<String, MediaScrapeInfo> results) async {
    final map = results.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    await GStorage.putSetting(
      SettingsKeys.localMediaScrapeResults,
      jsonEncode(map),
    );
  }
}
