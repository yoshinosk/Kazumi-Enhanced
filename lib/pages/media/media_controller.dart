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
    // 触发 Observer 刷新
    library = ObservableList.of(library.toList());
  }

  // ============ 搜刮 ============

  /// 请求取消当前正在进行的搜刮。
  @action
  void cancelScrape() {
    _scrapeCancelRequested = true;
  }

  /// 搜刮所有文件夹的番剧元数据。
  @action
  Future<void> scrapeAll() async {
    if (library.isEmpty) {
      KazumiDialog.showToast(message: '没有可搜刮的文件夹');
      return;
    }
    isScraping = true;
    scrapeDone = 0;
    scrapeTotal = library.length;
    scrapeMatched = 0;
    scrapeFailed = 0;
    scrapeCurrentName = '';
    scrapeKeyword = '';
    _scrapeCancelRequested = false;
    try {
      final results = await _scraper.scrapeAll(
        library.toList(),
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
      final unmatchedPaths = <String>{
        for (final r in results)
          if (r.status != ScrapeStatus.matched) r.folderPath,
      };
      scrapeResults
        ..removeWhere((path, _) => unmatchedPaths.contains(path))
        ..addAll(matched);
      await MediaScrapeStore.save(Map<String, MediaScrapeInfo>.from(scrapeResults));
      final toastMessage = _scrapeCancelRequested
          ? '已取消搜刮，匹配 ${matched.length}/${library.length} 个文件夹'
          : '搜刮完成，匹配 ${matched.length}/${library.length} 个文件夹'
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

  /// 按番剧分组返回。
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
      ..sort((a, b) => a.info!.displayName.compareTo(b.info!.displayName));
    if (unmatched.isNotEmpty) {
      groups.add(AnimeGroup(info: null, folders: unmatched));
    }
    return groups;
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
