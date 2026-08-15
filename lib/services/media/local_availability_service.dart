import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/utils/local_episode_parser.dart';

/// 一个番剧的「本地可用」汇总：媒体库文件 + 离线缓存集数。
class LocalAvailability {
  const LocalAvailability({
    this.files = const [],
    this.cachedEpisodes = const [],
    this.cachedByPlugin = const {},
  });

  /// 媒体库中匹配该番剧的全部视频文件（按文件夹展开）。
  final List<LocalMediaFile> files;

  /// 已缓存完成的剧集（下载中心记录，按插件聚合前的扁平列表）。
  final List<DownloadEpisode> cachedEpisodes;

  /// 已缓存完成的剧集，按下载插件名聚合（离线播放需要插件名恢复选集）。
  final Map<String, List<DownloadEpisode>> cachedByPlugin;

  int get localFileCount => files.length;

  int get cachedCount => cachedEpisodes.length;

  bool get isEmpty => files.isEmpty && cachedEpisodes.isEmpty;

  /// 媒体库中该番剧已有的集数集合（文件名解析，SP/剧场版等非正片计入）。
  Set<int> get localEpisodes =>
      files.map((f) => parseLocalEpisodeNumber(f.name)).where((e) => e > 0).toSet();

  /// 缓存完成的集数集合。
  Set<int> get cachedEpisodeNumbers =>
      cachedEpisodes.map((e) => e.episodeNumber).where((e) => e > 0).toSet();
}

/// 跨功能协调：按 Bangumi subject ID 汇总「本地媒体库文件」与
/// 「离线缓存剧集」，供详情页本地剧集面板、播放页角标、追番列表角标、
/// 搜索页提示等复用。
class LocalAvailabilityService {
  LocalAvailabilityService(this._mediaController, this._downloadController);

  final MediaController _mediaController;
  final DownloadController _downloadController;

  /// 汇总一个 Bangumi subject ID 的本地可用内容。
  ///
  /// [bangumiId] 需要是正数（搜刮来源为 Bangumi 的 ID）；legacy / AniList
  /// 条目没有真实的 Bangumi ID，返回空。
  LocalAvailability availabilityFor(int bangumiId) {
    if (bangumiId <= 0) return const LocalAvailability();
    final files = _mediaController.filesForBangumi(bangumiId);
    final cached = <DownloadEpisode>[];
    final byPlugin = <String, List<DownloadEpisode>>{};
    for (final record in _downloadController.records) {
      if (record.bangumiId != bangumiId) continue;
      final pluginEpisodes = <DownloadEpisode>[];
      for (final episode in record.episodes.values) {
        if (episode.status == DownloadStatus.completed) {
          cached.add(episode);
          pluginEpisodes.add(episode);
        }
      }
      if (pluginEpisodes.isNotEmpty) {
        byPlugin[record.pluginName] = pluginEpisodes;
      }
    }
    return LocalAvailability(
      files: files,
      cachedEpisodes: cached,
      cachedByPlugin: byPlugin,
    );
  }

  /// 批量汇总多个番剧的「本地文件 + 已完成缓存」数量（一次遍历全库）。
  ///
  /// 搜索结果逐项调用 [availabilityFor] 是 O(结果数 × 全库) 的重复扫描，
  /// 提示横幅只需要计数，用批量版本 O(全库) 完成。
  Map<int, int> availabilityCountsFor(Iterable<int> bangumiIds) {
    final ids = bangumiIds.where((id) => id > 0).toSet();
    if (ids.isEmpty) return const {};
    final counts = _mediaController.fileCountsByBangumi();
    final cacheCounts = <int, int>{};
    for (final record in _downloadController.records) {
      if (!ids.contains(record.bangumiId)) continue;
      var completed = 0;
      for (final episode in record.episodes.values) {
        if (episode.status == DownloadStatus.completed) completed++;
      }
      if (completed > 0) {
        cacheCounts[record.bangumiId] =
            (cacheCounts[record.bangumiId] ?? 0) + completed;
      }
    }
    return {
      for (final id in ids)
        id: (counts[id] ?? 0) + (cacheCounts[id] ?? 0),
    };
  }
}
