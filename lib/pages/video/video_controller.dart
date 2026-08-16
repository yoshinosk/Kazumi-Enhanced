import 'dart:async';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/danmaku_axis_dialog.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/video_source/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/episode_url.dart';
import 'package:kazumi/utils/http_headers.dart';
import 'package:kazumi/utils/local_episode_parser.dart';
import 'package:kazumi/utils/media.dart';
import 'package:kazumi/utils/async_session.dart';
import 'package:kazumi/services/platform/display_mode_service.dart';
import 'package:path/path.dart' as p;

part 'video_controller.g.dart';

class VideoPageController = _VideoPageController with _$VideoPageController;

class VideoEpisodeSelection {
  const VideoEpisodeSelection({
    required this.episode,
    required this.road,
  });

  final int episode;
  final int road;

  @override
  bool operator ==(Object other) {
    return other is VideoEpisodeSelection &&
        other.episode == episode &&
        other.road == road;
  }

  @override
  int get hashCode => Object.hash(episode, road);

  @override
  String toString() {
    return 'VideoEpisodeSelection(episode: $episode, road: $road)';
  }
}

abstract class _VideoPageController with Store implements Disposable {
  _VideoPageController(
    this.historyController,
    this.downloadRepository,
    this.downloadManager,
  );

  late BangumiItem bangumiItem;

  // Resolution state machine: [_beginEpisodeSwitch] enters the loading state;
  // [_finishLoading] and [_failLoading] are the only terminal transitions.
  // [_errorMessage] is non-null only in the failed state.
  @readonly
  bool _loading = true;

  @readonly
  String? _errorMessage;

  @observable
  VideoEpisodeSelection selectedEpisode =
      const VideoEpisodeSelection(episode: 1, road: 0);

  @observable
  VideoEpisodeSelection? playingEpisode;

  @action
  void resetEpisodeState({int episode = 1, int road = 0}) {
    final selection = VideoEpisodeSelection(episode: episode, road: road);
    selectedEpisode = selection;
    playingEpisode = null;
  }

  VideoEpisodeSelection get playbackEpisode =>
      playingEpisode ?? selectedEpisode;

  @observable
  bool isFullscreen = false;

  // Playback and automatic danmaku loading have separate owners. Manual
  // danmaku selection can cancel auto danmaku without touching playback.
  final AsyncSessionOwner _playbackSessions = AsyncSessionOwner();
  final AsyncSessionOwner _danmakuSessions = AsyncSessionOwner();

  @observable
  bool isPip = false;

  @observable
  bool showTabBody = true;

  @observable
  int historyOffset = 0;

  @observable
  bool isOfflineMode = false;

  /// 本地媒体库播放模式：在应用内播放本地视频文件并关联弹幕。
  @observable
  bool isLocalMediaMode = false;

  /// 磁力边下边播模式：播放引擎流媒体服务器提供的 HTTP 流。
  @observable
  bool isStreamMode = false;

  PlaybackHistoryIdentity? _playbackHistoryIdentity;
  final Map<int, DownloadEpisode> _offlineEpisodesByNumber = {};
  final Map<int, int> _offlineDisplayRoadToOriginalRoad = {};
  final Map<int, int> _offlineOriginalRoadToDisplayRoad = {};

  /// Title reported by the video source; may differ from [bangumiItem]'s.
  String title = '';

  String src = '';

  @observable
  var roadList = ObservableList<Road>();

  late Plugin currentPlugin;

  String _offlinePluginName = '';

  String _localMediaPluginName = '';

  /// 边下边播的适配器标识（流 URL 与文件名保存在 roadList 中）。
  String _streamPluginName = '';

  int? _localMediaBangumiSyncId;

  /// 本地媒体模式下的 Bangumi subject ID，仅搜刮来源为 bangumi 时非空；
  /// 播放完成后的 Bangumi 进度联动应使用它，而不是 [bangumiItem] 的播放 ID。
  int? get bangumiSyncId => _localMediaBangumiSyncId;

  final HistoryController historyController;
  final IDownloadRepository downloadRepository;
  final IDownloadManager downloadManager;

  WebViewVideoSourceService? _videoSourceService;

  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();

  Stream<String> get logStream => _logStreamController.stream;

  StreamSubscription<String>? _logSubscription;

  /// Applies the route arguments exactly once, from [VideoPage.initState].
  @action
  void applyPlaybackArgs(VideoPlaybackArgs args) {
    switch (args) {
      case OnlineVideoPlaybackArgs():
        bangumiItem = args.bangumiItem;
        currentPlugin = args.plugin;
        title = args.title;
        src = args.src;
        roadList.clear();
        roadList.addAll(args.roads);
      case OfflineVideoPlaybackArgs():
        _initForOfflinePlayback(
          bangumiItem: args.bangumiItem,
          pluginName: args.pluginName,
          episodeNumber: args.episodeNumber,
          road: args.road,
          downloadedEpisodes: args.downloadedEpisodes,
        );
      case LocalMediaVideoPlaybackArgs():
        _initForLocalMediaPlayback(
          bangumiItem: args.bangumiItem,
          files: args.files,
          selectedIndex: args.selectedIndex,
          pluginName: args.pluginName,
          bangumiSyncId: args.bangumiSyncId,
        );
      case MagnetStreamVideoPlaybackArgs():
        _initForStreamPlayback(
          bangumiItem: args.bangumiItem,
          streamUrl: args.streamUrl,
          fileName: args.fileName,
          pluginName: args.pluginName,
        );
    }
  }

