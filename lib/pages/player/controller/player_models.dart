import 'package:kazumi/services/video_source/video_source_format.dart';

class PlaybackInitParams {
  final String videoUrl;
  final int offset;
  final bool isLocalPlayback;
  final VideoSourceFormat videoSourceFormat;
  final int bangumiId;
  final String pluginName;
  final int episode;
  final int danmakuEpisodeNumber;
  final String pageUrl;

  /// 集数排序号，语义同 EpisodeRef.sortNumber（在线解析自标题、离线为 episodeNumber）。
  final int? sortNumber;
  final Map<String, String> httpHeaders;
  final bool adBlockerEnabled;
  final String episodeTitle;
  final String referer;
  final int currentRoad;
  final String? coverUrl;
  final String? bangumiName;

  /// 弹幕标题检索的备选名称（如英文名/罗马音），避免仅凭中文名匹配不到弹弹。
  final List<String>? bangumiNameAliases;

  /// 本地媒体库文件所在的目录，用于读写与视频同目录的弹幕侧车文件
  /// （`danmaku.json`）。仅本地媒体播放时非空。
  final String? localDanmakuDirectory;

  /// 弹幕侧车文件的番剧作用域（`danmaku_<ep>_<scope>.json`）。
  /// 同目录混放多部番剧时避免侧车文件互相覆盖；仅本地媒体播放时非空。
  final String? danmakuScope;

  const PlaybackInitParams({
    required this.videoUrl,
    required this.offset,
    required this.isLocalPlayback,
    required this.bangumiId,
    required this.pluginName,
    required this.episode,
    required this.danmakuEpisodeNumber,
    required this.httpHeaders,
    required this.adBlockerEnabled,
    required this.episodeTitle,
    required this.referer,
    required this.currentRoad,
    this.videoSourceFormat = VideoSourceFormat.auto,
    this.pageUrl = '',
    this.sortNumber,
    this.coverUrl,
    this.bangumiName,
    this.bangumiNameAliases,
    this.localDanmakuDirectory,
    this.danmakuScope,
  });
}

enum DanmakuDestination {
  chatRoom,
  remoteDanmaku,
}

class SyncPlayChatMessage {
  final String username;
  final String message;
  final bool fromRemote;
  final DateTime time;

  SyncPlayChatMessage({
    required this.username,
    required this.message,
    this.fromRemote = true,
    DateTime? time,
  }) : time = time ?? DateTime.now();
}
