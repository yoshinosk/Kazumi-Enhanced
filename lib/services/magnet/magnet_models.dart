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

  /// 下载目录（aria2 下载该订阅资源时的 dir，留空用默认）。
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

/// 一个 aria2 下载任务的状态。
class MagnetDownloadTask {
  final String gid;
  final String status;
  final int totalLength;
  final int completedLength;
  final int downloadSpeed;
  final String fileName;

  const MagnetDownloadTask({
    required this.gid,
    required this.status,
    required this.totalLength,
    required this.completedLength,
    required this.downloadSpeed,
    required this.fileName,
  });

  double get progress =>
      totalLength > 0 ? completedLength / totalLength : 0.0;

  bool get isCompleted => status == 'complete';
  bool get isActive => status == 'active' || status == 'waiting' || status == 'paused';
  bool get isError => status == 'error' || status == 'removed';
}

/// `aria2.getPeers` 返回的单个对等节点信息。
class MagnetPeer {
  final String peerId;
  final String ip;
  final String port;
  final String bitfield;
  final bool amChoking;
  final bool peerChoking;
  final int downloadSpeed;
  final int uploadSpeed;
  final bool seeder;

  const MagnetPeer({
    required this.peerId,
    required this.ip,
    required this.port,
    required this.bitfield,
    required this.amChoking,
    required this.peerChoking,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.seeder,
  });

  /// 该节点对我的分享是否完整（是否全种）。
  bool get hasFullData => bitfield.contains('0') == false && bitfield.isNotEmpty;

  factory MagnetPeer.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) {
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return MagnetPeer(
      peerId: json['peerId'] as String? ?? '',
      ip: json['ip'] as String? ?? '',
      port: json['port'] as String? ?? '',
      bitfield: json['bitfield'] as String? ?? '',
      amChoking: (json['amChoking'] as String?) == 'true',
      peerChoking: (json['peerChoking'] as String?) == 'true',
      downloadSpeed: parseInt(json['downloadSpeed']),
      uploadSpeed: parseInt(json['uploadSpeed']),
      seeder: (json['seeder'] as String?) == 'true',
    );
  }
}

/// `aria2.getGlobalStat` 返回的全局统计。
class MagnetGlobalStat {
  final int downloadSpeed;
  final int uploadSpeed;
  final int numActive;
  final int numWaiting;
  final int numStopped;

  const MagnetGlobalStat({
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.numActive,
    required this.numWaiting,
    required this.numStopped,
  });

  factory MagnetGlobalStat.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) {
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return MagnetGlobalStat(
      downloadSpeed: parseInt(json['downloadSpeed']),
      uploadSpeed: parseInt(json['uploadSpeed']),
      numActive: parseInt(json['numActive']),
      numWaiting: parseInt(json['numWaiting']),
      numStopped: parseInt(json['numStopped']),
    );
  }
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
