// ignore_for_file: library_private_types_in_public_api

import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/player/controller/player_models.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/request/apis/danmaku_api.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/danmaku.dart';
import 'package:kazumi/utils/danmaku_time_offset_store.dart';
import 'package:mobx/mobx.dart';

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
    this.episodeId = 0,
  });

  factory DanmakuLoadResult.success({
    required List<DanmakuEntry> danmakus,
    required int bangumiID,
    String animeTitle = '',
    String episodeTitle = '',
    int episodeId = 0,
  }) {
    return DanmakuLoadResult(
      danmakus: danmakus,
      bangumiID: bangumiID,
      status: danmakus.isEmpty
          ? DanmakuLoadStatus.empty
          : DanmakuLoadStatus.success,
      animeTitle: animeTitle,
      episodeTitle: episodeTitle,
      episodeId: episodeId,
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

  /// 弹幕来源分集的弹弹 episodeId（文件匹配 / 分集解析可得，未知为 0）。
  ///
  /// 用于把弹幕轴偏移等按分集作用域的数据精确到单集。
  final int episodeId;

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

/// 弹幕时间轴偏移的作用域读写见 [DanmakuTimeOffsetStore]。
abstract class _PlayerDanmakuController with Store {
  _PlayerDanmakuController({
    required this.isLocalPlayback,
    required this.downloadController,
  });

  final bool Function() isLocalPlayback;
  final DownloadController downloadController;

  late canvas.DanmakuController canvasController;

  final Map<int, List<DanmakuEntry>> danDanmakus = {};

  /// 弹幕池内容版本：池被清空 / 追加时递增，供只读缓存（如弹幕池
  /// 列表的排序结果）判断是否需要重建。
  int _danmakusRevision = 0;
  int get danmakusRevision => _danmakusRevision;

  void _clearDanmakus() {
    danDanmakus.clear();
    _danmakusRevision++;
  }
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
    return DanmakuTimeOffsetStore.effectiveOffset(bangumiID, danmakuEpisodeId);
  }

  /// 手动设置当前弹幕池的时间轴偏移（写入当前番剧/分集作用域）。
  ///
  /// 手动调整必须作用于运行时实际读取的「有效偏移」：若只写全局设置，
  /// 会被已存在的分集/番剧作用域偏移（如自动检测应用过的推荐值）遮蔽，
  /// 表现为「调整不生效」。未绑定番剧（bangumiID<=0）时退回全局设置。
  Future<void> setTimelineOffset(double offset) async {
    final normalized = DanmakuTimeOffsetStore.normalize(offset);
    if (bangumiID > 0) {
      await DanmakuTimeOffsetStore.setScopedOffset(
          bangumiID, danmakuEpisodeId, normalized);
    } else {
      await GStorage.putSetting<double>(
          SettingsKeys.danmakuTimeOffset, normalized);
    }
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
    _clearDanmakus();
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
    // 文件匹配 / 分集解析得到的 episodeId 一并落地，弹幕轴偏移等
    // 分集作用域数据才能精确到单集（未知保持 0，同番剧共享作用域）。
    if (result.episodeId > 0) {
      danmakuEpisodeId = result.episodeId;
    }
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
    _clearDanmakus();
    danmakuOn = false;
    danmakuLoading = false;
  }

  @action
  void finishDanmakuLoad({bool disableDanmaku = false}) {
    if (disableDanmaku) {
      _clearDanmakus();
      danmakuOn = false;
    }
    danmakuLoading = false;
  }

  /// 本地播放（下载缓存 / 本地媒体库）的弹幕获取策略链：
  ///
  /// 1. 同目录弹幕侧车文件 —— 仅当属于搜刮番剧时采用（历史错误绑定会丢弃）
  /// 2. 下载库中的弹幕缓存
  /// 3. **BGM ID → 弹弹 ID 映射** —— 本地媒体库按「搜刮的番剧」绑定弹幕池，
  ///    文件匹配 / 标题兜底不得覆盖搜刮结果；仅当搜刮番剧该集无弹幕时才兜底
  /// 4. **弹弹 Play 文件哈希匹配**（`/api/v2/match`）—— 兜底方案，命中
  ///    `episodeId`，不依赖文件名集数解析与 BGM ID 映射
  /// 5. 清洗后的标题检索 —— 最后兜底
  Future<DanmakuLoadResult> _fetchCachedDanmaku(
      int bangumiId, String pluginName, int episode,
      {String? localDanmakuDirectory,
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

    // 优先按「搜刮的番剧」绑定弹幕池：解析搜刮 BGM ID 对应的弹弹番剧 ID，
    // 用于校验侧车缓存是否仍属于搜刮番剧，以及直接拉取搜刮番剧的弹幕，
    // 避免文件匹配 / 标题兜底把弹幕池绑到其它番剧。
    // 图片识别兜底（AniList ID）与 legacy 条目的 bangumiId 非正，跳过映射。
    int? scrapedDanDanID;
    if (bangumiId > 0) {
      try {
        final mapped =
            await DanmakuApi.getDanDanBangumiIDByBgmBangumiID(bangumiId);
        nextBangumiID = mapped;
        bgmResolved = true;
        if (mapped > 0) {
          scrapedDanDanID = mapped;
        }
      } catch (e) {
        KazumiLogger().w(
            'PlayerController: failed to map BGM $bangumiId to danDan ID',
            error: e);
      }
    }

    // --- 1 & 2. 本地缓存 ---
    try {
      if (hasLocalDirectory) {
        final sidecar = await downloadController.readDirectoryDanmaku(
            localDanmakuDirectory,
            episode: episode,
            scope: scope);
        if (sidecar != null && sidecar.danmakus.isNotEmpty) {
          // 侧车缓存可能来自历史错误绑定（文件匹配 / 标题兜底写入了其它番剧
          // 的弹幕）。搜刮番剧的弹弹 ID 已知且侧车与之不符时丢弃侧车，
          // 改按搜刮番剧重新绑定；侧车 ID 为 0（旧格式）时无法校验，视为有效。
          final sidDanDan = sidecar.danDanBangumiID;
          if (scrapedDanDanID == null ||
              scrapedDanDanID <= 0 ||
              sidDanDan == 0 ||
              sidDanDan == scrapedDanDanID) {
            KazumiLogger().i(
                'PlayerController: loaded ${sidecar.danmakus.length} danmakus from local danmaku file');
            return DanmakuLoadResult.success(
              danmakus: sidecar.danmakus,
              bangumiID: sidecar.danDanBangumiID,
              episodeId: sidecar.danDanEpisodeId,
            );
          }
          KazumiLogger().w(
              'PlayerController: sidecar danmaku (danDanBangumiID=$sidDanDan) mismatches scraped anime ($scrapedDanDanID), discarding stale binding');
        }
      }

      final cachedDanmakus = await downloadController.getCachedDanmakus(
        bangumiId,
        pluginName,
        episode,
      );
      if (cachedDanmakus != null && cachedDanmakus.danmakus.isNotEmpty) {
        KazumiLogger().i(
            'PlayerController: loaded ${cachedDanmakus.danmakus.length} cached danmakus');
        return DanmakuLoadResult.success(
          danmakus: cachedDanmakus.danmakus,
          bangumiID: nextBangumiID,
          episodeId: cachedDanmakus.danDanEpisodeId,
        );
      }
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: failed to load cached danmaku', error: e);
      return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
    }

    // --- 3. 搜刮番剧映射（本地媒体优先按搜刮番剧绑定弹幕池） ---
    // 本地媒体库的 bangumiId 可能是搜刮命中 Bangumi 得到的真实 BGM ID，
    // 也可能是图片识别兜底的 AniList ID（此时映射必然落空，由后续兜底接管）。
    if (scrapedDanDanID != null && scrapedDanDanID > 0) {
      try {
        final res = await DanmakuApi.getDanDanmaku(scrapedDanDanID, episode);
        if (res.danmakus.isNotEmpty) {
          KazumiLogger().i(
              'PlayerController: fetched ${res.danmakus.length} danmakus for scraped anime');
          _saveDanmakuToCache(downloadController, bangumiId, pluginName,
              episode, res.danmakus, scrapedDanDanID);
          return DanmakuLoadResult.success(
            danmakus: res.danmakus,
            bangumiID: scrapedDanDanID,
            episodeId: res.episodeId,
          );
        }
        // 映射成功但该集无弹幕：继续尝试文件匹配 / 标题回退，
        // 因为多季番很可能被映射到了错误的季度。
        if (!hasLocalDirectory) {
          return DanmakuLoadResult.success(
            danmakus: res.danmakus,
            bangumiID: scrapedDanDanID,
            episodeId: res.episodeId,
          );
        }
      } catch (e) {
        KazumiLogger().w(
            'PlayerController: failed to fetch danmaku for scraped anime (may be offline)',
            error: e);
        if (!hasLocalDirectory) {
          return DanmakuLoadResult.failed(bangumiID: scrapedDanDanID);
        }
      }
    }

    // --- 4. 文件哈希精确匹配（搜刮番剧无弹幕 / 无法映射时的兜底） ---
    if (hasLocalFile) {
      final matched = await _fetchDanmakuByFileMatch(
        localVideoPath,
        localDanmakuDirectory: localDanmakuDirectory,
        episode: episode,
        danmakuScope: scope,
      );
      if (matched != null) return matched;
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
            episode: episode,
            scope: danmakuScope ?? '',
            danDanEpisodeId: match.episodeId);
      }
      return DanmakuLoadResult.success(
        danmakus: res,
        bangumiID: match.animeId,
        animeTitle: match.animeTitle,
        episodeTitle: match.episodeTitle,
        episodeId: match.episodeId,
      );
    } catch (e) {
      KazumiLogger().w('PlayerController: dandan file match failed', error: e);
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
        if (res.danmakus.isEmpty) continue;
        KazumiLogger().i(
            'PlayerController: fetched ${res.danmakus.length} danmakus via title "$candidate"');
        await downloadController.writeDirectoryDanmaku(
            localDanmakuDirectory, res.danmakus, titleId,
            episode: episode,
            scope: danmakuScope ?? '',
            danDanEpisodeId: res.episodeId);
        return DanmakuLoadResult.success(
          danmakus: res.danmakus,
          bangumiID: titleId,
          animeTitle: candidate,
          episodeId: res.episodeId,
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
        danmakus: res.danmakus,
        bangumiID: nextBangumiID,
        episodeId: res.episodeId,
      );
    } catch (e) {
      KazumiLogger().w(
          'PlayerController: failed to get danmaku [BgmBangumiID] $bgmBangumiID',
          error: e);
    }
    return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
  }

  /// 手动绑定 / 切换弹幕库：按分集 ID 拉取弹幕并整体替换弹幕池。
  ///
  /// [bangumiId] 为弹弹 Play 番剧 ID。本地播放自动加载失败后（bangumiID
  /// 为 0）手动检索绑定时必须一并写回：否则弹幕面板会误判「未绑定弹幕」、
  /// 弹幕轴偏移作用域落到 `0:episodeId` 与其它本地文件互相污染。
  @action
  Future<bool> getDanDanmakuByEpisodeID(
    int episodeID, {
    String? animeTitle,
    String? episodeTitle,
    int? bangumiId,
  }) async {
    KazumiLogger().i('PlayerController: attempting to get danmaku $episodeID');
    danmakuLoading = true;
    try {
      _clearDanmakus();
      var res = await DanmakuApi.getDanDanmakuByEpisodeID(episodeID);
      if (bangumiId != null && bangumiId > 0) {
        bangumiID = bangumiId;
      }
      addDanmakus(res);
      danmakuEpisodeId = episodeID;
      // 弹幕池整体替换：清掉画布上旧池残留弹幕并递增发射代次，
      // 播放器发射追踪随即复位、从当前秒重新发射新池弹幕；
      // 否则绑定瞬间当前秒的弹幕会被「已发射过」误判跳过。
      clearAndInvalidateScheduledDanmakus();
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
    if (listToAdd.isNotEmpty) {
      _danmakusRevision++;
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
