import 'dart:convert';
import 'dart:io';

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/search/image_search_module.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path/path.dart' as p;

/// 本地媒体库支持的视频扩展名。
const Set<String> kLocalMediaExtensions = {
  '.mp4',
  '.mkv',
  '.avi',
  '.mov',
  '.flv',
  '.wmv',
  '.webm',
  '.m4v',
  '.ts',
  '.m2ts',
};

/// 判断文件是否是支持的视频类型。
bool isSupportedVideoFile(String path) {
  final ext = p.extension(path).toLowerCase();
  return kLocalMediaExtensions.contains(ext);
}

/// 媒体路径的比较键。Windows 忽略大小写，其他平台保留大小写。
String localMediaPathKey(String path) {
  final normalized = p.normalize(p.absolute(path));
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

bool localMediaPathsEqual(String first, String second) =>
    localMediaPathKey(first) == localMediaPathKey(second);

bool isLocalMediaPathWithin(String root, String candidate) {
  final rootKey = localMediaPathKey(root);
  final candidateKey = localMediaPathKey(candidate);
  return rootKey == candidateKey || p.isWithin(rootKey, candidateKey);
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
      modifiedAt: DateTime.tryParse(json['modifiedAt'] as String? ?? '') ??
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

  /// 同步版本，供后台 isolate 扫描使用。
  static LocalMediaFile fromFileSystemEntitySync(File file) {
    final stat = file.statSync();
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
          .map((e) =>
              LocalMediaFile.fromJson(Map<String, dynamic>.from(e as Map)))
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
enum MediaMetadataSource { bangumi, anilist, legacy }

class MediaScrapeInfo {
  const MediaScrapeInfo({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.airDate,
    required this.coverUrl,
    this.source = MediaMetadataSource.bangumi,
  });

  final int id;
  final String name;
  final String nameCn;
  final String summary;
  final String airDate;
  final String coverUrl;
  final MediaMetadataSource source;

  /// 只有来源明确为 Bangumi 时才允许访问 Bangumi API。
  int? get bangumiId =>
      source == MediaMetadataSource.bangumi && id > 0 ? id : null;

  String get identityKey => '${source.name}:${id > 0 ? id : '$name|$airDate'}';

  /// AniList 条目使用非正数 ID，播放器可正常展示但不会触发远端同步；
  /// legacy 保留正 ID，与旧版本历史记录的 key（正 ID）保持一致。
  int get playbackId {
    if (source == MediaMetadataSource.bangumi) return id;
    if (source == MediaMetadataSource.anilist) return id > 0 ? -id : 0;
    return id > 0 ? id : 0;
  }

  /// 优先显示中文名，为空时回退原名。
  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  /// 转换为应用内播放 / 弹幕关联所需的 BangumiItem。
  BangumiItem toBangumiItem() => BangumiItem(
        id: playbackId,
        type: 2,
        name: name,
        nameCn: nameCn,
        summary: summary,
        airDate: airDate,
        airWeekday: 0,
        rank: 0,
        images: {
          'large': coverUrl,
          'common': '',
          'medium': '',
          'small': '',
          'grid': '',
        },
        tags: const [],
        alias: const [],
        ratingScore: 0,
        votes: 0,
        votesCount: const [],
        info: '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nameCn': nameCn,
        'summary': summary,
        'airDate': airDate,
        'coverUrl': coverUrl,
        'source': source.name,
      };

  factory MediaScrapeInfo.fromJson(Map<String, dynamic> json) {
    final rawSource = json['source'] as String?;
    return MediaScrapeInfo(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      nameCn: json['nameCn'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      airDate: json['airDate'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      // 旧格式没有 source 字段：早期只有 Bangumi 搜刮与 trace.moe 图片识别兜底
      // 两条写入路径，图片识别兜底的结果 summary 恒为空。据此可安全区分：
      // summary 非空且 id > 0 判定为 Bangumi（恢复缺集检测与进度同步），
      // 其余保守保留 legacy 并禁用远端同步，避免把 AniList ID 误当 Bangumi ID。
      source: MediaMetadataSource.values.firstWhere(
        (source) => source.name == rawSource,
        orElse: () => _inferLegacySource(json),
      ),
    );
  }

  /// 推断旧数据（无 source 字段）的来源，见 [MediaScrapeInfo.fromJson]。
  static MediaMetadataSource _inferLegacySource(Map<String, dynamic> json) {
    final summary = json['summary'] as String? ?? '';
    final id = (json['id'] as num?)?.toInt() ?? 0;
    if (summary.isNotEmpty && id > 0) return MediaMetadataSource.bangumi;
    return MediaMetadataSource.legacy;
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
      source: MediaMetadataSource.anilist,
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
      source: MediaMetadataSource.bangumi,
    );
  }
}

/// 搜刮结果仓库：以 JSON 字符串形式持久化「路径 → 番剧信息」映射。
///
/// 文件夹级结果以 `localMediaScrapeResults` 保存，单文件级结果以
/// `localMediaFileScrapeResults` 保存（播放时优先使用文件级结果）。
class MediaScrapeStore {
  MediaScrapeStore._();

  static Map<String, MediaScrapeInfo> load() =>
      _decode(GStorage.getSetting(SettingsKeys.localMediaScrapeResults));

  static Future<void> save(Map<String, MediaScrapeInfo> results) =>
      GStorage.putSetting(
          SettingsKeys.localMediaScrapeResults, _encode(results));

  static Map<String, MediaScrapeInfo> loadFileResults() =>
      _decode(GStorage.getSetting(SettingsKeys.localMediaFileScrapeResults));

  static Future<void> saveFileResults(
          Map<String, MediaScrapeInfo> results) =>
      GStorage.putSetting(
          SettingsKeys.localMediaFileScrapeResults, _encode(results));

  static Map<String, MediaScrapeInfo> _decode(String raw) {
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

  static String _encode(Map<String, MediaScrapeInfo> results) =>
      jsonEncode(results.map(
        (key, value) => MapEntry(key, value.toJson()),
      ));
}
