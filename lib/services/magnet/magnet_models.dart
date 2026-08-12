import 'dart:convert';

import 'package:kazumi/services/storage/storage.dart';

/// 一条磁力搜索结果（来自 Mikan 等站点的 RSS 条目）。
class MagnetSearchItem {
  final String title;
  final String magnetLink;
  final String torrentUrl;
  final String size;
  final DateTime publishDate;
  final String? publisher;
  final String subtitle;

  const MagnetSearchItem({
    required this.title,
    required this.magnetLink,
    required this.torrentUrl,
    required this.size,
    required this.publishDate,
    this.publisher,
    this.subtitle = '',
  });

  factory MagnetSearchItem.fromJson(Map<String, dynamic> json) {
    return MagnetSearchItem(
      title: json['title'] as String? ?? '',
      magnetLink: json['magnetLink'] as String? ?? '',
      torrentUrl: json['torrentUrl'] as String? ?? '',
      size: json['size'] as String? ?? '',
      publishDate: DateTime.tryParse(json['publishDate'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      publisher: json['publisher'] as String?,
      subtitle: (json['subtitle'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'magnetLink': magnetLink,
        'torrentUrl': torrentUrl,
        'size': size,
        'publishDate': publishDate.toIso8601String(),
        'publisher': publisher,
        'subtitle': subtitle,
      };
}

/// 订阅源类型：Mikan 走 RSS XML，Animes Garden 走 JSON API + 客户端筛选。
enum SubscriptionKind {
  mikan,
  animesGarden,
}

/// 一个 RSS 订阅源。
///
/// [feedUrl] 对 [SubscriptionKind.mikan] 是 RSS 地址；
/// 对 [SubscriptionKind.animesGarden] 是搜索关键词（用作 API 的 search 参数），
/// 实际拉取时再叠加 [fansub]、[keywords]、[since]、[minSize] 等筛选条件。
class MagnetSubscription {
  final String id;
  final String name;
  final String feedUrl;
  final DateTime createdAt;
  final String? lastGuid;
  final DateTime? lastCheckedAt;

  /// 源类型，默认 mikan 以兼容旧数据。
  final SubscriptionKind kind;

  /// 指定字幕组名称（仅 Animes Garden 生效，传给 API 的 fansub 参数）。
  final String? fansub;

  /// 标题必须包含的关键字（仅 Animes Garden 生效，客户端过滤，逗号分隔多关键字）。
  final String? keywords;

  /// 仅返回此日期之后的资源（仅 Animes Garden 生效，客户端过滤）。
  final DateTime? since;

  /// 资源体积下限（MB，仅 Animes Garden 生效，客户端过滤）。
  final double? minSizeMb;

  /// 资源体积上限（MB，仅 Animes Garden 生效，客户端过滤）。
  final double? maxSizeMb;

  /// 下载目录（磁力引擎下载该订阅资源时的 dir，留空用默认）。
  final String? downloadPath;

  const MagnetSubscription({
    required this.id,
    required this.name,
    required this.feedUrl,
    required this.createdAt,
    this.lastGuid,
    this.lastCheckedAt,
    this.kind = SubscriptionKind.mikan,
    this.fansub,
    this.keywords,
    this.since,
    this.minSizeMb,
    this.maxSizeMb,
    this.downloadPath,
  });

  MagnetSubscription copyWith({
    String? lastGuid,
    DateTime? lastCheckedAt,
  }) {
    return MagnetSubscription(
      id: id,
      name: name,
      feedUrl: feedUrl,
      createdAt: createdAt,
      lastGuid: lastGuid ?? this.lastGuid,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      kind: kind,
      fansub: fansub,
      keywords: keywords,
      since: since,
      minSizeMb: minSizeMb,
      maxSizeMb: maxSizeMb,
      downloadPath: downloadPath,
    );
  }

  factory MagnetSubscription.fromJson(Map<String, dynamic> json) {
    final kindStr = json['kind'] as String?;
    return MagnetSubscription(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      feedUrl: json['feedUrl'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.now(),
      lastGuid: json['lastGuid'] as String?,
      lastCheckedAt: json['lastCheckedAt'] == null
          ? null
          : DateTime.tryParse(json['lastCheckedAt'] as String),
      kind: kindStr == 'animesGarden'
          ? SubscriptionKind.animesGarden
          : SubscriptionKind.mikan,
      fansub: _cleanOptional(json['fansub'] as String?),
      keywords: _cleanOptional(json['keywords'] as String?),
      since: json['since'] == null
          ? null
          : DateTime.tryParse(json['since'] as String),
      minSizeMb: (json['minSizeMb'] as num?)?.toDouble(),
      maxSizeMb: (json['maxSizeMb'] as num?)?.toDouble(),
      downloadPath: _cleanOptional(json['downloadPath'] as String?),
    );
  }

  static String? _cleanOptional(String? value) {
    final v = value?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'feedUrl': feedUrl,
        'createdAt': createdAt.toIso8601String(),
        'lastGuid': lastGuid,
        'lastCheckedAt': lastCheckedAt?.toIso8601String(),
        'kind': kind == SubscriptionKind.animesGarden
            ? 'animesGarden'
            : 'mikan',
        if (fansub != null) 'fansub': fansub,
        if (keywords != null) 'keywords': keywords,
        if (since != null) 'since': since!.toIso8601String(),
        if (minSizeMb != null) 'minSizeMb': minSizeMb,
        if (maxSizeMb != null) 'maxSizeMb': maxSizeMb,
        if (downloadPath != null) 'downloadPath': downloadPath,
      };
}

/// 订阅仓库：以 JSON 字符串形式持久化在设置盒子中，避免新增 Hive 适配器。
class MagnetSubscriptionStore {
  MagnetSubscriptionStore._();

  static List<MagnetSubscription> load() {
    final raw = GStorage.getSetting(SettingsKeys.magnetSubscriptions);
    if (raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => MagnetSubscription.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<MagnetSubscription> subscriptions) async {
    final json = subscriptions.map((e) => e.toJson()).toList();
    await GStorage.putSetting(
      SettingsKeys.magnetSubscriptions,
      jsonEncode(json),
    );
  }
}
