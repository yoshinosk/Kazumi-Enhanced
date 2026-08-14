import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/media/local_media_models.dart';

/// Route arguments for '/video/'. Entry points hand playback context over
/// through the route instead of pre-filling a shared controller, which lets
/// [VideoPageController] live and die with the route.
sealed class VideoPlaybackArgs {
  const VideoPlaybackArgs({required this.bangumiItem});

  final BangumiItem bangumiItem;
}

class OnlineVideoPlaybackArgs extends VideoPlaybackArgs {
  const OnlineVideoPlaybackArgs({
    required super.bangumiItem,
    required this.plugin,
    required this.title,
    required this.src,
    required this.roads,
  });

  final Plugin plugin;
  final String title;
  final String src;
  final List<Road> roads;
}

class OfflineVideoPlaybackArgs extends VideoPlaybackArgs {
  const OfflineVideoPlaybackArgs({
    required super.bangumiItem,
    required this.pluginName,
    required this.episodeNumber,
    required this.road,
    required this.downloadedEpisodes,
  });

  final String pluginName;
  final int episodeNumber;
  final int road;
  final List<DownloadEpisode> downloadedEpisodes;
}

/// 本地媒体库播放参数：在应用内播放本地视频文件并关联弹幕。
class LocalMediaVideoPlaybackArgs extends VideoPlaybackArgs {
  const LocalMediaVideoPlaybackArgs({
    required super.bangumiItem,
    required this.files,
    required this.selectedIndex,
    required this.pluginName,
    this.bangumiSyncId,
  });

  /// 同一文件夹下的全部本地视频文件，支持选集切换。
  final List<LocalMediaFile> files;

  /// 本次点击要播放的文件在 [files] 中的索引。
  final int selectedIndex;

  /// 用于历史记录与弹幕缓存的标识，本地媒体固定为 'local'。
  final String pluginName;

  /// 已确认的 Bangumi subject ID，仅搜刮来源为 bangumi 时非空。
  /// 播放完成后的 Bangumi 进度联动用它；legacy/AniList 条目为 null 不触发同步。
  final int? bangumiSyncId;
}
