// ignore_for_file: library_private_types_in_public_api

import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/player/controller/player_models.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/request/apis/danmaku_api.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/utils/danmaku.dart';

part 'player_danmaku_controller.g.dart';

class PlayerDanmakuController = _PlayerDanmakuController
    with _$PlayerDanmakuController;

enum DanmakuLoadStatus {
  success,
  empty,
  failed,
}

class DanmakuLoadResult {
  const DanmakuLoadResult({
    required this.danmakus,
    required this.bangumiID,
    required this.status,
    this.animeTitle = '',
    this.episodeTitle = '',
  });

  factory DanmakuLoadResult.success({
    required List<DanmakuEntry> danmakus,
    required int bangumiID,
    String animeTitle = '',
    String episodeTitle = '',
  }) {
    return DanmakuLoadResult(
      danmakus: danmakus,
      bangumiID: bangumiID,
      status: danmakus.isEmpty
          ? DanmakuLoadStatus.empty
          : DanmakuLoadStatus.success,
      animeTitle: animeTitle,
      episodeTitle: episodeTitle,
    );
  }

  factory DanmakuLoadResult.failed({
    required int bangumiID,
    String animeTitle = '',
    String episodeTitle = '',
  }) {
    return DanmakuLoadResult(
      danmakus: const [],
      bangumiID: bangumiID,
      status: DanmakuLoadStatus.failed,
      animeTitle: animeTitle,
      episodeTitle: episodeTitle,
    );
  }

  final List<DanmakuEntry> danmakus;
  final int bangumiID;
  final DanmakuLoadStatus status;

  /// 弹幕来源番剧标题（弹弹 Play 侧），检索/文件匹配时可获知。
  final String animeTitle;

  /// 弹幕来源分集标题（弹弹 Play 侧）。
  final String episodeTitle;

  bool get hasDanmakus => status == DanmakuLoadStatus.success;

  bool get isFailed => status == DanmakuLoadStatus.failed;
}

class DanmakuTimeline {
  static int? resolveSourceSecond(
    Duration playbackPosition,
    double timelineOffsetSeconds,
  ) {
    final sourceMilliseconds = playbackPosition.inMilliseconds -
        (timelineOffsetSeconds * 1000).round();
    if (sourceMilliseconds < 0) {
      return null;
    }
    return Duration(milliseconds: sourceMilliseconds).inSeconds;
  }

  static int staggerDelayMilliseconds({
    required int index,
    required int total,
  }) {
    if (total <= 0) {
      return 0;
    }
    return index * 1000 ~/ total;
  }
}

abstract class _PlayerDanmakuController with Store {
  _PlayerDanmakuController({
    required this.isLocalPlayback,
    required this.downloadController,
  });

  final bool Function() isLocalPlayback;
  final DownloadController downloadController;

  late canvas.DanmakuController canvasController;

  final Map<int, List<DanmakuEntry>> danDanmakus = {};
  @observable
  bool danmakuOn = false;
  @observable
  bool danmakuLoading = false;
  DanmakuDestination danmakuDestination = DanmakuDestination.remoteDanmaku;

  @observable
  int bangumiID = 0;

  /// 当前弹幕绑定到的番剧标题（弹弹 Play 侧；自动加载回退为本地番剧标题）。
  @observable
  String danmakuAnimeTitle = '';

  /// 当前弹幕绑定到的分集标题（弹弹 Play 侧；自动加载回退为「第X集」）。
  @observable
  String danmakuEpisodeTitle = '';

  /// 当前弹幕绑定到的分集 ID，仅在手动绑定/文件匹配时可知。
  int danmakuEpisodeId = 0;
  int _scheduledDanmakuGeneration = 0;

  int get scheduledDanmakuGeneration => _scheduledDanmakuGeneration;

  double get timelineOffsetSeconds {
    final offset = GStorage.getSetting(SettingsKeys.danmakuTimeOffset);
    return offset;
  }

  int? resolveDanmakuSecond(Duration playbackPosition) {
    return DanmakuTimeline.resolveSourceSecond(
      playbackPosition,
      timelineOffsetSeconds,
    );
  }

  List<DanmakuEntry> danmakusForPlaybackPosition(Duration playbackPosition) {
    final danmakuSecond = resolveDanmakuSecond(playbackPosition);
    if (danmakuSecond == null) {
      return const [];
    }
    return danDanmakus[danmakuSecond] ?? const [];
  }

  @action
  void setDanmakuEnabled(bool value) {
    danmakuOn = value;
  }

  void clearAndInvalidateScheduledDanmakus() {
    _scheduledDanmakuGeneration++;
    canvasController.clear();
  }

