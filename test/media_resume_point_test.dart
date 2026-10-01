import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 验证媒体库「上次看到哪里」：
/// 1. 续播点按文件路径精确匹配，并携带上次观看位置。
/// 2. 上次一集看完（进度落库时归零）后，续播点标记 finished 并推进到
///    同文件夹内的下一个文件；最后一集看完则无下一集。
/// 3. 分集观看状态按文件名解析的集数记录各集最后观看位置。
void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('kazumi_media_resume_test_');
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

  Future<Directory> makeLibrary(String name) async {
    final dir = Directory('${tempDir.path}/$name');
    await dir.create(recursive: true);
    for (var i = 1; i <= 3; i++) {
      await File(
        p.join(dir.path, '[SubGroup] Kaze Tachibana - ${i.toString().padLeft(2, '0')} [WebRip 1080p].mkv'),
      ).writeAsBytes(List.filled(64, 0));
    }
    return dir;
  }

  History buildHistory(Directory dir, int lastEpisode, Duration position) {
    final file = File(
      p.join(
        dir.path,
        '[SubGroup] Kaze Tachibana - ${lastEpisode.toString().padLeft(2, '0')} [WebRip 1080p].mkv',
      ),
    );
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
    // 前几集看完（进度归零），最后一集处于观看中或同样看完。
    for (var e = 1; e < lastEpisode; e++) {
      history.progresses[e] = Progress(e, 0, 0, updatedAtMs: e * 1000);
    }
    history.progresses[lastEpisode] =
        Progress(lastEpisode, 0, position.inMilliseconds, updatedAtMs: 99000);
    return history;
  }

  test('watching mid-episode: resume points at the file with position',
      () async {
    final dir = await makeLibrary('watching');
    await GStorage.histories.put(
      buildHistory(dir, 2, const Duration(minutes: 12, seconds: 34)).key,
      buildHistory(dir, 2, const Duration(minutes: 12, seconds: 34)),
    );

    final controller = MediaController();
    controller.folders.add(dir.path);
    await controller.scan();

    final resume = controller.resumePointForFolders(controller.library);
    expect(resume, isNotNull);
    expect(resume!.episode, 2);
    expect(resume.position, const Duration(minutes: 12, seconds: 34));
    expect(resume.finished, isFalse);
    expect(resume.nextFile, isNull);

    final positions =
        controller.watchPositionsFor(controller.library.first)!;
    expect(positions[1], Duration.zero);
    expect(positions[2], const Duration(minutes: 12, seconds: 34));
    expect(positions.containsKey(3), isFalse);
  });

  test('finished episode: resume advances to the next file', () async {
    final dir = await makeLibrary('finished');
    // EP2 看完：距结尾过近落库归零（与 updateHistory 的口径一致）。
    final history = buildHistory(dir, 2, Duration.zero);
    await GStorage.histories.put(history.key, history);

    final controller = MediaController();
    controller.folders.add(dir.path);
    await controller.scan();

    final resume = controller.resumePointForFolders(controller.library);
    expect(resume, isNotNull);
    expect(resume!.finished, isTrue);
    expect(resume.episode, 2);
    expect(resume.nextFile, isNotNull);
    expect(resume.nextFile!.path,
        p.join(dir.path, '[SubGroup] Kaze Tachibana - 03 [WebRip 1080p].mkv'));
  });

  test('last episode finished: no next file', () async {
    final dir = await makeLibrary('completed');
    final history = buildHistory(dir, 3, Duration.zero);
    await GStorage.histories.put(history.key, history);

    final controller = MediaController();
    controller.folders.add(dir.path);
    await controller.scan();

    final resume = controller.resumePointForFolders(controller.library);
    expect(resume, isNotNull);
    expect(resume!.finished, isTrue);
    expect(resume.episode, 3);
    expect(resume.nextFile, isNull);
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
