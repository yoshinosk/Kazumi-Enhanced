import 'dart:convert';

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/lan/lan_media_paths.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 协议版本。桌面端与手机端版本不一致时拒绝同步，避免半兼容状态。
const int kLanSyncProtocolVersion = 1;

/// 固定端口：HTTP 流媒体 / 同步 API。
const int kLanSyncHttpPort = 45870;

/// 固定端口：UDP 广播发现。
const int kLanSyncDiscoveryPort = 45871;

/// 局域网发现广播内容。
const String kLanSyncDiscoveryProbe = 'KAZUMI_LAN_DISCOVER_V1';

/// 服务端信息（发现响应与 API 共用）。
class LanServerInfo {
  const LanServerInfo({
    required this.protocol,
    required this.serverId,
    required this.name,
    required this.version,
    required this.httpPort,
    this.requiresPairing = true,
  });

  final int protocol;
  final String serverId;
  final String name;
  final String version;
  final int httpPort;
  final bool requiresPairing;

  factory LanServerInfo.fromJson(Map<String, dynamic> json) => LanServerInfo(
    protocol: (json['protocol'] as num?)?.toInt() ?? 0,
    serverId: json['serverId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    version: json['version'] as String? ?? '',
    httpPort: (json['httpPort'] as num?)?.toInt() ?? kLanSyncHttpPort,
    requiresPairing: json['requiresPairing'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'protocol': protocol,
    'serverId': serverId,
    'name': name,
    'version': version,
    'httpPort': httpPort,
    'requiresPairing': requiresPairing,
  };
}

/// 一次发现到的主机信息。
class LanDiscoveredServer {
  const LanDiscoveredServer({required this.host, required this.info});

  final String host;
  final LanServerInfo info;

  String get serverId => info.serverId;
  String get name => info.name;
  int get port => info.httpPort;

  Uri get baseUri => Uri(scheme: 'http', host: host, port: port);

  String get displayAddress => '$host:$port';
}

/// 桌面端媒体文件（真实路径 + 轻量元数据）。
class LanMediaFileData {
  const LanMediaFileData({
    required this.path,
    required this.name,
    required this.size,
    required this.modifiedAtMs,
  });

  final String path;
  final String name;
  final int size;
  final int modifiedAtMs;

  factory LanMediaFileData.fromLocalMediaFile(LocalMediaFile file) =>
      LanMediaFileData(
        path: file.path,
        name: file.name,
        size: file.size,
        modifiedAtMs: file.modifiedAt.millisecondsSinceEpoch,
      );

  factory LanMediaFileData.fromJson(Map<String, dynamic> json) =>
      LanMediaFileData(
        path: json['path'] as String? ?? '',
        name: json['name'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        modifiedAtMs: (json['modifiedAtMs'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'size': size,
    'modifiedAtMs': modifiedAtMs,
  };
}

/// 桌面端媒体库目录。
class LanMediaFolderData {
  const LanMediaFolderData({
    required this.path,
    required this.name,
    required this.files,
  });

  final String path;
  final String name;
  final List<LanMediaFileData> files;

  factory LanMediaFolderData.fromLocalMediaFolder(LocalMediaFolder folder) =>
      LanMediaFolderData(
        path: folder.path,
        name: folder.name,
        files: [
          for (final file in folder.files)
            if (!file.isRemote) LanMediaFileData.fromLocalMediaFile(file),
        ],
      );

  factory LanMediaFolderData.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    return LanMediaFolderData(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      files: [
        if (rawFiles is List)
          for (final raw in rawFiles)
            if (raw is Map)
              LanMediaFileData.fromJson(Map<String, dynamic>.from(raw)),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'files': files.map((file) => file.toJson()).toList(),
  };

  /// 转换为手机端媒体库条目；[streamUrlBuilder] 生成带 token 的流地址。
  LocalMediaFolder toLocalFolder(
    String serverId,
    String Function(String remotePath) streamUrlBuilder,
  ) {
    final folderPath = lanFolderPath(serverId, path);
    return LocalMediaFolder(
      path: folderPath,
      name: name,
      files: [
        for (final file in files)
          LocalMediaFile(
            path: lanFilePath(serverId, file.path),
            name: file.name,
            size: file.size,
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(file.modifiedAtMs),
            isRemote: true,
            remotePath: file.path,
            playbackUrl: streamUrlBuilder(file.path),
            remoteFolderPath: path,
            remoteFolderName: name,
          ),
      ],
    );
  }
}

/// 一次同步的完整数据：服务端信息 + 媒体库 + 本地播放历史。
class LanSyncPayload {
  const LanSyncPayload({
    required this.server,
    required this.folders,
    required this.scrapeResults,
    required this.fileScrapeResults,
    required this.history,
    required this.collectibles,
    required this.collectTombstones,
    required this.generatedAtMs,
  });

  final LanServerInfo server;
  final List<LanMediaFolderData> folders;
  final Map<String, MediaScrapeInfo> scrapeResults;
  final Map<String, MediaScrapeInfo> fileScrapeResults;
  final List<LanHistoryEntry> history;
  final List<LanCollectibleEntry> collectibles;
  final List<LanCollectTombstone> collectTombstones;
  final int generatedAtMs;

  factory LanSyncPayload.fromJson(Map<String, dynamic> json) {
    final rawServer = json['server'];
    final rawFolders = json['folders'];
    final rawScrape = json['scrapeResults'];
    final rawFileScrape = json['fileScrapeResults'];
    final rawHistory = json['history'];
    final rawCollectibles = json['collectibles'];
    final rawTombstones = json['collectTombstones'];
    return LanSyncPayload(
      server: rawServer is Map
          ? LanServerInfo.fromJson(Map<String, dynamic>.from(rawServer))
          : const LanServerInfo(
              protocol: 0,
              serverId: '',
              name: '',
              version: '',
              httpPort: kLanSyncHttpPort,
            ),
      folders: [
        if (rawFolders is List)
          for (final raw in rawFolders)
            if (raw is Map)
              LanMediaFolderData.fromJson(Map<String, dynamic>.from(raw)),
      ],
      scrapeResults: _decodeScrapeMap(rawScrape),
      fileScrapeResults: _decodeScrapeMap(rawFileScrape),
      history: [
        if (rawHistory is List)
          for (final raw in rawHistory)
            if (raw is Map)
              LanHistoryEntry.fromJson(Map<String, dynamic>.from(raw)),
      ],
      collectibles: [
        if (rawCollectibles is List)
          for (final raw in rawCollectibles)
            if (raw is Map)
              LanCollectibleEntry.fromJson(Map<String, dynamic>.from(raw)),
      ],
      collectTombstones: [
        if (rawTombstones is List)
          for (final raw in rawTombstones)
            if (raw is Map)
              LanCollectTombstone.fromJson(Map<String, dynamic>.from(raw)),
      ],
      generatedAtMs: (json['generatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  static Map<String, MediaScrapeInfo> _decodeScrapeMap(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, MediaScrapeInfo>{};
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      result[entry.key.toString()] = MediaScrapeInfo.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }
    return result;
  }

  Map<String, dynamic> toJson({bool includeHistory = true}) => {
    'server': server.toJson(),
    'folders': folders.map((folder) => folder.toJson()).toList(),
    'scrapeResults': {
      for (final entry in scrapeResults.entries)
        entry.key: entry.value.toJson(),
    },
    'fileScrapeResults': {
      for (final entry in fileScrapeResults.entries)
        entry.key: entry.value.toJson(),
    },
    if (includeHistory)
      'history': history.map((entry) => entry.toJson()).toList(),
    'collectibles': collectibles.map((entry) => entry.toJson()).toList(),
    'collectTombstones': collectTombstones
        .map((entry) => entry.toJson())
        .toList(),
    'generatedAtMs': generatedAtMs,
  };

  /// 手机端媒体库视图。
  List<LocalMediaFolder> toLocalFolders(
    String Function(String remotePath) streamUrlBuilder,
  ) {
    return [
      for (final folder in folders)
        folder.toLocalFolder(server.serverId, streamUrlBuilder),
    ];
  }

  /// 目录级搜刮结果：真实路径 → 手机端伪路径。
  Map<String, MediaScrapeInfo> toLocalFolderScrapeResults() => {
    for (final entry in scrapeResults.entries)
      lanFolderPath(server.serverId, entry.key): entry.value,
  };

  /// 文件级搜刮结果：真实路径 → 手机端伪路径。
  Map<String, MediaScrapeInfo> toLocalFileScrapeResults() => {
    for (final entry in fileScrapeResults.entries)
      lanFilePath(server.serverId, entry.key): entry.value,
  };

  LanSyncPayload copyWith({
    List<LanMediaFolderData>? folders,
    Map<String, MediaScrapeInfo>? scrapeResults,
    Map<String, MediaScrapeInfo>? fileScrapeResults,
    List<LanHistoryEntry>? history,
    List<LanCollectibleEntry>? collectibles,
    List<LanCollectTombstone>? collectTombstones,
    int? generatedAtMs,
  }) => LanSyncPayload(
    server: server,
    folders: folders ?? this.folders,
    scrapeResults: scrapeResults ?? this.scrapeResults,
    fileScrapeResults: fileScrapeResults ?? this.fileScrapeResults,
    history: history ?? this.history,
    collectibles: collectibles ?? this.collectibles,
    collectTombstones: collectTombstones ?? this.collectTombstones,
    generatedAtMs: generatedAtMs ?? this.generatedAtMs,
  );
}

/// 单集观看进度。
class LanProgressData {
  const LanProgressData({
    required this.episode,
    required this.road,
    required this.progressMs,
    required this.updatedAtMs,
  });

  final int episode;
  final int road;
  final int progressMs;
  final int updatedAtMs;

  /// 分集进度快照。
  ///
  /// [Progress.updatedAtMs] 为 0 表示该进度写入时还没有分集时间戳（旧版本
  /// 数据）。此处如实保留 0（未知），不能拿条目级的 [History.lastWatchTime]
  /// 兜底：那会让几个月前的旧进度看起来像是「最后观看那集的时间」更新的，
  /// 从而在合并时压掉对方设备刚看的新进度。
  factory LanProgressData.fromProgress(Progress progress) => LanProgressData(
    episode: progress.episode,
    road: progress.road,
    progressMs: progress.progress.inMilliseconds,
    updatedAtMs: progress.updatedAtMs > 0 ? progress.updatedAtMs : 0,
  );

  factory LanProgressData.fromJson(Map<String, dynamic> json) =>
      LanProgressData(
        episode: (json['episode'] as num?)?.toInt() ?? 0,
        road: (json['road'] as num?)?.toInt() ?? 0,
        progressMs: (json['progressMs'] as num?)?.toInt() ?? 0,
        updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'episode': episode,
    'road': road,
    'progressMs': progressMs,
    'updatedAtMs': updatedAtMs,
  };
}

/// 一条收藏状态（看过 / 抛弃等）。
class LanCollectibleEntry {
  const LanCollectibleEntry({
    required this.bangumiItem,
    required this.type,
    required this.timeMs,
  });

  final BangumiItem bangumiItem;

  /// 1 在看 / 2 想看 / 3 搁置 / 4 看过 / 5 抛弃。
  final int type;

  /// 最后一次设置该状态的时间（毫秒时间戳）。
  final int timeMs;

  int get bangumiId => bangumiItem.id;

  factory LanCollectibleEntry.fromCollected(CollectedBangumi collectible) =>
      LanCollectibleEntry(
        bangumiItem: collectible.bangumiItem,
        type: collectible.type,
        timeMs: collectible.time.millisecondsSinceEpoch,
      );

  factory LanCollectibleEntry.fromJson(Map<String, dynamic> json) {
    final rawBangumi = json['bangumiItem'];
    return LanCollectibleEntry(
      bangumiItem: _bangumiItemFromJson(
        rawBangumi is Map ? Map<String, dynamic>.from(rawBangumi) : const {},
      ),
      type: (json['type'] as num?)?.toInt() ?? 0,
      timeMs: (json['timeMs'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'bangumiItem': _bangumiItemToJson(bangumiItem),
    'type': type,
    'timeMs': timeMs,
  };

  CollectedBangumi toCollected() => CollectedBangumi(
    bangumiItem,
    DateTime.fromMillisecondsSinceEpoch(timeMs),
    type,
  );
}

/// 收藏删除墓碑：用来把「删除收藏」同步到另一端，避免被旧数据复活。
class LanCollectTombstone {
  const LanCollectTombstone({
    required this.bangumiId,
    required this.updatedAtMs,
  });

  final int bangumiId;
  final int updatedAtMs;

  factory LanCollectTombstone.fromJson(Map<String, dynamic> json) =>
      LanCollectTombstone(
        bangumiId: (json['bangumiId'] as num?)?.toInt() ?? 0,
        updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'bangumiId': bangumiId,
    'updatedAtMs': updatedAtMs,
  };
}

class LanCollectMergeResult {
  const LanCollectMergeResult({
    required this.collectibles,
    required this.tombstones,
  });

  final List<LanCollectibleEntry> collectibles;
  final List<LanCollectTombstone> tombstones;

  static const empty = LanCollectMergeResult(collectibles: [], tombstones: []);
}

/// 收藏状态合并：最后修改时间优先。
///
/// - 同一番剧只保留一个状态；
/// - 时间较新的状态获胜；
/// - 时间相同时按「在看 > 看过 > 想看 > 搁置 > 抛弃」固定顺序决胜，
///   避免两端各自保留不同状态；
/// - 删除墓碑严格晚于现役状态时才生效；同一秒内重新收藏视为收藏方获胜。
LanCollectMergeResult mergeLanCollectibles({
  required Iterable<LanCollectibleEntry> localCollectibles,
  required Iterable<LanCollectTombstone> localTombstones,
  required Iterable<LanCollectibleEntry> remoteCollectibles,
  required Iterable<LanCollectTombstone> remoteTombstones,
}) {
  final live = <int, LanCollectibleEntry>{};
  final tombstones = <int, LanCollectTombstone>{};
  for (final entry in [...localCollectibles, ...remoteCollectibles]) {
    if (entry.bangumiId <= 0) continue;
    final existing = live[entry.bangumiId];
    if (existing == null ||
        entry.timeMs > existing.timeMs ||
        (entry.timeMs == existing.timeMs &&
            collectTypePriority(entry.type) >
                collectTypePriority(existing.type))) {
      live[entry.bangumiId] = entry;
    }
  }
  for (final entry in [...localTombstones, ...remoteTombstones]) {
    if (entry.bangumiId <= 0) continue;
    final existing = tombstones[entry.bangumiId];
    if (existing == null || entry.updatedAtMs > existing.updatedAtMs) {
      tombstones[entry.bangumiId] = entry;
    }
  }

  final resultLive = <LanCollectibleEntry>[];
  final resultTombstones = <LanCollectTombstone>[];
  final ids = {...live.keys, ...tombstones.keys}.toList()..sort();
  for (final id in ids) {
    final current = live[id];
    final tombstone = tombstones[id];
    if (current == null) {
      if (tombstone != null) resultTombstones.add(tombstone);
      continue;
    }
    if (tombstone != null && tombstone.updatedAtMs > current.timeMs) {
      resultTombstones.add(tombstone);
    } else {
      // 同时间或收藏状态更新时，以收藏为准（重新收藏后删除墓碑失效）。
      resultLive.add(current);
    }
  }
  return LanCollectMergeResult(
    collectibles: resultLive,
    tombstones: resultTombstones,
  );
}

int collectTypePriority(int type) => switch (type) {
  1 => 5, // 在看
  4 => 4, // 看过
  2 => 3, // 想看
  3 => 2, // 搁置
  5 => 1, // 抛弃
  _ => 0,
};

/// 可跨设备传输的本地媒体库历史条目。
class LanHistoryEntry {
  const LanHistoryEntry({
    required this.bangumiItem,
    required this.lastWatchEpisode,
    required this.lastWatchTime,
    required this.lastSrc,
    required this.lastWatchEpisodeName,
    required this.adapterName,
    required this.entryKind,
    required this.episodePageUrl,
    required this.progresses,
  });

  final BangumiItem bangumiItem;
  final int lastWatchEpisode;
  final DateTime lastWatchTime;
  final String lastSrc;
  final String lastWatchEpisodeName;
  final String adapterName;
  final String entryKind;
  final String episodePageUrl;
  final List<LanProgressData> progresses;

  String get key =>
      History.getKey(adapterName, bangumiItem, entryKind: entryKind);

  factory LanHistoryEntry.fromHistory(History history) => LanHistoryEntry(
    bangumiItem: history.bangumiItem,
    lastWatchEpisode: history.lastWatchEpisode,
    lastWatchTime: history.lastWatchTime,
    lastSrc: history.lastSrc,
    lastWatchEpisodeName: history.lastWatchEpisodeName,
    adapterName: history.adapterName,
    entryKind: HistoryEntryKind.normalize(history.entryKind),
    episodePageUrl: history.episodePageUrl,
    progresses: [
      for (final progress in history.progresses.values)
        LanProgressData.fromProgress(progress),
    ],
  );

  factory LanHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawBangumi = json['bangumiItem'];
    final rawProgresses = json['progresses'];
    return LanHistoryEntry(
      bangumiItem: _bangumiItemFromJson(
        rawBangumi is Map ? Map<String, dynamic>.from(rawBangumi) : const {},
      ),
      lastWatchEpisode: (json['lastWatchEpisode'] as num?)?.toInt() ?? 0,
      lastWatchTime:
          DateTime.tryParse(json['lastWatchTime'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastSrc: json['lastSrc'] as String? ?? '',
      lastWatchEpisodeName: json['lastWatchEpisodeName'] as String? ?? '',
      adapterName: json['adapterName'] as String? ?? kLocalMediaAdapterName,
      entryKind: HistoryEntryKind.normalize(json['entryKind'] as String? ?? ''),
      episodePageUrl: json['episodePageUrl'] as String? ?? '',
      progresses: [
        if (rawProgresses is List)
          for (final raw in rawProgresses)
            if (raw is Map)
              LanProgressData.fromJson(Map<String, dynamic>.from(raw)),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'bangumiItem': _bangumiItemToJson(bangumiItem),
    'lastWatchEpisode': lastWatchEpisode,
    'lastWatchTime': lastWatchTime.toIso8601String(),
    'lastSrc': lastSrc,
    'lastWatchEpisodeName': lastWatchEpisodeName,
    'adapterName': adapterName,
    'entryKind': entryKind,
    'episodePageUrl': episodePageUrl,
    'progresses': progresses.map((p) => p.toJson()).toList(),
  };

  LanHistoryEntry copyWith({
    String? episodePageUrl,
    List<LanProgressData>? progresses,
    int? lastWatchEpisode,
    DateTime? lastWatchTime,
    String? lastWatchEpisodeName,
    String? lastSrc,
  }) => LanHistoryEntry(
    bangumiItem: bangumiItem,
    lastWatchEpisode: lastWatchEpisode ?? this.lastWatchEpisode,
    lastWatchTime: lastWatchTime ?? this.lastWatchTime,
    lastSrc: lastSrc ?? this.lastSrc,
    lastWatchEpisodeName: lastWatchEpisodeName ?? this.lastWatchEpisodeName,
    adapterName: adapterName,
    entryKind: entryKind,
    episodePageUrl: episodePageUrl ?? this.episodePageUrl,
    progresses: progresses ?? this.progresses,
  );

  /// 合并两条同 key 条目：观看状态取较新一条，分集进度按更新时间逐集合并。
  ///
  /// 路径（[episodePageUrl]）不参与「谁更新」的判断：它标识文件归属，
  /// 与观看时间无关。因此取非空的一方，避免空路径条目把有效路径抹掉。
  LanHistoryEntry merge(LanHistoryEntry other) {
    final base =
        lastWatchTime.isAfter(other.lastWatchTime) ||
            lastWatchTime.isAtSameMomentAs(other.lastWatchTime)
        ? this
        : other;
    final byEpisode = <int, LanProgressData>{};
    for (final progress in [...progresses, ...other.progresses]) {
      final existing = byEpisode[progress.episode];
      if (existing == null ||
          progress.updatedAtMs > existing.updatedAtMs ||
          (progress.updatedAtMs == existing.updatedAtMs &&
              progress.progressMs > existing.progressMs)) {
        byEpisode[progress.episode] = progress;
      }
    }
    final merged = byEpisode.values.toList()
      ..sort((a, b) => a.episode.compareTo(b.episode));
    final path = base.episodePageUrl.isNotEmpty
        ? base.episodePageUrl
        : other.episodePageUrl;
    return base.copyWith(
      episodePageUrl: path,
      progresses: merged,
      // 分集进度与「最后观看集」不一致时（例如条目在旧版本写入时分集
      // 进度丢失），按最新进度回填，历史页才能显示「看到 xx:xx」。
      lastWatchEpisode: _consistentLastEpisode(base, merged),
    );
  }

  static int _consistentLastEpisode(
    LanHistoryEntry base,
    List<LanProgressData> merged,
  ) {
    if (merged.isEmpty) return base.lastWatchEpisode;
    for (final progress in merged) {
      if (progress.episode == base.lastWatchEpisode) {
        return base.lastWatchEpisode;
      }
    }
    LanProgressData? newest;
    for (final progress in merged) {
      if (progress.updatedAtMs <= 0) continue;
      if (newest == null ||
          progress.updatedAtMs > newest.updatedAtMs ||
          (progress.updatedAtMs == newest.updatedAtMs &&
              progress.episode > newest.episode)) {
        newest = progress;
      }
    }
    return newest?.episode ?? base.lastWatchEpisode;
  }

  History toHistory() {
    final history = History(
      bangumiItem,
      lastWatchEpisode,
      adapterName,
      lastWatchTime,
      lastSrc,
      lastWatchEpisodeName,
      entryKind: entryKind,
      episodePageUrl: episodePageUrl,
    );
    for (final progress in progresses) {
      history.progresses[progress.episode] = Progress(
        progress.episode,
        progress.road,
        progress.progressMs,
        updatedAtMs: progress.updatedAtMs,
      );
    }
    return history;
  }
}

/// 合并两组历史条目（按 key 去重，逐集取较新进度）。
List<LanHistoryEntry> mergeLanHistory(
  Iterable<LanHistoryEntry> first,
  Iterable<LanHistoryEntry> second,
) {
  final byKey = <String, LanHistoryEntry>{};
  for (final entry in [...first, ...second]) {
    if (entry.adapterName != kLocalMediaAdapterName) continue;
    final existing = byKey[entry.key];
    byKey[entry.key] = existing == null ? entry : existing.merge(entry);
  }
  final result = byKey.values.toList()
    ..sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
  return result;
}

Map<String, dynamic> _bangumiItemToJson(BangumiItem item) => {
  'id': item.id,
  'type': item.type,
  'name': item.name,
  'nameCn': item.nameCn,
  'summary': item.summary,
  'airDate': item.airDate,
  'airWeekday': item.airWeekday,
  'rank': item.rank,
  'images': item.images,
  'tags': item.tags.map((tag) => tag.toJson()).toList(),
  'alias': item.alias,
  'ratingScore': item.ratingScore,
  'votes': item.votes,
  'votesCount': item.votesCount,
  'info': item.info,
  'metaTags': item.metaTags,
};

BangumiItem _bangumiItemFromJson(Map<String, dynamic> json) {
  final rawImages = json['images'];
  final rawTags = json['tags'];
  final rawAlias = json['alias'];
  final rawVotesCount = json['votesCount'];
  final rawMetaTags = json['metaTags'];
  return BangumiItem(
    id: (json['id'] as num?)?.toInt() ?? 0,
    type: (json['type'] as num?)?.toInt() ?? 2,
    name: json['name'] as String? ?? '',
    nameCn: json['nameCn'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    airDate: json['airDate'] as String? ?? '',
    airWeekday: (json['airWeekday'] as num?)?.toInt() ?? 0,
    rank: (json['rank'] as num?)?.toInt() ?? 0,
    images: {
      if (rawImages is Map)
        for (final entry in rawImages.entries)
          entry.key.toString(): entry.value?.toString() ?? '',
    },
    tags: [
      if (rawTags is List)
        for (final raw in rawTags)
          if (raw is Map) BangumiTag.fromJson(Map<String, dynamic>.from(raw)),
    ],
    alias: [if (rawAlias is List) ...rawAlias.whereType<String>()],
    ratingScore: (json['ratingScore'] as num?)?.toDouble() ?? 0,
    votes: (json['votes'] as num?)?.toInt() ?? 0,
    votesCount: [
      if (rawVotesCount is List)
        for (final raw in rawVotesCount)
          if (raw is num) raw.toInt(),
    ],
    info: json['info'] as String? ?? '',
    metaTags: [if (rawMetaTags is List) ...rawMetaTags.whereType<String>()],
  );
}

/// 手机端缓存最近一次成功的媒体库快照（不含历史，避免重复膨胀）。
class LanLibraryCache {
  LanLibraryCache._();

  static LanSyncPayload? load() {
    final raw = GStorage.getSetting(SettingsKeys.lanSyncRemoteLibrary);
    if (raw.isEmpty) return null;
    try {
      final payload = LanSyncPayload.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      if (payload.server.protocol != kLanSyncProtocolVersion) return null;
      if (payload.server.serverId.isEmpty) return null;
      return payload;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(LanSyncPayload payload) => GStorage.putSetting(
    SettingsKeys.lanSyncRemoteLibrary,
    jsonEncode(
      payload
          .copyWith(
            history: const [],
            collectibles: const [],
            collectTombstones: const [],
          )
          .toJson(includeHistory: false),
    ),
  );

  static Future<void> clear() =>
      GStorage.putSetting(SettingsKeys.lanSyncRemoteLibrary, '');
}

/// 当前应用版本（服务端信息展示用）。
String lanSyncAppVersion() => ApiEndpoints.version;
