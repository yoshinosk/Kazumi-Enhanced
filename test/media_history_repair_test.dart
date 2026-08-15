import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 验证本地媒体库播放历史的占位番剧修复：
/// 1. [MediaController.getFileScrapeInfo] 必须按所在文件夹路径查询
///    文件夹级搜刮结果（传文件全路径永远查不到）。
/// 2. 扫描后自动把以占位番剧（id <= 0）落库的本地历史迁移到真实番剧。
void main() {
  late Directory tempDir;
  late HistoryRepository repository;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('kazumi_media_hist_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    Hive.init('${tempDir.path}/hive');
    await GStorage.init();
    repository = HistoryRepository();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('getFileScrapeInfo resolves folder-level result by folder path', () {
    final controller = MediaController();
    final folder = LocalMediaFolder(
      path: r'F:\media\Otome Kaijuu Carameliser',
      name: 'Otome Kaijuu Carameliser',
      files: const [],
    );
    const info = MediaScrapeInfo(
      id: 617123,
      name: '乙女怪獣キャラメリゼ',
      nameCn: '少女怪兽焦糖味',
      summary: '',
      airDate: '2026-07-02',
      coverUrl: '',
    );
    controller.scrapeResults[folder.path] = info;

    final file = LocalMediaFile(
      path: r'F:\media\Otome Kaijuu Carameliser\ep06.mkv',
      name: 'ep06.mkv',
      size: 0,
      modifiedAt: DateTime.now(),
    );

    // 无文件级结果时回退到文件夹级结果。
    expect(controller.getFileScrapeInfo(file, folder)?.bangumiId, 617123);
    expect(controller.getFileScrapeInfo(file, folder)?.displayName,
        '少女怪兽焦糖味');

    // 文件级结果优先级更高。
    const fileInfo = MediaScrapeInfo(
      id: 999,
      name: 'SP',
      nameCn: 'SP',
      summary: '',
      airDate: '',
      coverUrl: '',
    );
    controller.fileScrapeResults[file.path] = fileInfo;
    expect(controller.getFileScrapeInfo(file, folder)?.id, 999);
  });

  test('placeholder local history is migrated to real bangumi after scan',
      () async {
    final mediaDir = Directory('${tempDir.path}/media');
    await mediaDir.create(recursive: true);
    const fileName =
        '[smzase&LoliHouse] Otome Kaijuu Carameliser - 06 [WebRip 1080p HEVC-10bit AAC ASSx2].mkv';
    final video = File(p.join(mediaDir.path, fileName));
    await video.writeAsBytes(List.filled(64, 0));

    // 占位 BangumiItem（id <= 0）的历史条目。
    final placeholder = BangumiItem(
      id: -1651578227,
      type: 2,
      name: 'Otome Kaijuu Carameliser',
      nameCn: 'Otome Kaijuu Carameliser',
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: const {},
      tags: const [],
      alias: const [],
      ratingScore: 0,
      votes: 0,
      votesCount: const [],
      info: '',
    );
    final history = History(
      placeholder,
      6,
      kLocalMediaAdapterName,
      DateTime.now(),
      '',
      fileName,
      entryKind: HistoryEntryKind.offline,
      episodePageUrl: video.path,
    )
      ..progresses[6] = Progress(6, 0, 12000, updatedAtMs: 1000);
    await GStorage.histories.put(history.key, history);

    final controller = MediaController();
    controller.folders.add(mediaDir.path);
    await controller.scan();

    // 找到文件所在逻辑分组文件夹，补上真实搜刮结果，再扫描触发迁移。
    final folder = controller.library
        .firstWhere((f) => f.files.any((file) => file.path == video.path));
    final real = MediaScrapeInfo(
      id: 617123,
      name: '乙女怪獣キャラメリゼ',
      nameCn: '少女怪兽焦糖味',
      summary: '',
      airDate: '2026-07-02',
      coverUrl: '',
    );
    controller.scrapeResults[folder.path] = real;
    await controller.scan();

    // _repairPlaceholderHistories 在 scan 内 unawaited 执行，轮询等待完成。
    await _waitUntil(() => !repository
        .getAllHistories()
        .any((h) => isLocalMediaHistory(h) && h.bangumiItem.id <= 0));

    final all = repository.getAllHistories();
    final migrated = all
        .where(isLocalMediaHistory)
        .where((h) => h.episodePageUrl == video.path)
        .toList();
    expect(migrated, isNotEmpty,
        reason: '占位历史应迁移到真实番剧条目下');
    expect(migrated.single.bangumiItem.id, 617123);
    expect(migrated.single.bangumiItem.nameCn, '少女怪兽焦糖味');
    expect(migrated.single.lastWatchEpisode, 6);
    expect(migrated.single.progresses[6]?.progress, const Duration(seconds: 12));
    expect(
        all.any((h) =>
            isLocalMediaHistory(h) && h.bangumiItem.id <= 0),
        isFalse,
        reason: '不应残留占位番剧历史');
  });
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var i = 0; i < 100; i++) {
    if (predicate()) return;
    await Future.delayed(const Duration(milliseconds: 20));
  }
  fail('timed out waiting for condition');
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