  @action
  void _initForOfflinePlayback({
    required BangumiItem bangumiItem,
    required String pluginName,
    required int episodeNumber,
    required int road,
    required List<DownloadEpisode> downloadedEpisodes,
  }) {
    this.bangumiItem = bangumiItem;
    _offlinePluginName = pluginName;
    title =
        bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name;
    isOfflineMode = true;
    _loading = false;

    _buildOfflineRoadList(downloadedEpisodes);

    final target = _findOfflineEpisodeByNumber(
      episodeNumber,
      preferredOriginalRoad: road,
    );
    final selected = VideoEpisodeSelection(
      episode: target?.listIndex ?? 1,
      road: target?.roadIndex ?? 0,
    );
    selectedEpisode = selected;
    playingEpisode = null;
    final resolvedEpisode = _resolveOfflineEpisode(
      selected.episode,
      road: selected.road,
    );
    if (resolvedEpisode != null) {
      _setOfflineHistoryIdentity(resolvedEpisode);
    } else {
      _playbackHistoryIdentity = null;
    }
    KazumiLogger().i(
        'VideoPageController: initialized for offline playback, episode $episodeNumber (position: ${selected.episode})');
  }

  void _buildOfflineRoadList(List<DownloadEpisode> episodes) {
    final snapshot = buildOfflineRoadListSnapshot(episodes);
    roadList.clear();
    roadList.addAll(snapshot.roads);
    _offlineEpisodesByNumber.clear();
    _offlineEpisodesByNumber.addAll(snapshot.episodesByNumber);
    _offlineDisplayRoadToOriginalRoad.clear();
    _offlineDisplayRoadToOriginalRoad
        .addAll(snapshot.displayRoadToOriginalRoad);
    _offlineOriginalRoadToDisplayRoad.clear();
    _offlineOriginalRoadToDisplayRoad
        .addAll(snapshot.originalRoadToDisplayRoad);
  }

  String get offlinePluginName => _offlinePluginName;

  /// 本地媒体 / 边下边播模式下的适配器标识（供音频会话等元数据使用）。
  String get streamOrLocalPluginName =>
      isStreamMode ? _streamPluginName : _localMediaPluginName;

  @action
  void _initForLocalMediaPlayback({
    required BangumiItem bangumiItem,
    required List<LocalMediaFile> files,
    required int selectedIndex,
    required String pluginName,
    required int? bangumiSyncId,
  }) {
    this.bangumiItem = bangumiItem;
    _localMediaPluginName = pluginName;
    _localMediaBangumiSyncId = bangumiSyncId;
    title =
        bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name;
    isLocalMediaMode = true;
    _loading = false;

    _buildLocalMediaRoadList(files);

    final safeIndex =
        files.isEmpty ? 0 : selectedIndex.clamp(0, files.length - 1);
    final selected = VideoEpisodeSelection(
      episode: safeIndex + 1,
      road: 0,
    );
    selectedEpisode = selected;
    playingEpisode = null;
    final resolvedEpisode = _resolveLocalMediaEpisode(
      selected.episode,
      road: selected.road,
    );
    if (resolvedEpisode != null) {
      _setLocalMediaHistoryIdentity(resolvedEpisode);
    } else {
      _playbackHistoryIdentity = null;
    }
    KazumiLogger().i(
        'VideoPageController: initialized for local media playback, index $selectedIndex (position: ${selected.episode})');
  }

  void _buildLocalMediaRoadList(List<LocalMediaFile> files) {
    roadList.clear();
    if (files.isEmpty) {
      return;
    }
    roadList.add(Road(
      name: '本地视频',
      data: files.map((f) => f.path).toList(),
      identifier: files.map((f) => f.name).toList(),
    ));
  }