  // Fetching must not mutate current danmaku state; VideoPageController applies
  // the result only after confirming the playback session is still current.
  Future<DanmakuLoadResult> fetchDanmaku(
    int bangumiId,
    String pluginName,
    int episode, {
    String? localDanmakuDirectory,
    String? localVideoPath,
    String? bangumiName,
    List<String>? bangumiNameAliases,
    String? danmakuScope,
  }) async {
    if (isLocalPlayback()) {
      return await _fetchCachedDanmaku(
        bangumiId,
        pluginName,
        episode,
        localDanmakuDirectory: localDanmakuDirectory,
        localVideoPath: localVideoPath,
        bangumiName: bangumiName,
        bangumiNameAliases: bangumiNameAliases,
        danmakuScope: danmakuScope,
      );
    }
    return await _fetchDanDanmakuByBgmBangumiID(
      bangumiId,
      episode,
    );
  }

  @action
  void beginDanmakuLoad() {
    danDanmakus.clear();
    danmakuEpisodeId = 0;
    danmakuLoading = true;
  }

  @action
  void applyDanmakuLoad(
    DanmakuLoadResult result, {
    required bool enableDanmaku,
    String? animeTitle,
    String? episodeTitle,
  }) {
    bangumiID = result.bangumiID;
    addDanmakus(result.danmakus);
    danmakuOn = enableDanmaku;
    danmakuLoading = false;
    applyDanmakuBinding(animeTitle: animeTitle, episodeTitle: episodeTitle);
  }

  /// 更新弹幕绑定信息（当前弹幕来自哪部番剧的哪一集）。空字符串不会被覆盖。
  @action
  void applyDanmakuBinding({String? animeTitle, String? episodeTitle}) {
    if (animeTitle != null && animeTitle.isNotEmpty) {
      danmakuAnimeTitle = animeTitle;
    }
    if (episodeTitle != null && episodeTitle.isNotEmpty) {
      danmakuEpisodeTitle = episodeTitle;
    }
  }

  @action
  void applyUnavailableDanmakuLoad(DanmakuLoadResult result) {
    bangumiID = result.bangumiID;
    danDanmakus.clear();
    danmakuOn = false;
    danmakuLoading = false;
  }

  @action
  void finishDanmakuLoad({bool disableDanmaku = false}) {
    if (disableDanmaku) {
      danDanmakus.clear();
      danmakuOn = false;
    }
    danmakuLoading = false;
  }

