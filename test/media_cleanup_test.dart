import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 验证媒体库「清理已看完」：
/// 1. 只有「最近观看的最后一集已播放完毕、且已是文件夹内最后一个文件」的
///    文件夹才进入清理候选。
/// 2. 已匹配番剧按番剧聚合，同番剧多季目录中只有已看完的季进入同一项。
/// 3. 批量删除会移除磁盘文件、搜刮结果与内存库条目。
void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp(
      'kazumi_media_cleanup_test_',
    );
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

  Future<Directory> makeLibrary(String name, {int count = 3}) async {
    final dir = Directory('${tempDir.path}/$name');
    await dir.create(recursive: true);
    for (var i = 1; i <= count; i++) {
      await File(
        p.join(
          dir.path,
          '[SubGroup] Kaze Tachibana - ${i.toString().padLeft(2, '0')} [WebRip 1080p].mkv',
        ),
      ).writeAsBytes(List.filled(64, 0));
    }
    return dir;
  }

  File episodeFile(Directory dir, int episode) => File(
    p.join(
      dir.path,
      '[SubGroup] Kaze Tachibana - ${episode.toString().padLeft(2, '0')} [WebRip 1080p].mkv',
    ),
  );

  Future<void> seedHistory(
    Directory dir,
    int lastEpisode,
    Duration position,
  ) async {
    final file = episodeFile(dir, lastEpisode);
    final history = History(
      _bangumiItem,
      lastEpisode,
      kLocalMediaAdapterName,
      DateTime.now(),
      '',
      p.basename(file.path),
      entryKind: HistoryEntryKind.offline,
      episodePageUrl: file.path,
    );
    for (var e = 1; e < lastEpisode; e++) {
      history.progresses[e] = Progress(e, 0, 0, updatedAtMs: e * 1000);
    }
    history.progresses[lastEpisode] = Progress(
      lastEpisode,
      0,
      position.inMilliseconds,
      updatedAtMs: 99000,
    );
    await GStorage.histories.put(history.key, history);
  }

  test('last episode finished: folder becomes a cleanup entry', () async {
    final dir = await makeLibrary('completed');
    await seedHistory(dir, 3, Duration.zero);

    final controller = MediaController();
    controller.folders.add(dir.path);
    await controller.scan();

    final entries = controller.cleanupEntries;
    expect(entries, hasLength(1));
    expect(entries.first.info, isNull);
    expect(entries.first.folders, hasLength(1));
    expect(entries.first.fileCount, 3);
    expect(entries.first.totalSize, 192);
  });

  test('watching mid-episode: folder is not cleanable', () async {
    final dir = await makeLibrary('watching');
    await seedHistory(dir, 2, const Duration(minutes: 12, seconds: 34));

    final controller = MediaController();
    controller.folders.add(dir.path);
    await controller.scan();

    expect(controller.cleanupEntries, isEmpty);
  });

  test(
    'matched group: finishing the show offers all its local folders',
    () async {
      final season1 = await makeLibrary('season1', count: 3);
      final season2 = await makeLibrary('season2', count: 2);
      // 同番剧多季共用一条本地历史：最后观看的是 S2 的最后一集且已看完。
      await seedHistory(season2, 2, Duration.zero);

      final controller = MediaController();
      controller.folders.addAll([season1.path, season2.path]);
      await controller.scan();

      const info = MediaScrapeInfo(
        id: 42,
        name: 'Kaze Tachibana',
        nameCn: '风立',
        summary: '',
        airDate: '',
        coverUrl: '',
      );
      for (final folder in controller.library) {
        await controller.applyScrapeInfo(folder.path, info);
      }

      final entries = controller.cleanupEntries;
      expect(entries, hasLength(1));
      expect(entries.first.title, '风立');
      expect(entries.first.fileCount, 5);
      expect(entries.first.folders.map((folder) => folder.path).toSet(), {
        season1.path,
        season2.path,
      });
    },
  );

  test('deleteLocalFolders removes files, scrape results and library', () async {
    final root = Directory('${tempDir.path}/delete_library');
    final season = Directory(p.join(root.path, 'Kaze Tachibana'));
    await season.create(recursive: true);
    for (var i = 1; i <= 2; i++) {
      await File(
        p.join(
          season.path,
          '[SubGroup] Kaze Tachibana - ${i.toString().padLeft(2, '0')} [WebRip 1080p].mkv',
        ),
      ).writeAsBytes(List.filled(64, 0));
    }
    await seedHistory(season, 2, Duration.zero);

    final controller = MediaController();
    controller.folders.add(root.path);
    await controller.scan();

    final folder = controller.library.first;
    const info = MediaScrapeInfo(
      id: 42,
      name: 'Kaze Tachibana',
      nameCn: '风立',
      summary: '',
      airDate: '',
      coverUrl: '',
    );
    await controller.applyScrapeInfo(folder.path, info);
    final entry = controller.cleanupEntries.single;

    await controller.deleteLocalFolders(entry.folders);

    expect(await season.exists(), isFalse);
    expect(controller.cleanupEntries, isEmpty);
    expect(controller.getScrapeInfo(folder.path), isNull);
    expect(controller.library, isEmpty);
  });
}

final _bangumiItem = BangumiItem(
  id: 42,
  type: 2,
  name: 'Kaze Tachibana',
  nameCn: '风立',
  summary: '',
  airDate: '',
  airWeekday: 0,
  rank: 0,
  images: {},
  tags: [],
  alias: [],
  ratingScore: 0,
  votes: 0,
  votesCount: [],
  info: '',
);

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