  /// 边下边播初始化：单文件 HTTP 流，写入历史（adapterName=magnet-stream）。
  @action
  void _initForStreamPlayback({
    required BangumiItem bangumiItem,
    required String streamUrl,
    required String fileName,
    required String pluginName,
  }) {
    this.bangumiItem = bangumiItem;
    _streamPluginName = pluginName;
    title =
        bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name;
    isStreamMode = true;
    _loading = false;

    roadList.clear();
    roadList.add(Road(
      name: '边下边播',
      data: [streamUrl],
      identifier: [fileName.isEmpty ? '流式播放' : fileName],
    ));

    selectedEpisode = const VideoEpisodeSelection(episode: 1, road: 0);
    playingEpisode = null;
    // 边下边播写入历史（adapterName=magnet-stream）：流 URL 在引擎存活期间
    // 有效，历史页恢复时校验可达性；应用重启后引擎重建、URL 端口变化，
    // 历史页会提示从下载页重新开始。
    final parsed = parseLocalEpisodeNumber(fileName);
    final episodeNumber = parsed > 0 ? parsed : 1;
    _playbackHistoryIdentity = PlaybackHistoryIdentity.offline(
      bangumiItem: bangumiItem,
      pluginName: _streamPluginName,
      episodeNumber: episodeNumber,
      episodeTitle: fileName.isEmpty ? '流式播放' : fileName,
      road: 0,
      episodePageUrl: streamUrl,
    );
    KazumiLogger().i('VideoPageController: initialized for magnet streaming');
  }

  EpisodeRef? _resolveLocalMediaEpisode(int episode, {int? road}) {
    final targetRoad = road ?? selectedEpisode.road;
    if (roadList.isEmpty || targetRoad < 0 || targetRoad >= roadList.length) {
      return null;
    }
    final roadData = roadList[targetRoad];
    final index = episode - 1;
    if (index < 0 || index >= roadData.data.length) {
      return null;
    }
    final path = roadData.data[index];
    final name = (index < roadData.identifier.length &&
            roadData.identifier[index].isNotEmpty)
        ? roadData.identifier[index]
        : '本地视频';
    // 本地文件命名远比在线标题混乱（字幕组标签、分辨率、季度、发布档期都含
    // 数字），必须用专用解析器，否则会把 `1080p`/`10月新番`/`第2季` 里的数字
    // 当成集数，导致弹幕请求到错误分集。
    final parsed = parseLocalEpisodeNumber(name);
    final danmakuEp = parsed > 0 ? parsed : episode;
    return EpisodeRef.offline(
      listIndex: episode,
      roadIndex: targetRoad,
      displayTitle: name,
      pageUrl: path,
      episodeNumber: danmakuEp,
      originalRoadIndex: targetRoad,
    );
  }

  void _setLocalMediaHistoryIdentity(EpisodeRef episode) {
    _playbackHistoryIdentity = PlaybackHistoryIdentity.offline(
      bangumiItem: bangumiItem,
      pluginName: _localMediaPluginName,
      episodeNumber: episode.historyEpisodeNumber,
      episodeTitle: episode.displayTitle,
      road: episode.originalRoadIndex,
      episodePageUrl: episode.pageUrl,
    );
  }

  PlaybackHistoryIdentity? get currentHistoryIdentity =>
      _playbackHistoryIdentity;

  ({int listIndex, int roadIndex})? _findOfflineEpisodeByNumber(
    int episodeNumber, {
    required int preferredOriginalRoad,
  }) {
    if (episodeNumber <= 0 || roadList.isEmpty) {
      return null;
    }
    final preferredDisplayRoad =
        _offlineOriginalRoadToDisplayRoad[preferredOriginalRoad];
    final roadIndices = <int>[
      if (preferredDisplayRoad != null) preferredDisplayRoad,
      for (var i = 0; i < roadList.length; i++)
        if (i != preferredDisplayRoad) i,
    ];
    for (final roadIndex in roadIndices) {
      final match = _findOfflineEpisodeInDisplayRoad(episodeNumber, roadIndex);
      if (match != null) {
        return match;
      }
    }
    return null;
  }

  ({int listIndex, int roadIndex})? _findOfflineEpisodeInDisplayRoad(
    int episodeNumber,
    int roadIndex,
  ) {
    if (roadIndex < 0 || roadIndex >= roadList.length) {
      return null;
    }
    final index = roadList[roadIndex].data.indexOf(episodeNumber.toString());
    if (index < 0) {
      return null;
    }
    return (listIndex: index + 1, roadIndex: roadIndex);
  }

  int getHistoryOffsetFor(PlaybackHistoryIdentity identity) {
    final playResume = GStorage.getSetting(SettingsKeys.playResume);
    if (playResume != true) {
      return 0;
    }
    return historyController
            .findProgress(
              identity.bangumiItem,
              identity.pluginName,
              identity.episodeNumber,
              entryKind: identity.entryKind,
            )
            ?.progress
            .inSeconds ??
        0;
  }

  void _setOnlineHistoryIdentity(EpisodeRef episode) {
    _playbackHistoryIdentity = PlaybackHistoryIdentity.online(
      bangumiItem: bangumiItem,
      pluginName: currentPlugin.name,
      episodeNumber: episode.historyEpisodeNumber,
      episodeTitle: episode.displayTitle,
      road: episode.originalRoadIndex,
      onlineBangumiSrc: src,
      episodePageUrl: episode.pageUrl,
    );
  }

