import 'dart:io';

import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/media/local_media_scanner.dart';
import 'package:kazumi/services/media/media_scraper.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:mobx/mobx.dart';
import 'package:path/path.dart' as p;

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

/// 从 `YYYY-MM-DD` / `YYYY-MM` / `YYYY` 形式的首播日期解析出可比较的整数键。
///
/// 解析失败（空串或非法格式）返回 null，调用方需把这类条目排到末尾 ——
/// 未知日期既不该占据「最新」也不该占据「最早」的位置。
int? _airDateSortKey(String airDate) {
  if (airDate.isEmpty) return null;
  final match = RegExp(r'^(\d{4})(?:-(\d{1,2}))?(?:-(\d{1,2}))?').firstMatch(airDate);
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

  @observable
  ObservableList<String> folders = ObservableList();

  @observable
  ObservableList<LocalMediaFolder> library = ObservableList();

  @observable
  bool isScanning = false;

  @observable
  ObservableMap<String, MediaScrapeInfo> scrapeResults = ObservableMap();

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
    if (folders.isNotEmpty) {
      await scan();
    }
  }

  @action
  Future<void> addFolder(String path) async {
    path = path.trim();
    if (path.isEmpty) return;
    if (folders.any((f) => f.toLowerCase() == path.toLowerCase())) {
      KazumiDialog.showToast(message: '该文件夹已添加');
      return;
    }
    folders.add(path);
    await LocalMediaFolderStore.save(folders.toList());
    await scan();
  }

  @action
  Future<void> removeFolder(String path) async {
    folders.removeWhere((f) => f == path);
    await LocalMediaFolderStore.save(folders.toList());
    await scan();
  }

  @action
  Future<void> scan() async {
    if (folders.isEmpty) {
      library.clear();
      return;
    }
    isScanning = true;
    try {
      final result = await _scanner.scanAll(
        folders.toList(),
        groupByFolder: groupByFolder,
      );
      library
        ..clear()
        ..addAll(result);
    } catch (e) {
      KazumiLogger().w('MediaController: scan failed', error: e);
      KazumiDialog.showToast(message: '扫描失败：$e');
    } finally {
      isScanning = false;
    }
  }

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
      await MediaScrapeStore.save(Map<String, MediaScrapeInfo>.from(scrapeResults));
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
    await MediaScrapeStore.save(Map<String, MediaScrapeInfo>.from(scrapeResults));
  }

  /// 清除文件夹的搜刮结果。
  @action
  Future<void> removeScrapeResult(String folderPath) async {
    scrapeResults.remove(folderPath);
    await MediaScrapeStore.save(Map<String, MediaScrapeInfo>.from(scrapeResults));
  }

  /// 获取文件夹的搜刮结果。
  MediaScrapeInfo? getScrapeInfo(String folderPath) =>
      scrapeResults[folderPath];

  /// 按番剧分组返回，排序遵循 [sortMode] / [sortDescending]，未匹配组恒定排在末尾。
  List<AnimeGroup> get animeGroups {
    final matched = <int, AnimeGroup>{};
    final unmatched = <LocalMediaFolder>[];
    for (final folder in library) {
      final info = scrapeResults[folder.path];
      if (info != null) {
        final existing = matched[info.id];
        if (existing != null) {
          matched[info.id] = AnimeGroup(
            info: info,
            folders: [...existing.folders, folder],
          );
        } else {
          matched[info.id] = AnimeGroup(info: info, folders: [folder]);
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
    return groups;
  }

  /// 网格视图数据源：已匹配番剧聚合成一张卡片，未匹配文件夹各自成卡。
  ///
  /// 默认按番剧首播日期降序（最新番在前），无日期的条目恒定沉底。
  List<MediaGridItem> get gridItems {
    final matched = <int, MediaGridItem>{};
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
      final existing = matched[info.id];
      matched[info.id] = MediaGridItem(
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
    // 未匹配条目没有元数据可排，统一按名称升序垫在最后。
    unmatched.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
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

  @action
  Future<void> deleteFile(LocalMediaFile file) async {
    try {
      final f = File(file.path);
      if (await f.exists()) {
        await f.delete();
      }
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
      KazumiDialog.showToast(message: '已移动 ${file.name}');
      await scan();
    } catch (e) {
      KazumiLogger().w('MediaController: moveFile failed', error: e);
      KazumiDialog.showToast(message: '移动失败：$e');
    }
  }

  int get totalFiles => library.fold<int>(0, (sum, f) => sum + f.count);
}