  /// 本地播放（下载缓存 / 本地媒体库）的弹幕获取策略链，按可靠性从高到低：
  ///
  /// 1. 同目录弹幕侧车文件 —— 用户手动放置或此前匹配成功后写入的缓存
  /// 2. 下载库中的弹幕缓存
  /// 3. **弹弹 Play 文件哈希匹配**（`/api/v2/match`）—— 本地文件的首选方案，
  ///    直接命中 `episodeId`，不依赖文件名集数解析与 BGM ID 映射
  /// 4. BGM ID → 弹弹 ID 映射 —— 仅当搜刮命中 Bangumi 时可用
  /// 5. 清洗后的标题检索 —— 最后兜底
  Future<DanmakuLoadResult> _fetchCachedDanmaku(
      int bangumiId,
      String pluginName,
      int episode, {
      String? localDanmakuDirectory,
      String? localVideoPath,
      String? bangumiName,
      List<String>? bangumiNameAliases,
      String? danmakuScope}) async {
    KazumiLogger().i(
        'PlayerController: attempting to load cached danmaku for episode $episode');
    var nextBangumiID = bangumiID;
    var bgmResolved = false;
    final bool hasLocalDirectory =
        localDanmakuDirectory != null && localDanmakuDirectory.isNotEmpty;
    final bool hasLocalFile =
        localVideoPath != null && localVideoPath.isNotEmpty;
    final scope = danmakuScope ?? '';

    // --- 1 & 2. 本地缓存 ---
    try {
      if (hasLocalDirectory) {
        final sidecar = await downloadController
            .readDirectoryDanmaku(localDanmakuDirectory,
                episode: episode, scope: scope);
        if (sidecar != null && sidecar.danmakus.isNotEmpty) {
          KazumiLogger().i(
              'PlayerController: loaded ${sidecar.danmakus.length} danmakus from local danmaku file');
          return DanmakuLoadResult.success(
            danmakus: sidecar.danmakus,
            bangumiID: sidecar.danDanBangumiID,
          );
        }
      }

      final cachedDanmakus = await downloadController.getCachedDanmakus(
        bangumiId,
        pluginName,
        episode,
      );
      if (cachedDanmakus != null && cachedDanmakus.isNotEmpty) {
        KazumiLogger().i(
            'PlayerController: loaded ${cachedDanmakus.length} cached danmakus');
        return DanmakuLoadResult.success(
          danmakus: cachedDanmakus,
          bangumiID: nextBangumiID,
        );
      }
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: failed to load cached danmaku', error: e);
      return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
    }

    // --- 3. 文件哈希精确匹配 ---
    if (hasLocalFile) {
      final matched = await _fetchDanmakuByFileMatch(
        localVideoPath,
        localDanmakuDirectory: localDanmakuDirectory,
        episode: episode,
        danmakuScope: scope,
      );
      if (matched != null) return matched;
    }

    // --- 4. BGM ID → 弹弹 ID 映射 ---
    // 本地媒体库的 bangumiId 可能是搜刮命中 Bangumi 得到的真实 BGM ID，
    // 也可能是图片识别兜底的 AniList ID（此时映射必然落空，由第 5 步接管）。
    if (bangumiId > 0) {
      try {
        nextBangumiID =
            await DanmakuApi.getDanDanBangumiIDByBgmBangumiID(bangumiId);
        if (nextBangumiID != 0) {
          final res = await DanmakuApi.getDanDanmaku(nextBangumiID, episode);
          if (res.isNotEmpty) {
            KazumiLogger()
                .i('PlayerController: fetched ${res.length} danmakus online');
            _saveDanmakuToCache(downloadController, bangumiId, pluginName,
                episode, res, nextBangumiID);
            return DanmakuLoadResult.success(
              danmakus: res,
              bangumiID: nextBangumiID,
            );
          }
          // 映射成功但该集无弹幕：对本地媒体继续尝试标题回退，
          // 因为多季番很可能被映射到了错误的季度。
          if (!hasLocalDirectory) {
            return DanmakuLoadResult.success(
              danmakus: res,
              bangumiID: nextBangumiID,
            );
          }
        }
        bgmResolved = true;
      } catch (e) {
        KazumiLogger().w(
            'PlayerController: failed to fetch danmaku online (may be offline)',
            error: e);
        if (!hasLocalDirectory) {
          return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
        }
        KazumiLogger().i(
            'PlayerController: BGM mapping failed for local media, trying title fallback');
      }
    }

    // --- 5. 标题检索兜底 ---
    if (hasLocalDirectory) {
      final titleResult = await _fetchDanmakuByTitleCandidates(
        localDanmakuDirectory,
        episode: episode,
        bangumiName: bangumiName,
        bangumiNameAliases: bangumiNameAliases,
        danmakuScope: scope,
      );
      if (titleResult != null) return titleResult;
      return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
    }
    if (!bgmResolved) {
      return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
    }
    return DanmakuLoadResult.success(
      danmakus: const [],
      bangumiID: nextBangumiID,
    );
  }

  /// 用弹弹 Play `/api/v2/match` 精确匹配本地文件，命中后写入侧车缓存。
  /// 未命中或出错返回 null，交由调用方继续后续策略。
  Future<DanmakuLoadResult?> _fetchDanmakuByFileMatch(
    String localVideoPath, {
    required String? localDanmakuDirectory,
    required int episode,
    String? danmakuScope,
  }) async {
    try {
      final matchResponse = await DanmakuApi.matchLocalFile(localVideoPath);
      final match = matchResponse.best;
      if (match == null) {
        KazumiLogger()
            .i('PlayerController: dandan file match returned no candidate');
        return null;
      }
      if (!matchResponse.hasUniqueMatch) {
        KazumiLogger().i(
            'PlayerController: dandan file match is ambiguous (${matchResponse.matches.length} candidates), using best "${match.animeTitle} - ${match.episodeTitle}"');
      }
      final res = await DanmakuApi.getDanDanmakuByEpisodeID(match.episodeId);
      if (res.isEmpty) {
        KazumiLogger().i(
            'PlayerController: dandan file match hit episode ${match.episodeId} but it has no danmaku');
        return null;
      }
      KazumiLogger().i(
          'PlayerController: fetched ${res.length} danmakus via file match "${match.animeTitle} - ${match.episodeTitle}"');
      if (localDanmakuDirectory != null && localDanmakuDirectory.isNotEmpty) {
        await downloadController.writeDirectoryDanmaku(
            localDanmakuDirectory, res, match.animeId,
            episode: episode, scope: danmakuScope ?? '');
      }
      return DanmakuLoadResult.success(
        danmakus: res,
        bangumiID: match.animeId,
        animeTitle: match.animeTitle,
        episodeTitle: match.episodeTitle,
      );
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: dandan file match failed', error: e);
      return null;
    }
  }