  void _setOfflineHistoryIdentity(EpisodeRef episode) {
    _playbackHistoryIdentity = PlaybackHistoryIdentity.offline(
      bangumiItem: bangumiItem,
      pluginName: _offlinePluginName,
      episodeNumber: episode.historyEpisodeNumber,
      episodeTitle: episode.displayTitle,
      road: episode.originalRoadIndex,
      episodePageUrl: episode.pageUrl,
    );
  }

  EpisodeRef? _resolveOnlineEpisode(int episode, {int? road}) {
    final targetRoad = road ?? selectedEpisode.road;
    if (roadList.isEmpty || targetRoad < 0 || targetRoad >= roadList.length) {
      return null;
    }
    final roadData = roadList[targetRoad];
    final index = episode - 1;
    if (index < 0 ||
        index >= roadData.data.length ||
        index >= roadData.identifier.length) {
      return null;
    }
    final displayTitle = roadData.identifier[index];
    return EpisodeRef.online(
      listIndex: episode,
      roadIndex: targetRoad,
      displayTitle: displayTitle,
      pageUrl: roadData.data[index],
    );
  }

  EpisodeRef? _resolveOfflineEpisode(int episode, {int? road}) {
    final targetRoad = road ?? selectedEpisode.road;
    if (roadList.isEmpty || targetRoad < 0 || targetRoad >= roadList.length) {
      return null;
    }
    final roadData = roadList[targetRoad];
    final index = episode - 1;
    if (index < 0 ||
        index >= roadData.data.length ||
        index >= roadData.identifier.length) {
      return null;
    }
    final episodeNumber = int.tryParse(roadData.data[index]);
    if (episodeNumber == null) {
      return null;
    }
    final downloadEpisode = _offlineEpisodesByNumber[episodeNumber];
    final titleFromRoad = roadData.identifier[index];
    final episodeTitle = downloadEpisode?.episodeName.isNotEmpty == true
        ? downloadEpisode!.episodeName
        : (titleFromRoad.isNotEmpty ? titleFromRoad : '第$episodeNumber集');
    return EpisodeRef.offline(
      listIndex: episode,
      roadIndex: targetRoad,
      displayTitle: episodeTitle,
      pageUrl: downloadEpisode?.episodePageUrl ?? '',
      episodeNumber: episodeNumber,
      originalRoadIndex: downloadEpisode?.road ??
          _offlineDisplayRoadToOriginalRoad[targetRoad] ??
          targetRoad,
    );
  }

  EpisodeRef? resolveEpisode(VideoEpisodeSelection selection) {
    if (isOfflineMode) {
      return _resolveOfflineEpisode(selection.episode, road: selection.road);
    }
    if (isLocalMediaMode) {
      return _resolveLocalMediaEpisode(selection.episode, road: selection.road);
    }
    if (isStreamMode) {
      return _resolveStreamEpisode(selection.episode, road: selection.road);
    }
    return _resolveOnlineEpisode(selection.episode, road: selection.road);
  }

  /// 边下边播集数解析：固定单文件，集数从文件名解析（失败回退 1）。
  EpisodeRef? _resolveStreamEpisode(int episode, {int? road}) {
    if (roadList.isEmpty || episode != 1) {
      return null;
    }
    final roadData = roadList.first;
    if (roadData.data.isEmpty) {
      return null;
    }
    final name =
        roadData.identifier.isNotEmpty ? roadData.identifier.first : '流式播放';
    final parsed = parseLocalEpisodeNumber(name);
    final episodeNumber = parsed > 0 ? parsed : 1;
    return EpisodeRef.offline(
      listIndex: 1,
      roadIndex: 0,
      displayTitle: name,
      pageUrl: roadData.data.first,
      episodeNumber: episodeNumber,
      originalRoadIndex: 0,
    );
  }

  /// Resets pre-switch state as a single transaction so observers see one
  /// notification instead of one per field.
  @action
  void _beginEpisodeSwitch(VideoEpisodeSelection selection) {
    selectedEpisode = selection;
    playingEpisode = null;
    _loading = true;
    _errorMessage = null;
  }

  @action
  void _applyResolvedSelection(EpisodeRef resolvedEpisode) {
    selectedEpisode = VideoEpisodeSelection(
      episode: resolvedEpisode.listIndex,
      road: resolvedEpisode.roadIndex,
    );
  }

  @action
  void _finishLoading() {
    _loading = false;
  }

  @action
  void _failLoading(String message) {
    _loading = false;
    _errorMessage = message;
  }

