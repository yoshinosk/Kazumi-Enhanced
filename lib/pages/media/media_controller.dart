import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/media/local_media_scanner.dart';
import 'package:kazumi/services/media/media_folder_watcher.dart';
import 'package:kazumi/services/media/media_scraper.dart';
import 'package:kazumi/services/media/video_frame_extractor.dart';
import 'package:kazumi/services/platform/android_storage_access.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/local_episode_parser.dart';
import 'package:mobx/mobx.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'media_controller.g.dart';

class MediaController = _MediaController with _$MediaController;

/// 按番剧分组的结果。
class AnimeGroup {
  const AnimeGroup({this.info, required this.folders});

  /// 番剧元数据，为 null 表示未匹配的文件夹。
  final MediaScrapeInfo? info;
  final List<LocalMediaFolder> folders;

  int get fileCount => folders.fold<int>(0, (sum, f) => sum + f.count);
}

/// 网格视图的一个卡片单元。
///
/// 与 [AnimeGroup] 的区别：已匹配番剧仍按番剧聚合成一张卡片，
/// 但未匹配的文件夹会**逐个**拆成独立卡片 —— 网格是海报墙，
/// 把上百个未匹配文件夹塞进同一张「未匹配」卡片毫无意义。
class MediaGridItem {
  const MediaGridItem({
    this.info,
    required this.title,
    required this.folders,
  });

  /// 番剧元数据，为 null 表示未匹配。
  final MediaScrapeInfo? info;

  /// 卡片标题：已匹配取番剧名，未匹配取文件夹名。
  final String title;

  final List<LocalMediaFolder> folders;

  bool get isMatched => info != null;

  String get coverUrl => info?.coverUrl ?? '';

  String get airDate => info?.airDate ?? '';

  int get fileCount => folders.fold<int>(0, (sum, f) => sum + f.count);

  /// 卡片下所有视频文件（按文件夹顺序展开）。
  List<LocalMediaFile> get files => [
        for (final folder in folders) ...folder.files,
      ];
}

/// 媒体库中一个文件的续播点：来自本地播放历史（adapterName='local'，
/// episodePageUrl 精确匹配文件路径）。
class MediaResumePoint {
  const MediaResumePoint({
    required this.folder,
    required this.file,
    required this.position,
    required this.updatedAt,
  });

  /// 文件所在的媒体库文件夹（用于取选集列表）。
  final LocalMediaFolder folder;

  /// 上次播放的文件。
  final LocalMediaFile file;

  /// 上次播放位置（已看完时归零）。
  final Duration position;

  /// 最近一次进度更新时间。
  final DateTime updatedAt;

  /// 从文件名解析的集数（失败为 0）。
  int get episode => parseLocalEpisodeNumber(file.name);