  /// 依次用多个候选标题检索弹弹番剧库，命中后写入侧车缓存。
  Future<DanmakuLoadResult?> _fetchDanmakuByTitleCandidates(
    String localDanmakuDirectory, {
    required int episode,
    String? bangumiName,
    List<String>? bangumiNameAliases,
    String? danmakuScope,
  }) async {
    final candidates = <String>{
      if (bangumiName != null && bangumiName.trim().isNotEmpty)
        bangumiName.trim(),
      ...?bangumiNameAliases,
    }.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    for (final candidate in candidates) {
      try {
        final titleId = await DanmakuApi.getBangumiIDByTitle(candidate);
        if (titleId == 0) continue;
        final res = await DanmakuApi.getDanDanmaku(titleId, episode);
        if (res.isEmpty) continue;
        KazumiLogger().i(
            'PlayerController: fetched ${res.length} danmakus via title "$candidate"');
        await downloadController.writeDirectoryDanmaku(
            localDanmakuDirectory, res, titleId,
            episode: episode, scope: danmakuScope ?? '');
        return DanmakuLoadResult.success(
          danmakus: res,
          bangumiID: titleId,
          animeTitle: candidate,
        );
      } catch (e) {
        KazumiLogger().w(
            'PlayerController: failed to fetch danmaku via title "$candidate"',
            error: e);
      }
    }
    return null;
  }

  void _saveDanmakuToCache(
      DownloadController downloadController,
      int bangumiId,
      String pluginName,
      int episode,
      List<DanmakuEntry> danmakus,
      int danDanID) {
    try {
      downloadController.updateCachedDanmakus(
        bangumiId,
        pluginName,
        episode,
        danmakus,
        danDanID,
      );
      KazumiLogger()
          .i('PlayerController: saved ${danmakus.length} danmakus to cache');
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: failed to save danmaku to cache', error: e);
    }
  }

  Future<DanmakuLoadResult> _fetchDanDanmakuByBgmBangumiID(
      int bgmBangumiID, int episode) async {
    KazumiLogger().i(
        'PlayerController: attempting to get danmaku [BgmBangumiID] $bgmBangumiID');
    var nextBangumiID = bangumiID;
    try {
      nextBangumiID =
          await DanmakuApi.getDanDanBangumiIDByBgmBangumiID(bgmBangumiID);
      if (nextBangumiID == 0) {
        return DanmakuLoadResult.success(
          danmakus: const [],
          bangumiID: nextBangumiID,
        );
      }
      var res = await DanmakuApi.getDanDanmaku(nextBangumiID, episode);
      return DanmakuLoadResult.success(
        danmakus: res,
        bangumiID: nextBangumiID,
      );
    } catch (e) {
      KazumiLogger().w(
          'PlayerController: failed to get danmaku [BgmBangumiID] $bgmBangumiID',
          error: e);
    }
    return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
  }

  @action
  Future<bool> getDanDanmakuByEpisodeID(
    int episodeID, {
    String? animeTitle,
    String? episodeTitle,
  }) async {
    KazumiLogger().i('PlayerController: attempting to get danmaku $episodeID');
    danmakuLoading = true;
    try {
      danDanmakus.clear();
      var res = await DanmakuApi.getDanDanmakuByEpisodeID(episodeID);
      addDanmakus(res);
      danmakuEpisodeId = episodeID;
      applyDanmakuBinding(animeTitle: animeTitle, episodeTitle: episodeTitle);
      return res.isNotEmpty;
    } catch (e) {
      KazumiLogger().w('PlayerController: failed to get danmaku', error: e);
      rethrow;
    } finally {
      danmakuLoading = false;
    }
  }

  void addDanmakus(List<DanmakuEntry> danmakus) {
    final bool danmakuDeduplicationEnable =
        GStorage.getSetting(SettingsKeys.danmakuDeduplication);

    final List<DanmakuEntry> listToAdd = danmakuDeduplicationEnable
        ? mergeDuplicateDanmakus(danmakus, timeWindowSeconds: 5)
        : danmakus;

    for (final element in listToAdd) {
      final danmakuSecond = element.time.toInt();
      (danDanmakus[danmakuSecond] ??= <DanmakuEntry>[]).add(element);
    }
  }

  void updateDanmakuSpeed(double playerSpeed) {
    final baseDuration = GStorage.getSetting(SettingsKeys.danmakuDuration);
    final followSpeed = GStorage.getSetting(SettingsKeys.danmakuFollowSpeed);

    final duration = followSpeed ? (baseDuration / playerSpeed) : baseDuration;
    canvasController
        .updateOption(canvasController.option.copyWith(duration: duration));
  }
}