  Future<void> changeEpisode(
    int episode, {
    int currentRoad = 0,
    int offset = 0,
    required PlayerController playerController,
  }) async {
    final session = _playbackSessions.begin();
    final selection = VideoEpisodeSelection(
      episode: episode,
      road: currentRoad,
    );
    _beginEpisodeSwitch(selection);
    _danmakuSessions.cancel();
    playerController.danmaku.finishDanmakuLoad();
    _videoSourceService?.cancel();

    await playerController.stop();
    if (session.isStale) {
      return;
    }

    if (isOfflineMode) {
      await _changeOfflineEpisode(
        selection,
        offset,
        session: session,
        playerController: playerController,
      );
      return;
    }

    if (isLocalMediaMode) {
      await _changeLocalMediaEpisode(
        selection,
        offset,
        session: session,
        playerController: playerController,
      );
      return;
    }

    if (isStreamMode) {
      await _changeStreamEpisode(
        selection,
        offset,
        session: session,
        playerController: playerController,
      );
      return;
    }

    final resolvedEpisode = _resolveOnlineEpisode(episode, road: currentRoad);
    if (resolvedEpisode == null) {
      KazumiLogger().e(
          'VideoPageController: failed to resolve online episode. road=$currentRoad, episode=$episode');
      _failLoading('集数解析失败');
      return;
    }

    _applyResolvedSelection(resolvedEpisode);
    _setOnlineHistoryIdentity(resolvedEpisode);

    KazumiLogger()
        .i('VideoPageController: changed to ${resolvedEpisode.displayTitle}');
    final urlItem = normalizeEpisodeUrl(
      currentPlugin.baseUrl,
      resolvedEpisode.pageUrl,
    );

    await _resolveWithVideoSourceService(
      urlItem,
      offset,
      resolvedEpisode: resolvedEpisode,
      session: session,
      playerController: playerController,
    );
  }

