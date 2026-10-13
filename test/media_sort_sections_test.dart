import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 回归：番剧 / 网格视图在分组型排序（最近播放 / 最近更新 / 番剧季度）下
/// 存在未匹配文件夹时，排序比较器曾对未匹配组的空 info 使用 null 断言，
/// 导致页面构建崩溃（Null check operator used on a null value）。
void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('kazumi_media_sort_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    Hive.init('${tempDir.path}/hive');
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  MediaController buildController() {
    final controller = MediaController()
      ..scrapeResults['/media/a'] = const MediaScrapeInfo(
        id: 1,
        name: 'Anime A',
        nameCn: '番剧A',
        summary: '',
        airDate: '2024-04-01',
        coverUrl: '',
      )
      ..scrapeResults['/media/b'] = const MediaScrapeInfo(
        id: 2,
        name: 'Anime B',
        nameCn: '番剧B',
        summary: '',
        airDate: '2023-10-05',
        coverUrl: '',
      )
      ..library = ObservableList.of([
        LocalMediaFolder(
          path: '/media/a',
          name: 'a',
          files: [
            LocalMediaFile(
              path: '/media/a/ep01.mkv',
              name: 'ep01.mkv',
              size: 1,
              modifiedAt: DateTime(2025, 1, 1),
            ),
          ],
        ),
        LocalMediaFolder(
          path: '/media/b',
          name: 'b',
          files: [
            LocalMediaFile(
              path: '/media/b/ep01.mkv',
              name: 'ep01.mkv',
              size: 1,
              modifiedAt: DateTime(2025, 3, 1),
            ),
          ],
        ),
        LocalMediaFolder(
          path: '/media/unknown',
          name: '未匹配目录',
          files: [
            LocalMediaFile(
              path: '/media/unknown/ep01.mkv',
              name: 'ep01.mkv',
              size: 1,
              modifiedAt: DateTime(2025, 2, 1),
            ),
          ],
        ),
      ]);
    return controller;
  }

  test('番剧视图分组型排序下存在未匹配组不再崩溃', () async {
    for (final mode in const ['played', 'updated', 'season']) {
      final controller = buildController();
      await controller.setSortMode(mode);
      // 修复前此处抛 Null check operator used on a null value。
      final sections = controller.animeSections;
      expect(sections, isNotEmpty, reason: '排序模式 $mode');
    }
  });

  test('番剧视图季度排序下未匹配组沉底到「季度未知」分组', () async {
    final controller = buildController();
    await controller.setSortMode('season');
    final sections = controller.animeSections;
    expect(sections.last.title, '季度未知');
    expect(sections.last.items.single.info, isNull);
  });

  test('番剧视图季度排序降序下未匹配组仍沉底', () async {
    final controller = buildController();
    await controller.setSortMode('season');
    await controller.setSortDescending(true);
    final sections = controller.animeSections;
    expect(sections.last.title, '季度未知');
    expect(sections.last.items.single.info, isNull);
  });

  test('网格视图分组型排序下未匹配卡片不再崩溃', () async {
    for (final mode in const ['played', 'updated', 'season']) {
      final controller = buildController();
      await controller.setSortMode(mode);
      final sections = controller.gridSections;
      expect(sections, isNotEmpty, reason: '排序模式 $mode');
    }
  });

  test('网格视图季度排序下未匹配卡片沉底到「季度未知」分组', () async {
    final controller = buildController();
    await controller.setSortMode('season');
    final sections = controller.gridSections;
    expect(sections.last.title, '季度未知');
    expect(sections.last.items.single.isMatched, isFalse);
  });
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);

  final Directory _root;

  @override
  Future<String?> getApplicationSupportPath() async =>
      '${_root.path}/app_support';
  @override
  Future<String?> getTemporaryPath() async => '${_root.path}/temp';
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      '${_root.path}/documents';
  @override
  Future<String?> getApplicationCachePath() async => '${_root.path}/cache';
  @override
  Future<String?> getDownloadsPath() async => '${_root.path}/downloads';
}