  /// 内容相等判定：mapEquals 依赖它判断续播点缓存是否需要写回，
  /// 缺失时内容相同的新实例恒不相等，observable 每帧重建触发观察者。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaResumePoint &&
          localMediaPathKey(other.folder.path) ==
              localMediaPathKey(folder.path) &&
          localMediaPathKey(other.file.path) == localMediaPathKey(file.path) &&
          other.position == position &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        localMediaPathKey(folder.path),
        localMediaPathKey(file.path),
        position,
        updatedAt,
      );

  /// 播放位置的可读展示（如 `12:34` / `1:02:03`）。
  String get positionLabel {
    final total = position.inSeconds;
    if (total <= 0) return '';
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

/// 从 `YYYY-MM-DD` / `YYYY-MM` / `YYYY` 形式的首播日期解析出可比较的整数键。
///
/// 解析失败（空串或非法格式）返回 null，调用方需把这类条目排到末尾 ——
/// 未知日期既不该占据「最新」也不该占据「最早」的位置。
int? _airDateSortKey(String airDate) {
  if (airDate.isEmpty) return null;
  final match =
      RegExp(r'^(\d{4})(?:-(\d{1,2}))?(?:-(\d{1,2}))?').firstMatch(airDate);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  if (year == null) return null;
  final month = int.tryParse(match.group(2) ?? '') ?? 0;
  final day = int.tryParse(match.group(3) ?? '') ?? 0;
  return year * 10000 + month * 100 + day;
}

abstract class _MediaController with Store {
  _MediaController()
      : _scanner = LocalMediaScanner(),
        _scraper = MediaScraper();

  final LocalMediaScanner _scanner;
  final MediaScraper _scraper;
  final HistoryRepository _historyRepository = HistoryRepository();

  /// Windows 目录监听（Android 走页面定时轮询），变化后自动重扫。
  late final MediaFolderWatcher _folderWatcher =
      MediaFolderWatcher(onChanged: () => unawaited(scan()));

  /// 历史记录变化订阅（用于刷新续播点）。
  StreamSubscription<void>? _historyChangesSub;

  /// 未匹配文件夹的视频首帧缩略图缓存（文件夹路径 → JPEG 路径）。
  @observable
  ObservableMap<String, String> thumbnails = ObservableMap();

  @observable
  ObservableList<String> folders = ObservableList();

  @observable
  ObservableList<LocalMediaFolder> library = ObservableList();

  @observable
  bool isScanning = false;

  @observable
  ObservableMap<String, MediaScrapeInfo> scrapeResults = ObservableMap();

  /// 单个文件的搜刮结果（文件路径 → 番剧信息），优先级高于文件夹级结果。
  ///
  /// 混合目录中单个文件（如 SP / 特典）与文件夹匹配的番剧不同时，
  /// 用户可只对该文件重新匹配，播放时以文件级结果为准。
  @observable
  ObservableMap<String, MediaScrapeInfo> fileScrapeResults = ObservableMap();

  @observable
  bool isScraping = false;

  @observable
  int scrapeDone = 0;

  @observable
  int scrapeTotal = 0;

  /// 已匹配的文件夹数。
  @observable
  int scrapeMatched = 0;

  /// 匹配失败（未找到 / 出错）的文件夹数。
  @observable
  int scrapeFailed = 0;

  /// 当前正在搜刮的文件夹名。
  @observable
  String scrapeCurrentName = '';

  /// 当前正在使用的搜索关键词。
  @observable
  String scrapeKeyword = '';

  /// 续播点缓存：文件夹路径键 → 该文件夹内最新的续播点。
  /// 随本地播放历史变化自动刷新，驱动卡片「续播」角标。
  @observable
  ObservableMap<String, MediaResumePoint> resumePoints = ObservableMap();

  /// 是否请求取消当前搜刮。
  bool _scrapeCancelRequested = false;

  bool get groupByFolder =>
      GStorage.getSetting(SettingsKeys.localMediaGroupByFolder);

  String get viewMode => GStorage.getSetting(SettingsKeys.localMediaViewMode);

  bool get isAnimeMode => viewMode == 'anime';

  bool get isGridMode => viewMode == 'grid';

  /// 排序依据：`date` / `name` / `count`，仅对番剧视图与网格视图生效。
  String get sortMode => GStorage.getSetting(SettingsKeys.localMediaSortMode);

  /// 是否降序（日期越新、文件越多越靠前）。
  bool get sortDescending =>
      GStorage.getSetting(SettingsKeys.localMediaSortDescending);

  @action
  Future<void> setSortMode(String mode) async {
    await GStorage.putSetting(SettingsKeys.localMediaSortMode, mode);
    _refreshLibraryView();
  }

  @action
  Future<void> setSortDescending(bool value) async {
    await GStorage.putSetting(SettingsKeys.localMediaSortDescending, value);
    _refreshLibraryView();
  }

  /// 触发依赖 [library] 的 Observer 重建。
  ///
  /// 排序/视图模式存在设置盒子里而非 observable，改动后必须手动打一下
  /// observable 引用，否则界面不会刷新。
  void _refreshLibraryView() {
    library = ObservableList.of(library.toList());
  }

  /// 批量搜刮时是否只处理尚未匹配的文件夹。
  bool get scrapeOnlyUnmatched =>
      GStorage.getSetting(SettingsKeys.localMediaScrapeOnlyUnmatched);

  Future<void> setScrapeOnlyUnmatched(bool value) =>
      GStorage.putSetting(SettingsKeys.localMediaScrapeOnlyUnmatched, value);

  /// 尚未匹配到番剧元数据的文件夹。
  List<LocalMediaFolder> get unmatchedFolders => [
        for (final folder in library)
          if (scrapeResults[folder.path] == null) folder,
      ];

  /// 尚未匹配的文件夹数量。
  int get unmatchedCount => unmatchedFolders.length;

  /// 已匹配的文件夹数量。
  int get matchedCount => library.length - unmatchedCount;

  Future<void> init() async {
    folders = ObservableList.of(LocalMediaFolderStore.load());
    scrapeResults = ObservableMap.of(MediaScrapeStore.load());
    fileScrapeResults = ObservableMap.of(MediaScrapeStore.loadFileResults());
    _historyChangesSub ??= _historyRepository.changes.listen((_) {
      _refreshResumePoints();
    });
    _refreshResumePoints();
    if (folders.isNotEmpty) {
      // Android 需要读取共享存储视频的运行时权限；用户已配置过文件夹，
      // 启动时静默检查并补请求（一次系统弹窗，授权后正常扫描）。
      await _ensureAndroidReadAccess();
      // 不阻塞启动流程：扫描在后台进行，媒体库页通过 isScanning 展示进度。
      unawaited(scan());
    }
    _syncFolderWatcher();
  }

  /// 按设置同步 Windows 目录监听（文件夹列表变化 / 设置开关变化时调用）。
  void _syncFolderWatcher() {
    final enabled = GStorage.getSetting(SettingsKeys.localMediaWatchFolder);
    if (enabled && folders.isNotEmpty) {
      _folderWatcher.start(folders.toList());
    } else {
      _folderWatcher.stop();
    }
  }

  /// 切换 Windows 目录监听开关。
  @action
  Future<void> setWatchFolder(bool value) async {
    await GStorage.putSetting(SettingsKeys.localMediaWatchFolder, value);
    _syncFolderWatcher();
  }

  /// 切换未匹配卡片缩略图开关（开启时立即为未匹配文件夹补生成）。
  @action
  Future<void> setThumbnailsEnabled(bool value) async {
    await GStorage.putSetting(SettingsKeys.localMediaThumbnails, value);
    if (value) {
      unawaited(_generateMissingThumbnails());
    } else {
      thumbnails.clear();
    }
  }

  /// 从本地播放历史重建续播点缓存（按 episodePageUrl 精确匹配文件路径，
  /// 同一文件夹只保留最近更新的那一条）。
  @action
  void _refreshResumePoints() {
    final byFile = <String, ({LocalMediaFolder folder, LocalMediaFile file})>{};
    for (final folder in library) {
      for (final file in folder.files) {
        byFile[localMediaPathKey(file.path)] = (folder: folder, file: file);
      }
    }
    final latest = <String, MediaResumePoint>{};
    try {
      for (final history in _historyRepository.getAllHistories()) {
        if (!isLocalMediaHistory(history)) continue;
        if (history.episodePageUrl.isEmpty) continue;
        final target = byFile[localMediaPathKey(history.episodePageUrl)];
        if (target == null) continue;
        final progress = history.progresses[history.lastWatchEpisode];
        final updatedAt = DateTime.fromMillisecondsSinceEpoch(
          progress?.effectiveUpdatedAtMs(history.lastWatchTime) ?? 0,
        );
        final folderKey = localMediaPathKey(target.folder.path);
        final existing = latest[folderKey];
        if (existing == null || updatedAt.isAfter(existing.updatedAt)) {
          latest[folderKey] = MediaResumePoint(
            folder: target.folder,
            file: target.file,
            position: progress?.progress ?? Duration.zero,
            updatedAt: updatedAt,
          );
        }
      }
    } catch (e) {
      KazumiLogger()
          .w('MediaController: refresh resume points failed', error: e);
    }
    if (!mapEquals(latest, Map.from(resumePoints))) {
      resumePoints = ObservableMap.of(latest);
    }
  }

  /// 修复以占位番剧落库的本地播放历史条目。
  ///
  /// 旧版本在文件尚未匹配时直接播放，会以标题哈希的占位 BangumiItem
  /// 记录历史（id <= 0）；文件夹随后搜刮匹配到真实番剧后，旧条目不会
  /// 自动更新，导致历史页显示占位标题、无法联动 Bangumi 进度。此处把
  /// 这类条目按 episodePageUrl 找到所在文件夹，迁移到真实番剧的 key 下。
  /// 若匹配后用户已重新播放过（真实条目已存在且更新），则跳过迁移、
  /// 直接丢弃占位条目，避免陈旧占位进度覆盖新历史。每次扫描后运行，
  /// 占位条目迁移完毕即空跑退出。
  Future<void> _repairPlaceholderHistories() async {
    try {
      final placeholders = _historyRepository
          .getAllHistories()
          .where(isLocalMediaHistory)
          .where((h) => h.bangumiItem.id <= 0 && h.episodePageUrl.isNotEmpty)
          .toList();
      if (placeholders.isEmpty) return;
      final byFile = <String, LocalMediaFolder>{};
      for (final folder in library) {
        for (final file in folder.files) {
          byFile[localMediaPathKey(file.path)] = folder;
        }
      }
      var repaired = false;
      for (final history in placeholders) {
        final folder = byFile[localMediaPathKey(history.episodePageUrl)];
        if (folder == null) continue;
        final info = scrapeResults[folder.path];
        if (info == null || info.bangumiId == null) continue;
        final realBangumiItem = info.toBangumiItem();
        // 文件夹匹配后用户已重新播放过该文件：真实条目存在且更新，
        // 迁移会把陈旧占位进度覆盖到真实条目上（updateHistory 无条件
        // 写 lastWatchTime=now 并覆写进度），此时直接丢弃占位条目。
        final real = _historyRepository.getHistory(
          kLocalMediaAdapterName,
          realBangumiItem,
          entryKind: HistoryEntryKind.offline,
        );
        if (real != null &&
            !real.lastWatchTime.isBefore(history.lastWatchTime)) {
          await _historyRepository.deleteHistory(history);
          continue;
        }
        final byEpisode = {
          for (final progress in history.progresses.values)
            progress.episode: progress,
        };
        final lastEpisode = history.lastWatchEpisode;
        final lastProgress = byEpisode.remove(lastEpisode);
        // 最后写入上次观看的分集，保证迁移后 watch-state 与占位条目一致；
        // 其余分集进度一并迁移，避免旧占位条目中的其他进度丢失。
        final ordered = [
          ...byEpisode.values,
          if (lastProgress != null) lastProgress,
        ];
        for (var i = 0; i < ordered.length; i++) {
          final progress = ordered[i];
          final isLast = i == ordered.length - 1;
          await _historyRepository.updateHistory(
            identity: PlaybackHistoryIdentity.offline(
              bangumiItem: realBangumiItem,
              pluginName: kLocalMediaAdapterName,
              episodeNumber: progress.episode,
              episodeTitle: isLast ? history.lastWatchEpisodeName : '',
              road: progress.road,
              episodePageUrl: history.episodePageUrl,
            ),
            progress: progress.progress,
          );
        }
        await _historyRepository.deleteHistory(history);
        repaired = true;
        KazumiLogger().i(
            'MediaController: repaired placeholder history of ${history.episodePageUrl}');
      }
      if (repaired) {
        _refreshResumePoints();
      }
    } catch (e) {
      KazumiLogger()
          .w('MediaController: repair placeholder histories failed', error: e);
    }
  }

  /// 单个文件夹的续播点（无则 null）。
  MediaResumePoint? resumePointFor(LocalMediaFolder folder) =>
      resumePoints[localMediaPathKey(folder.path)];

  /// 一组文件夹（同一番剧多季 / 多目录）中最近更新的续播点。
  MediaResumePoint? resumePointForFolders(List<LocalMediaFolder> folders) {
    MediaResumePoint? best;
    for (final folder in folders) {
      final r = resumePoints[localMediaPathKey(folder.path)];
      if (r != null && (best == null || r.updatedAt.isAfter(best.updatedAt))) {
        best = r;
      }
    }
    return best;
  }

  /// Android：确保已授予媒体视频读取权限（无权限时请求一次）。
  Future<void> _ensureAndroidReadAccess() async {
    if (!Platform.isAndroid) return;
    if (await AndroidStorageAccess.hasMediaReadPermission()) return;
    await AndroidStorageAccess.requestMediaReadPermission();
  }

  @action
  Future<void> addFolder(String path) async {
    path = path.trim();
    if (path.isEmpty) return;
    if (folders.any((folder) => localMediaPathsEqual(folder, path))) {
      KazumiDialog.showToast(message: '该文件夹已添加');
      return;
    }
    if (Platform.isAndroid) {
      if (!await AndroidStorageAccess.hasMediaReadPermission()) {
        final granted = await AndroidStorageAccess.requestMediaReadPermission();
        if (!granted) {
          KazumiDialog.showToast(message: '未授予存储读取权限，无法扫描本地视频，请在系统设置中允许');
          return;
        }
      }
      if (!await AndroidStorageAccess.hasAllFilesAccess()) {
        // 仅读取权限下共享存储目录只暴露视频文件；提示用户可开启
        // 全文件访问以支持遍历任意目录（如包含外挂字幕等非视频文件）。
        KazumiDialog.showToast(
            message: '提示：可开启「所有文件访问」权限以获得完整目录遍历能力',
            duration: const Duration(seconds: 3));
      }
    }
    folders.add(path);
    await LocalMediaFolderStore.save(folders.toList());
    _syncFolderWatcher();
    await scan();
  }

  @action
  Future<void> removeFolder(String path) async {
    folders.removeWhere((f) => f == path);
    await LocalMediaFolderStore.save(folders.toList());
    // 清理该目录（含其子目录）遗留的搜刮结果，避免设置膨胀与重新添加时
    // 复活旧匹配。
    final removedKeys = scrapeResults.keys
        .where((key) => isLocalMediaPathWithin(path, key))
        .toList();
    if (removedKeys.isNotEmpty) {
      for (final k in removedKeys) {
        scrapeResults.remove(k);
      }
      await MediaScrapeStore.save(scrapeResults);
    }
    final removedFileKeys = fileScrapeResults.keys
        .where((key) => isLocalMediaPathWithin(path, key))
        .toList();
    if (removedFileKeys.isNotEmpty) {
      for (final k in removedFileKeys) {
        fileScrapeResults.remove(k);
      }
      await MediaScrapeStore.saveFileResults(fileScrapeResults);
    }
    _syncFolderWatcher();
    await scan();
  }

  /// 扫描代次：每次扫描递增；结果仅当仍是最新一代时才写入，
  /// 防止「先开始的慢扫描」用陈旧快照覆盖「后开始的新扫描」。
  int _scanGeneration = 0;

  @action
  Future<void> scan() async {
    final generation = ++_scanGeneration;
    if (folders.isEmpty) {
      library.clear();
      isScanning = false;
      return;
    }
    isScanning = true;
    try {
      final result = await _scanner.scanAllWithGroupings(
        folders.toList(),
        groupByFolder: groupByFolder,
      );
      // 扫描期间又有新的扫描（或文件夹变更）发起：丢弃本次结果，
      // 由最新一轮接管；同时避免把 isScanning 提前置 false。
      if (generation != _scanGeneration) return;
      // 分组键随文件集合变化而失效：先按新旧分组快照迁移搜刮结果，
      // 再提交新的文件夹列表，保证本次扫描起各链路使用新键仍能命中。
      await _migrateScrapeResultsForRegrouping(result.groupings);
      library
        ..clear()
        ..addAll(result.folders);
      _refreshResumePoints();
      unawaited(_repairPlaceholderHistories());
      if (isGridMode) {
        unawaited(_generateMissingThumbnails());
      }
    } catch (e) {
      KazumiLogger().w('MediaController: scan failed', error: e);
      KazumiDialog.showToast(message: '扫描失败：$e');
    } finally {
      if (generation == _scanGeneration) {
        isScanning = false;
      }
    }
  }

  /// 标题分组键迁移：媒体库的「假路径」分组键（`<目录>/<清洗后标题>`）
  /// 由目录内**当前**文件集合推导——单标题目录用真实目录作键，出现第二
  /// 个标题后同一批文件改挂到标题分组键（反向合并同理）。键变化后按路径
  /// 持久化的搜刮结果会永久失效（续播 / 缩略图按文件路径重建可自愈，
  /// 搜刮与依赖它的历史迁移不会）。
  ///
  /// 每次扫描后把上次扫描的分组快照与新快照按归一化标题对齐，把旧键下
  /// 的搜刮结果迁移到新键，并持久化新快照供下次迁移使用。
  Future<void> _migrateScrapeResultsForRegrouping(
      Map<String, Map<String, String>> newGroupings) async {
    final oldGroupings = _decodeGroupingSnapshot(
        GStorage.getSetting(SettingsKeys.localMediaLastGrouping));
    if (oldGroupings.isNotEmpty) {
      if (scrapeResults.isEmpty) {
        scrapeResults = ObservableMap.of(MediaScrapeStore.load());
      }
      var changed = false;
      for (final entry in newGroupings.entries) {
        final oldByTitle = oldGroupings[entry.key];
        if (oldByTitle == null) continue;
        for (final title in entry.value.keys) {
          final newPath = entry.value[title]!;
          final oldPath = oldByTitle[title];
          if (oldPath == null || localMediaPathsEqual(oldPath, newPath)) {
            continue;
          }
          final info = scrapeResults[oldPath];
          if (info == null) continue;
          if (!scrapeResults.containsKey(newPath)) {
            scrapeResults[newPath] = info;
          }
          scrapeResults.remove(oldPath);
          changed = true;
          KazumiLogger().i(
              'MediaController: migrated scrape result $oldPath -> $newPath '
              '(title grouping changed)');
        }
      }
      if (changed) {
        await MediaScrapeStore.save(
            Map<String, MediaScrapeInfo>.from(scrapeResults));
      }
    }
    await GStorage.putSetting(
      SettingsKeys.localMediaLastGrouping,
      _encodeGroupingSnapshot(newGroupings),
    );
  }

  static Map<String, Map<String, String>> _decodeGroupingSnapshot(String raw) {
    if (raw.isEmpty) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (dir, byTitle) => MapEntry(
          dir,
          (byTitle as Map<String, dynamic>)
              .map((title, path) => MapEntry(title, path as String)),
        ),
      );
    } catch (_) {
      return const {};
    }
  }

  static String _encodeGroupingSnapshot(
          Map<String, Map<String, String>> groupings) =>
      jsonEncode(groupings);

  @action
  Future<void> setGroupByFolder(bool value) async {
    await GStorage.putSetting(SettingsKeys.localMediaGroupByFolder, value);
    await scan();
  }

  @action
  Future<void> setViewMode(String mode) async {
    await GStorage.putSetting(SettingsKeys.localMediaViewMode, mode);
    _refreshLibraryView();
  }

  // ============ 搜刮 ============

  /// 请求取消当前正在进行的搜刮。
  @action
  void cancelScrape() {
    _scrapeCancelRequested = true;
  }

  /// 搜刮文件夹的番剧元数据。
  ///
  /// [onlyUnmatched] 为 true 时跳过已有搜刮结果的文件夹，只处理未匹配的番剧；
  /// 传 null 则沿用设置项 `localMediaScrapeOnlyUnmatched`。
  @action
  Future<void> scrapeAll({bool? onlyUnmatched}) async {
    if (library.isEmpty) {
      KazumiDialog.showToast(message: '没有可搜刮的文件夹');
      return;
    }
    final skipMatched = onlyUnmatched ?? scrapeOnlyUnmatched;
    final targets = skipMatched ? unmatchedFolders : library.toList();
    if (targets.isEmpty) {
      KazumiDialog.showToast(message: '所有文件夹都已匹配，无需搜刮');
      return;
    }
    isScraping = true;
    scrapeDone = 0;
    scrapeTotal = targets.length;
    scrapeMatched = 0;
    scrapeFailed = 0;
    scrapeCurrentName = '';
    scrapeKeyword = '';
    _scrapeCancelRequested = false;
    try {
      final results = await _scraper.scrapeAll(
        targets,
        isCancelled: () => _scrapeCancelRequested,
        onProgress: (progress) {
          scrapeDone = progress.done;
          scrapeTotal = progress.total;
          scrapeMatched = progress.matched;
          scrapeFailed = progress.failed;
          scrapeCurrentName = progress.currentFolder ?? '';
          scrapeKeyword = progress.currentKeyword ?? '';
        },
      );
      final matched = <String, MediaScrapeInfo>{
        for (final r in results)
          if (r.status == ScrapeStatus.matched && r.info != null)
            r.folderPath: r.info!,
      };
      // 未匹配/出错的结果移除旧数据，避免残留过期匹配。
      // 注意：只清理本轮真正搜刮过的路径，跳过的已匹配结果必须原样保留。
      final unmatchedPaths = <String>{
        for (final r in results)
          if (r.status != ScrapeStatus.matched) r.folderPath,
      };
      scrapeResults
        ..removeWhere((path, _) => unmatchedPaths.contains(path))
        ..addAll(matched);
      await MediaScrapeStore.save(
          Map<String, MediaScrapeInfo>.from(scrapeResults));
      final scopeLabel = skipMatched ? '未匹配文件夹' : '文件夹';
      final toastMessage = _scrapeCancelRequested
          ? '已取消搜刮，匹配 ${matched.length}/${targets.length} 个$scopeLabel'
          : '搜刮完成，匹配 ${matched.length}/${targets.length} 个$scopeLabel'
              '，未找到 $scrapeFailed 个';
      KazumiDialog.showToast(message: toastMessage);
    } catch (e) {
      KazumiLogger().w('MediaController: scrapeAll failed', error: e);
      KazumiDialog.showToast(message: '搜刮失败：$e');
    } finally {
      isScraping = false;
      _scrapeCancelRequested = false;
    }
  }

  /// 手动搜刮单个文件夹（用指定关键词搜索并返回候选列表）。
  Future<List<BangumiItem>> searchBangumi(String keyword) async {
    if (keyword.trim().isEmpty) return const [];
    try {
      final page = await BangumiApi.bangumiSearch(keyword, limit: 20);
      return page?.items ?? const [];
    } catch (e) {
      KazumiLogger().w('MediaController: searchBangumi failed', error: e);
      return const [];
    }
  }

  /// 为文件夹设置手动匹配的番剧。
  @action
  Future<void> setFolderMatch(
    String folderPath,
    BangumiItem item,
  ) async {
    final info = MediaScrapeInfo.fromBangumiItem(item);
    scrapeResults[folderPath] = info;
    await MediaScrapeStore.save(
        Map<String, MediaScrapeInfo>.from(scrapeResults));
  }

  /// 为单个文件设置手动匹配的番剧（覆盖该文件所在文件夹的匹配结果）。
  @action
  Future<void> setFileMatch(
    LocalMediaFile file,
    BangumiItem item,
  ) async {
    if (fileScrapeResults.isEmpty) {
      // 内存映射尚未加载（媒体库未初始化时）：先读取持久化结果再合并，
      // 避免用空映射覆盖已保存的搜刮数据。
      fileScrapeResults = ObservableMap.of(MediaScrapeStore.loadFileResults());
    }
    final info = MediaScrapeInfo.fromBangumiItem(item);
    fileScrapeResults[file.path] = info;
    await MediaScrapeStore.saveFileResults(
        Map<String, MediaScrapeInfo>.from(fileScrapeResults));
  }

  /// 清除单个文件的搜刮结果，恢复使用文件夹级结果。
  @action
  Future<void> removeFileScrapeResult(String filePath) async {
    fileScrapeResults.remove(filePath);
    await MediaScrapeStore.saveFileResults(
        Map<String, MediaScrapeInfo>.from(fileScrapeResults));
  }

  /// 获取文件的搜刮结果：优先文件级，其次文件夹级。
  ///
  /// [folder] 为文件所在媒体库文件夹（逻辑分组）。文件夹级结果按
  /// 文件夹路径索引，传文件全路径永远查不到，会导致播放历史记录下
  /// 占位番剧而非真实匹配结果。
  MediaScrapeInfo? getFileScrapeInfo(
          LocalMediaFile file, LocalMediaFolder folder) =>
      fileScrapeResults[file.path] ?? scrapeResults[folder.path];

  /// 直接为文件夹写入搜刮结果（如磁力任务完成后自动同步），
  /// 会更新内存 observable 并持久化。
  @action
  Future<void> applyScrapeInfo(String folderPath, MediaScrapeInfo info) async {
    if (scrapeResults.isEmpty) {
      // 内存映射尚未加载（媒体库未初始化时）：先读取持久化结果再合并，
      // 避免用空映射覆盖已保存的搜刮数据。
      scrapeResults = ObservableMap.of(MediaScrapeStore.load());
    }
    scrapeResults[folderPath] = info;
    await MediaScrapeStore.save(
        Map<String, MediaScrapeInfo>.from(scrapeResults));
  }

  /// 清除文件夹的搜刮结果。
  @action
  Future<void> removeScrapeResult(String folderPath) async {
    scrapeResults.remove(folderPath);
    await MediaScrapeStore.save(
        Map<String, MediaScrapeInfo>.from(scrapeResults));
  }

  /// 获取文件夹的搜刮结果。
  MediaScrapeInfo? getScrapeInfo(String folderPath) =>
      scrapeResults[folderPath];

  /// 缺失集数检测：对比本地已解析集数与 Bangumi 正片（type=0）集数。
  ///
  /// 返回升序的缺失集数列表；本地集数解析为空、未匹配番剧或网络失败时
  /// 返回空列表。缺失列表以「本地最大集数 + 12」为上界，避免把尚未
  /// 播出的未来集数全部报为缺集。
  Future<List<int>> detectMissingEpisodes(String folderPath) async {
    final info = scrapeResults[folderPath];
    final bangumiId = info?.bangumiId;
    if (bangumiId == null) return const [];
    final folder = library.where((f) => f.path == folderPath).firstOrNull;
    if (folder == null) return const [];
    final have = <int>{};
    for (final file in folder.files) {
      final ep = parseLocalEpisodeNumber(file.name);
      if (ep > 0) have.add(ep);
    }
    if (have.isEmpty) return const [];
    final maxHave = have.reduce((a, b) => a > b ? a : b);
    try {
      final episodes = await BangumiApi.getBangumiEpisodesByID(bangumiId);
      final missing = <int>{};
      for (final e in episodes) {
        if (e.type != 0) continue;
        final n = e.episode.toInt();
        if (n <= 0 || have.contains(n)) continue;
        // 只报本地已有最大集数附近的一段，其余视为未播出。
        if (n > maxHave + 12) continue;
        missing.add(n);
      }
      return missing.toList()..sort();
    } catch (e) {
      KazumiLogger()
          .w('MediaController: detect missing episodes failed', error: e);
      return const [];
    }
  }

  /// 按番剧分组返回，排序遵循 [sortMode] / [sortDescending]，未匹配组恒定排在末尾。
  List<AnimeGroup> get animeGroups {
    final matched = <String, AnimeGroup>{};
    final unmatched = <LocalMediaFolder>[];
    for (final folder in library) {
      final info = scrapeResults[folder.path];
      if (info != null) {
        final existing = matched[info.identityKey];
        if (existing != null) {
          matched[info.identityKey] = AnimeGroup(
            info: info,
            folders: [...existing.folders, folder],
          );
        } else {
          matched[info.identityKey] = AnimeGroup(info: info, folders: [folder]);
        }
      } else {
        unmatched.add(folder);
      }
    }
    final groups = matched.values.toList()
      ..sort((a, b) => _compareEntries(
            aDate: a.info!.airDate,
            bDate: b.info!.airDate,
            aName: a.info!.displayName,
            bName: b.info!.displayName,
            aCount: a.fileCount,
            bCount: b.fileCount,
          ));
    if (unmatched.isNotEmpty) {
      groups.add(AnimeGroup(info: null, folders: unmatched));
    }
    // 同番剧多季目录按季数排序（第 2 季排在「无季数标记」的第 1 季之后）。
    for (final group in groups) {
      group.folders.sort(_compareFoldersBySeason);
    }
    return groups;
  }

  /// 网格视图数据源：已匹配番剧聚合成一张卡片，未匹配文件夹各自成卡。
  ///
  /// 默认按番剧首播日期降序（最新番在前），无日期的条目恒定沉底。
  List<MediaGridItem> get gridItems {
    final matched = <String, MediaGridItem>{};
    final unmatched = <MediaGridItem>[];
    for (final folder in library) {
      final info = scrapeResults[folder.path];
      if (info == null) {
        unmatched.add(MediaGridItem(
          title: folder.name.isNotEmpty ? folder.name : folder.path,
          folders: [folder],
        ));
        continue;
      }
      final existing = matched[info.identityKey];
      matched[info.identityKey] = MediaGridItem(
        info: info,
        title: info.displayName,
        folders: [...?existing?.folders, folder],
      );
    }
    final items = matched.values.toList()
      ..sort((a, b) => _compareEntries(
            aDate: a.airDate,
            bDate: b.airDate,
            aName: a.title,
            bName: b.title,
            aCount: a.fileCount,
            bCount: b.fileCount,
          ));
    // 同番剧多季目录按季数排序。
    for (final item in items) {
      item.folders.sort(_compareFoldersBySeason);
    }
    // 未匹配条目没有元数据可排，统一按名称升序垫在最后。
    unmatched
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return [...items, ...unmatched];
  }

  /// 番剧视图 / 网格视图共用的比较器。
  int _compareEntries({
    required String aDate,
    required String bDate,
    required String aName,
    required String bName,
    required int aCount,
    required int bCount,
  }) {
    final desc = sortDescending;
    int byName() {
      final r = aName.toLowerCase().compareTo(bName.toLowerCase());
      return desc ? -r : r;
    }

    switch (sortMode) {
      case 'name':
        return byName();
      case 'count':
        if (aCount != bCount) {
          return desc ? bCount.compareTo(aCount) : aCount.compareTo(bCount);
        }
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      case 'date':
      default:
        final ka = _airDateSortKey(aDate);
        final kb = _airDateSortKey(bDate);
        // 无日期的条目不参与方向反转，恒定沉底，避免降序时占满首屏。
        if (ka == null && kb == null) {
          return aName.toLowerCase().compareTo(bName.toLowerCase());
        }
        if (ka == null) return 1;
        if (kb == null) return -1;
        if (ka != kb) return desc ? kb.compareTo(ka) : ka.compareTo(kb);
        return aName.toLowerCase().compareTo(bName.toLowerCase());
    }
  }

  // ============ 文件操作 ============

  /// 立即从内存库中移除文件条目，保证面板即时刷新；
  /// 随后的 [scan] 会与磁盘状态做最终同步。
  void _removeFileFromLibrary(LocalMediaFile file) {
    final updated = <LocalMediaFolder>[];
    for (final folder in library) {
      if (folder.files.any((f) => f.path == file.path)) {
        final files = folder.files.where((f) => f.path != file.path).toList();
        if (files.isEmpty) continue; // 分组清空，交由扫描重建
        updated.add(LocalMediaFolder(
            path: folder.path, name: folder.name, files: files));
      } else {
        updated.add(folder);
      }
    }
    library = ObservableList.of(updated);
  }

  @action
  Future<void> deleteFile(LocalMediaFile file) async {
    try {
      final f = File(file.path);
      if (await f.exists()) {
        await f.delete();
      }
      _removeFileFromLibrary(file);
      KazumiDialog.showToast(message: '已删除 ${file.name}');
      await scan();
    } catch (e) {
      KazumiLogger().w('MediaController: deleteFile failed', error: e);
      KazumiDialog.showToast(message: '删除失败：$e');
    }
  }

  @action
  Future<void> renameFile(LocalMediaFile file, String newName) async {
    newName = newName.trim();
    if (newName.isEmpty) {
      KazumiDialog.showToast(message: '文件名不能为空');
      return;
    }
    // 保留原扩展名（若用户未输入）
    final ext = p.extension(file.path);
    if (!newName.toLowerCase().endsWith(ext.toLowerCase())) {
      newName = '$newName$ext';
    }
    final newPath = p.join(p.dirname(file.path), newName);
    if (newPath == file.path) return;
    try {
      final f = File(file.path);
      if (await f.exists()) {
        await f.rename(newPath);
      }
      _removeFileFromLibrary(file);
      KazumiDialog.showToast(message: '已重命名为 $newName');
      await scan();
    } catch (e) {
      KazumiLogger().w('MediaController: renameFile failed', error: e);
      KazumiDialog.showToast(message: '重命名失败：$e');
    }
  }

  @action
  Future<void> moveFile(LocalMediaFile file, String destDir) async {
    destDir = destDir.trim();
    if (destDir.isEmpty) {
      KazumiDialog.showToast(message: '目标路径不能为空');
      return;
    }
    final newPath = p.join(destDir, file.name);
    if (newPath == file.path) {
      KazumiDialog.showToast(message: '文件已在目标位置');
      return;
    }
    try {
      final src = File(file.path);
      if (!await src.exists()) {
        KazumiDialog.showToast(message: '源文件不存在');
        return;
      }
      // 确保目标目录存在
      final dest = Directory(destDir);
      if (!await dest.exists()) {
        await dest.create(recursive: true);
      }
      // rename 在同卷下直接移动；跨卷会抛异常，回退到复制+删除
      try {
        await src.rename(newPath);
      } catch (_) {
        await src.copy(newPath);
        await src.delete();
      }
      _removeFileFromLibrary(file);
      KazumiDialog.showToast(message: '已移动 ${file.name}');
      await scan();
    } catch (e) {
      KazumiLogger().w('MediaController: moveFile failed', error: e);
      KazumiDialog.showToast(message: '移动失败：$e');
    }
  }

  int get totalFiles => library.fold<int>(0, (sum, f) => sum + f.count);

  /// 媒体库全部视频文件的总字节数。
  int get totalSize => library.fold<int>(
        0,
        (sum, folder) =>
            sum + folder.files.fold<int>(0, (acc, file) => acc + file.size),
      );

  // ============ 跨功能查询 ============

  /// 媒体库中匹配指定 Bangumi subject ID 的全部视频文件。
  ///
  /// 文件级搜刮结果优先，其次文件夹级；仅接受来源为 Bangumi 的正 ID。
  List<LocalMediaFile> filesForBangumi(int bangumiId) {
    if (bangumiId <= 0) return const [];
    final result = <LocalMediaFile>[];
    for (final folder in library) {
      final folderInfo = scrapeResults[folder.path];
      for (final file in folder.files) {
        final info = fileScrapeResults[file.path] ?? folderInfo;
        if (info?.bangumiId == bangumiId) {
          result.add(file);
        }
      }
    }
    return result;
  }

  /// 媒体库中匹配该番剧、且文件名为第 [episode] 集的视频文件（无则 null）。
  LocalMediaFile? fileForEpisode(int bangumiId, int episode) {
    if (bangumiId <= 0 || episode <= 0) return null;
    for (final file in filesForBangumi(bangumiId)) {
      if (parseLocalEpisodeNumber(file.name) == episode) return file;
    }
    return null;
  }

  /// 预构建「解析集数 → 文件」映射（单次全库扫描）。
  ///
  /// 播放页剧集列表逐行调用 [fileForEpisode] 是 O(集数 × 全库) 的
  /// 线性扫描，改为构建一次映射后按集数 O(1) 查询。
  Map<int, LocalMediaFile> episodeFileMapForBangumi(int bangumiId) {
    if (bangumiId <= 0) return const {};
    final map = <int, LocalMediaFile>{};
    for (final file in filesForBangumi(bangumiId)) {
      final episode = parseLocalEpisodeNumber(file.name);
      if (episode > 0) map[episode] = file;
    }
    return map;
  }

  /// 媒体库文件按 Bangumi subject ID 聚合的数量（文件级搜刮结果优先）。
  ///
  /// 与 [filesForBangumi] 口径一致（区别于按文件夹整目录计数的旧逻辑，
  /// 混合目录中单文件改匹配到其它番剧时不再虚报）。
  Map<int, int> fileCountsByBangumi() {
    final counts = <int, int>{};
    for (final folder in library) {
      final folderInfo = scrapeResults[folder.path];
      for (final file in folder.files) {
        final info = fileScrapeResults[file.path] ?? folderInfo;
        final bangumiId = info?.bangumiId ?? 0;
        if (bangumiId > 0) {
          counts[bangumiId] = (counts[bangumiId] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  // ============ 未匹配卡片缩略图 ============

  bool _thumbnailGenerating = false;

  /// 为尚未匹配的文件夹生成视频首帧缩略图（需 ffmpeg 可用且设置开启）。
  ///
  /// 缓存键 = 文件路径 + 修改时间 + 大小 的哈希，文件变化后自动重生成；
  /// 已匹配的文件夹展示 Bangumi 封面，不生成。
  Future<void> _generateMissingThumbnails() async {
    if (_thumbnailGenerating) return;
    if (!GStorage.getSetting(SettingsKeys.localMediaThumbnails)) return;
    if (!VideoFrameExtractor.instance.isAvailable) return;
    _thumbnailGenerating = true;
    try {
      final target = <(LocalMediaFolder, LocalMediaFile)>[];
      for (final folder in library) {
        if (scrapeResults.containsKey(folder.path)) continue;
        LocalMediaFile? pick;
        for (final file in folder.files) {
          if (pick == null || file.size > pick.size) pick = file;
        }
        if (pick == null) continue;
        final key = _thumbnailKey(pick);
        final cached = thumbnails[folder.path];
        if (cached != null && cached == key) continue;
        target.add((folder, pick));
      }
      if (target.isEmpty) return;
      final support = await getApplicationSupportDirectory();
      final cacheDir = Directory(p.join(support.path, 'kazumi_thumbnails'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      // 逐个生成，避免同时拉起大量 ffmpeg 进程。
      final updated = Map<String, String>.from(thumbnails);
      for (final (folder, file) in target) {
        try {
          final frame =
              await VideoFrameExtractor.instance.extractFrame(file.path);
          if (frame == null) continue;
          final key = _thumbnailKey(file);
          final dest = File(p.join(cacheDir.path, '${_hash(key)}.jpg'));
          if (!await dest.exists()) {
            await frame.copy(dest.path);
          }
          await frame.delete();
          if (await dest.exists()) {
            updated[folder.path] = key;
          }
        } catch (e) {
          KazumiLogger().w('MediaController: thumbnail failed for ${file.path}',
              error: e);
        }
      }
      if (!mapEquals(updated, Map.from(thumbnails))) {
        thumbnails = ObservableMap.of(updated);
      }
    } catch (e) {
      KazumiLogger()
          .w('MediaController: thumbnail generation failed', error: e);
    } finally {
      _thumbnailGenerating = false;
    }
  }

  static String _thumbnailKey(LocalMediaFile file) =>
      '${file.path}|${file.modifiedAt.millisecondsSinceEpoch}|${file.size}';

  static String _hash(String input) {
    var h = 0;
    for (final code in input.codeUnits) {
      h = (h * 31 + code) & 0x7FFFFFFF;
    }
    return h.toRadixString(16);
  }

  /// 按季数排序的文件夹比较器：季数越靠前越先（无季数判定为第 1 季）。
  static int _compareFoldersBySeason(LocalMediaFolder a, LocalMediaFolder b) {
    const scraper = _SeasonProbe();
    final sa = scraper.parseSeason(a.name) ?? 1;
    final sb = scraper.parseSeason(b.name) ?? 1;
    if (sa != sb) return sa.compareTo(sb);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

/// 仅用于季数比较的轻量探针（MediaScraper 是重量级对象，避免每帧构建）。
class _SeasonProbe {
  const _SeasonProbe();

  int? parseSeason(String raw) {
    final lower = raw.toLowerCase();
    final en = RegExp(r'(?:^|[^a-z])(?:s|season)\s*(\d{1,2})(?:[^a-z0-9]|$)',
            caseSensitive: false)
        .firstMatch(lower);
    if (en != null) {
      final n = int.tryParse(en.group(1)!);
      if (n != null && n >= 1 && n <= 99) return n;
    }
    final cn = RegExp(r'第\s*([一二三四五六七八九十1-9１-９0-9]+)\s*[季期部]').firstMatch(raw);
    if (cn != null) {
      const map = {
        '一': 1,
        '二': 2,
        '三': 3,
        '四': 4,
        '五': 5,
        '六': 6,
        '七': 7,
        '八': 8,
        '九': 9,
        '1': 1,
        '2': 2,
        '3': 3,
        '4': 4,
        '5': 5,
        '6': 6,
        '7': 7,
        '8': 8,
        '9': 9,
      };
      final v = cn.group(1)!.trim();
      if (v == '十') return 10;
      if (v.length >= 2 && v.startsWith('十')) {
        final tail = map[v.substring(1)];
        return tail == null ? null : 10 + tail;
      }
      return map[v];
    }
    return null;
  }
}