  Future<void> _changeOfflineEpisode(
    VideoEpisodeSelection selection,
    int offset, {
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    final resolvedEpisode =
        _resolveOfflineEpisode(selection.episode, road: selection.road);
    if (resolvedEpisode == null) {
      KazumiLogger().e(
          'VideoPageController: failed to resolve offline episode. road=${selection.road}, episode=${selection.episode}');
      _failLoading('集数解析失败');
      return;
    }

    final localPath = _getLocalVideoPath(
      bangumiItem.id,
      _offlinePluginName,
      resolvedEpisode.historyEpisodeNumber,
    );
    if (localPath == null) {
      _failLoading('该集数未下载');
      return;
    }
    _applyResolvedSelection(resolvedEpisode);
    _setOfflineHistoryIdentity(resolvedEpisode);
    if (session.isStale) {
      return;
    }
    _finishLoading();
    final resolvedOffset =
        offset > 0 ? offset : getHistoryOffsetFor(_playbackHistoryIdentity!);

    KazumiLogger().i(
        'VideoPageController: offline episode changed to ${resolvedEpisode.historyEpisodeNumber} (index: ${selection.episode}), path: $localPath');

    final params = PlaybackInitParams(
      videoUrl: localPath,
      offset: resolvedOffset,
      isLocalPlayback: true,
      bangumiId: bangumiItem.id,
      pluginName: _offlinePluginName,
      episode: resolvedEpisode.listIndex,
      danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
      pageUrl: resolvedEpisode.pageUrl,
      sortNumber: resolvedEpisode.sortNumber,
      httpHeaders: {},
      adBlockerEnabled: false,
      episodeTitle: resolvedEpisode.displayTitle,
      referer: '',
      currentRoad: resolvedEpisode.roadIndex,
      coverUrl: bangumiItem.images['large'],
      bangumiName:
          bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name,
    );

    final initialized = await playerController.init(params);
    if (session.isActive && initialized) {
      playingEpisode = selection;
      unawaited(_loadPlaybackDanmaku(playerController, params, session));
    } else if (session.isActive) {
      _playbackSessions.cancel();
    }
  }

  /// 弹幕标题检索的候选名，按命中概率排序。
  ///
  /// 注意不要把原始文件名直接作为候选：`[组名][番名][01][1080p][CHS]` 这类
  /// 字符串在弹弹番剧库中几乎不可能命中，必须先清洗出干净的番剧名。
  List<String> _danmakuTitleAliases(String displayTitle) {
    final sanitized = sanitizeAnimeTitle(displayTitle);
    final aliases = <String>{
      bangumiItem.nameCn,
      bangumiItem.name,
      if (sanitized.isNotEmpty) sanitized,
    };
    return aliases.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  /// 弹幕侧车文件的作用域：用番剧名哈希区分同目录混放的多部番剧。
  String get _localMediaDanmakuScope {
    final title =
        bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name;
    return danmakuSidecarScope(title);
  }

  Future<void> _changeLocalMediaEpisode(
    VideoEpisodeSelection selection,
    int offset, {
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    final resolvedEpisode =
        _resolveLocalMediaEpisode(selection.episode, road: selection.road);
    if (resolvedEpisode == null) {
      KazumiLogger().e(
          'VideoPageController: failed to resolve local media episode. road=${selection.road}, episode=${selection.episode}');
      _failLoading('集数解析失败');
      return;
    }

    final localPath = resolvedEpisode.pageUrl;
    if (localPath.isEmpty) {
      _failLoading('文件路径为空');
      return;
    }
    _applyResolvedSelection(resolvedEpisode);
    _setLocalMediaHistoryIdentity(resolvedEpisode);
    if (session.isStale) {
      return;
    }
    _finishLoading();
    final resolvedOffset =
        offset > 0 ? offset : getHistoryOffsetFor(_playbackHistoryIdentity!);

    KazumiLogger().i(
        'VideoPageController: local media episode changed to ${resolvedEpisode.historyEpisodeNumber} (index: ${selection.episode}), path: $localPath');

    final params = PlaybackInitParams(
      videoUrl: localPath,
      offset: resolvedOffset,
      isLocalPlayback: true,
      bangumiId: bangumiItem.id,
      pluginName: _localMediaPluginName,
      episode: resolvedEpisode.listIndex,
      danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
      pageUrl: resolvedEpisode.pageUrl,
      sortNumber: resolvedEpisode.sortNumber,
      httpHeaders: {},
      adBlockerEnabled: false,
      episodeTitle: resolvedEpisode.displayTitle,
      referer: '',
      currentRoad: resolvedEpisode.roadIndex,
      coverUrl: bangumiItem.images['large'],
      bangumiName:
          bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name,
      bangumiNameAliases: _danmakuTitleAliases(resolvedEpisode.displayTitle),
      localDanmakuDirectory: p.dirname(localPath),
      danmakuScope: _localMediaDanmakuScope,
    );

    final initialized = await playerController.init(params);
    if (session.isActive && initialized) {
      playingEpisode = selection;
      unawaited(_loadPlaybackDanmaku(playerController, params, session));
    } else if (session.isActive) {
      _playbackSessions.cancel();
    }
  }

  Future<void> _changeStreamEpisode(
    VideoEpisodeSelection selection,
    int offset, {
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    final resolvedEpisode =
        _resolveStreamEpisode(selection.episode, road: selection.road);
    if (resolvedEpisode == null) {
      KazumiLogger().e(
          'VideoPageController: failed to resolve stream episode. road=${selection.road}, episode=${selection.episode}');
      _failLoading('流解析失败');
      return;
    }
    _applyResolvedSelection(resolvedEpisode);
    _playbackHistoryIdentity = PlaybackHistoryIdentity.offline(
      bangumiItem: bangumiItem,
      pluginName: _streamPluginName,
      episodeNumber: resolvedEpisode.historyEpisodeNumber,
      episodeTitle: resolvedEpisode.displayTitle,
      road: 0,
      episodePageUrl: resolvedEpisode.pageUrl,
    );
    if (session.isStale) {
      return;
    }
    _finishLoading();

    KazumiLogger().i(
        'VideoPageController: stream episode changed to ${resolvedEpisode.historyEpisodeNumber}, url: ${resolvedEpisode.pageUrl}');

    final params = PlaybackInitParams(
      videoUrl: resolvedEpisode.pageUrl,
      offset: offset,
      isLocalPlayback: false,
      bangumiId: bangumiItem.id,
      pluginName: _streamPluginName,
      episode: resolvedEpisode.listIndex,
      danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
      pageUrl: '',
      sortNumber: resolvedEpisode.sortNumber,
      httpHeaders: {},
      adBlockerEnabled: false,
      episodeTitle: resolvedEpisode.displayTitle,
      referer: '',
      currentRoad: resolvedEpisode.roadIndex,
      coverUrl: bangumiItem.images['large'],
      bangumiName:
          bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name,
      bangumiNameAliases: _danmakuTitleAliases(resolvedEpisode.displayTitle),
    );

    final initialized = await playerController.init(params);
    if (session.isActive && initialized) {
      playingEpisode = selection;
      unawaited(_loadPlaybackDanmaku(playerController, params, session));
    } else if (session.isActive) {
      _playbackSessions.cancel();
    }
  }

  Future<void> _loadPlaybackDanmaku(
    PlayerController playerController,
    PlaybackInitParams params,
    AsyncSession session,
  ) async {
    final danmakuSession = _danmakuSessions.begin();
    playerController.danmaku.beginDanmakuLoad();
    try {
      final result = await playerController.danmaku.fetchDanmaku(
        params.bangumiId,
        params.pluginName,
        params.danmakuEpisodeNumber,
        localDanmakuDirectory: params.localDanmakuDirectory,
        // 本地播放时 videoUrl 就是文件绝对路径，用于弹弹 Play 的文件哈希匹配。
        localVideoPath: params.isLocalPlayback ? params.videoUrl : null,
        bangumiName: params.bangumiName,
        bangumiNameAliases: params.bangumiNameAliases,
        danmakuScope: params.danmakuScope,
      );
      if (session.isActive && danmakuSession.isActive) {
        if (result.hasDanmakus) {
          final bool enableDanmaku =
              GStorage.getSetting(SettingsKeys.danmakuEnabledByDefault);
          playerController.danmaku.applyDanmakuLoad(
            result,
            enableDanmaku: enableDanmaku,
            animeTitle: result.animeTitle.isNotEmpty
                ? result.animeTitle
                : params.bangumiName,
            episodeTitle: result.episodeTitle.isNotEmpty
                ? result.episodeTitle
                : '第${params.danmakuEpisodeNumber}集',
          );
          if (enableDanmaku) {
            unawaited(
              checkDanmakuAxisAlignment(
                playerController: playerController,
                videoPageController: this as VideoPageController,
                danmakus: result.danmakus,
                shouldProceed: () =>
                    session.isActive && danmakuSession.isActive,
              ),
            );
          }
        } else {
          playerController.danmaku.applyUnavailableDanmakuLoad(result);
          playerController.danmaku.applyDanmakuBinding(
            animeTitle: result.animeTitle.isNotEmpty
                ? result.animeTitle
                : params.bangumiName,
            episodeTitle: result.episodeTitle.isNotEmpty
                ? result.episodeTitle
                : '第${params.danmakuEpisodeNumber}集',
          );
          if (result.isFailed) {
            KazumiDialog.showToast(message: '弹幕加载失败，可手动检索');
          }
        }
      }
    } catch (e) {
      if (session.isActive && danmakuSession.isActive) {
        playerController.danmaku.finishDanmakuLoad(disableDanmaku: true);
        KazumiDialog.showToast(message: '弹幕加载失败，可手动检索');
      }
      KazumiLogger().w('VideoPageController: failed to load danmaku', error: e);
    }
  }

  void cancelAutomaticDanmakuLoad() {
    _danmakuSessions.cancel();
  }

  String? _getLocalVideoPath(
      int bangumiId, String pluginName, int episodeNumber) {
    final episode =
        downloadRepository.getEpisode(bangumiId, pluginName, episodeNumber);
    return downloadManager.getLocalVideoPath(episode);
  }

  Future<void> _resolveWithVideoSourceService(
    String url,
    int offset, {
    required EpisodeRef resolvedEpisode,
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    _videoSourceService ??= WebViewVideoSourceService();

    await _logSubscription?.cancel();
    _logSubscription = _videoSourceService!.onLog.listen((log) {
      if (!_logStreamController.isClosed) {
        _logStreamController.add(log);
      }
    });

    try {
      final source = await _videoSourceService!.resolve(
        url,
        useLegacyParser: currentPlugin.useLegacyParser,
        offset: offset,
      );

      if (session.isStale) {
        return;
      }
      _finishLoading();
      KazumiLogger()
          .i('VideoPageController: resolved video URL: ${source.url}');

      final bool forceAdBlocker =
          GStorage.getSetting(SettingsKeys.forceAdBlocker);

      final params = PlaybackInitParams(
        videoUrl: source.url,
        offset: source.offset,
        isLocalPlayback: false,
        videoSourceFormat: source.format,
        bangumiId: bangumiItem.id,
        pluginName: currentPlugin.name,
        episode: resolvedEpisode.listIndex,
        danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
        pageUrl: resolvedEpisode.pageUrl,
        sortNumber: resolvedEpisode.sortNumber,
        httpHeaders: {
          'user-agent': currentPlugin.userAgent.isEmpty
              ? getRandomUA()
              : currentPlugin.userAgent,
          if (currentPlugin.referer.isNotEmpty)
            'referer': currentPlugin.referer,
        },
        adBlockerEnabled: forceAdBlocker || currentPlugin.adBlocker,
        episodeTitle: resolvedEpisode.displayTitle,
        referer: currentPlugin.referer,
        currentRoad: resolvedEpisode.roadIndex,
        coverUrl: bangumiItem.images['large'],
        bangumiName: bangumiItem.nameCn.isNotEmpty
            ? bangumiItem.nameCn
            : bangumiItem.name,
      );

      final initialized = await playerController.init(params);
      if (session.isActive && initialized) {
        playingEpisode = VideoEpisodeSelection(
          episode: resolvedEpisode.listIndex,
          road: resolvedEpisode.roadIndex,
        );
        unawaited(_loadPlaybackDanmaku(playerController, params, session));
      } else if (session.isActive) {
        _playbackSessions.cancel();
      }
    } on VideoSourceTimeoutException {
      if (session.isStale) {
        return;
      }
      _failLoading('视频解析超时，请重试');
    } on VideoSourceCancelledException {
      KazumiLogger().i('VideoPageController: video URL resolution cancelled');
    } catch (e) {
      if (session.isStale) {
        return;
      }
      _failLoading('视频解析失败：${e.toString()}');
    }
  }

  /// Called by Modular when the '/video' route scope is disposed.
  @override
  void dispose() {
    _playbackSessions.cancel();
    _danmakuSessions.cancel();
    _logSubscription?.cancel();
    _logSubscription = null;
    if (!_logStreamController.isClosed) {
      _logStreamController.close();
    }
    final videoSourceService = _videoSourceService;
    _videoSourceService = null;
    if (videoSourceService != null) {
      unawaited(videoSourceService.dispose());
    }
  }

  void enterFullScreen() {
    isFullscreen = true;
    DisplayModeService.enterFullScreen(lockOrientation: false);
  }

  void exitFullScreen() {
    isFullscreen = false;
    DisplayModeService.exitFullScreen();
  }

  void isDesktopFullscreen() async {
    if (isDesktop()) {
      isFullscreen = await windowManager.isFullScreen();
    }
  }

  void handleOnEnterFullScreen() async {
    isFullscreen = true;
  }

  void handleOnExitFullScreen() async {
    isFullscreen = false;
  }
}

class OfflineRoadListSnapshot {
  const OfflineRoadListSnapshot({
    required this.roads,
    required this.episodesByNumber,
    required this.displayRoadToOriginalRoad,
    required this.originalRoadToDisplayRoad,
  });

  final List<Road> roads;
  final Map<int, DownloadEpisode> episodesByNumber;
  final Map<int, int> displayRoadToOriginalRoad;
  final Map<int, int> originalRoadToDisplayRoad;
}

OfflineRoadListSnapshot buildOfflineRoadListSnapshot(
  List<DownloadEpisode> episodes,
) {
  final groupedEpisodes = <int, List<DownloadEpisode>>{};
  final episodesByNumber = <int, DownloadEpisode>{};

  for (final episode in episodes) {
    episodesByNumber[episode.episodeNumber] = episode;
    groupedEpisodes.putIfAbsent(episode.road, () => []).add(episode);
  }

  final originalRoads = groupedEpisodes.keys.toList()..sort();
  final roads = <Road>[];
  final displayRoadToOriginalRoad = <int, int>{};
  final originalRoadToDisplayRoad = <int, int>{};

  for (final originalRoad in originalRoads) {
    final roadEpisodes = groupedEpisodes[originalRoad]!
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    final displayRoad = roads.length;
    displayRoadToOriginalRoad[displayRoad] = originalRoad;
    originalRoadToDisplayRoad[originalRoad] = displayRoad;
    roads.add(Road(
      name: originalRoad >= 0
          ? '播放列表${originalRoad + 1}'
          : '播放列表${displayRoad + 1}',
      data: roadEpisodes.map((e) => e.episodeNumber.toString()).toList(),
      identifier: roadEpisodes
          .map((e) =>
              e.episodeName.isNotEmpty ? e.episodeName : '第${e.episodeNumber}集')
          .toList(),
    ));
  }

  return OfflineRoadListSnapshot(
    roads: roads,
    episodesByNumber: episodesByNumber,
    displayRoadToOriginalRoad: displayRoadToOriginalRoad,
    originalRoadToDisplayRoad: originalRoadToDisplayRoad,
  );
}

class EpisodeRef {
  const EpisodeRef({
    required this.listIndex,
    required this.roadIndex,
    required this.displayTitle,
    required this.pageUrl,
    required this.sortNumber,
    required this.historyEpisodeNumber,
    required this.danmakuEpisodeNumber,
    required this.originalRoadIndex,
  });

  final int listIndex;
  final int roadIndex;
  final String displayTitle;
  final String pageUrl;

  /// Episode sort number.
  /// - Online: parsed from [displayTitle] via [extractEpisodeNumber];
  ///   null when unparsable.
  /// - Offline: always the download record's episodeNumber.
  final int? sortNumber;
  final int historyEpisodeNumber;
  final int danmakuEpisodeNumber;
  final int originalRoadIndex;

  factory EpisodeRef.online({
    required int listIndex,
    required int roadIndex,
    required String displayTitle,
    required String pageUrl,
  }) {
    final parsedEpisodeNumber = extractEpisodeNumber(displayTitle);
    return EpisodeRef(
      listIndex: listIndex,
      roadIndex: roadIndex,
      displayTitle: displayTitle,
      pageUrl: pageUrl,
      sortNumber: parsedEpisodeNumber > 0 ? parsedEpisodeNumber : null,
      historyEpisodeNumber: listIndex,
      danmakuEpisodeNumber:
          parsedEpisodeNumber > 0 ? parsedEpisodeNumber : listIndex,
      originalRoadIndex: roadIndex,
    );
  }

  const factory EpisodeRef.offline({
    required int listIndex,
    required int roadIndex,
    required String displayTitle,
    required String pageUrl,
    required int episodeNumber,
    required int originalRoadIndex,
  }) = _OfflineEpisodeRef;
}

class _OfflineEpisodeRef extends EpisodeRef {
  const _OfflineEpisodeRef({
    required super.listIndex,
    required super.roadIndex,
    required super.displayTitle,
    required super.pageUrl,
    required int episodeNumber,
    required super.originalRoadIndex,
  }) : super(
          sortNumber: episodeNumber,
          historyEpisodeNumber: episodeNumber,
          danmakuEpisodeNumber: episodeNumber,
        );
}
