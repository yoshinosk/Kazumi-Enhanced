import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/pages/magnet/magnet_controller.dart';
import 'package:kazumi/services/magnet/magnet_download_service.dart';
import 'package:kazumi/services/media/local_media_scanner.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 复现用户真实场景：单文件种子直接落在下载根目录（混多部番剧），
/// 验证 scanFoldersForDir 产出的键与媒体库扫描一致，磁力同步可用它
/// 作为搜刮结果键。
void main() {
  late Directory temp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    temp = await Directory.systemTemp.createTemp('kazumi_scrape_key_test');
    PathProviderPlatform.instance = _FakePathProvider(temp);
    Hive.init('${temp.path}/hive');
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('混部根目录拆出的逻辑分组键与磁力任务文件可匹配', () async {
    final root = Directory(p.join(temp.path, 'test'));
    root.createSync(recursive: true);
    File(p.join(root.path,
            '[Nekomoe kissaten&LoliHouse] Kimi ga Shinu made Koi wo Shitai - 06 [WebRip 1080p HEVC-10bit AAC ASSx2].mkv'))
        .createSync();
    File(p.join(root.path,
            '[Nekomoe kissaten&LoliHouse] Kimi ga Shinu made Koi wo Shitai - 07 [WebRip 1080p HEVC-10bit AAC ASSx2].mkv'))
        .createSync();
    File(p.join(root.path,
            '[smzase] Otome Kaijuu Carameliser - S01E07 - [CHS_JPN][WebRip H264 8bit 1080P].mp4'))
        .createSync();
    File(p.join(root.path,
            '[smzase] Otome Kaijuu Carameliser - S01E08 - [CHS_JPN][WebRip H264 8bit 1080P].mp4'))
        .createSync();
    File(p.join(root.path,
            '[LoliHouse] Toukutsu Ou - 06 [WebRip 1080p HEVC-10bit AAC SRTx2].mkv'))
        .createSync();
    File(p.join(root.path,
            '[LoliHouse] Toukutsu Ou - 07 [WebRip 1080p HEVC-10bit AAC SRTx2].mkv'))
        .createSync();
    // 多文件种子子目录
    final kusuriya = Directory(p.join(root.path,
        '[Nekomoe kissaten&LoliHouse] Kusuriya no Hitorigoto [WebRip 1080p HEVC-10bit AAC ASSx2]'));
    kusuriya.createSync(recursive: true);
    File(p.join(kusuriya.path,
            '[Nekomoe kissaten&LoliHouse] Kusuriya no Hitorigoto - 25 [WebRip 1080p HEVC-10bit AAC ASSx2].mkv'))
        .createSync();
    File(p.join(kusuriya.path,
            '[Nekomoe kissaten&LoliHouse] Kusuriya no Hitorigoto - 26 [WebRip 1080p HEVC-10bit AAC ASSx2].mkv'))
        .createSync();

    final scanner = LocalMediaScanner();

    // 与媒体库 scan 一致
    final libraryFolders = await scanner.scan(temp.path, groupByFolder: true);
    final libraryKeys =
        libraryFolders.map((f) => localMediaPathKey(f.path)).toSet();

    // 磁力侧：每个任务用自己的目录做 scanFoldersForDir，再按文件归属匹配
    final rootFolders = scanner.scanFoldersForDir(root.path);
    expect(rootFolders, hasLength(3));
    final kusuriyaFolders = scanner.scanFoldersForDir(kusuriya.path);
    expect(kusuriyaFolders, hasLength(1));

    final kimiKey = rootFolders
        .firstWhere((f) => f.files.any((f2) => f2.name.contains('Kimi ga Shinu')))
        .path;
    final otomeKey = rootFolders
        .firstWhere((f) => f.files.any((f2) => f2.name.contains('Carameliser')))
        .path;
    final toukutsuKey = rootFolders
        .firstWhere((f) => f.files.any((f2) => f2.name.contains('Toukutsu')))
        .path;

    // 三个单文件组的键都必须是库里的真实键（逻辑分组路径）
    expect(libraryKeys, contains(localMediaPathKey(kimiKey)));
    expect(libraryKeys, contains(localMediaPathKey(otomeKey)));
    expect(libraryKeys, contains(localMediaPathKey(toukutsuKey)));
    // 多文件种子子目录键即真实子目录
    expect(localMediaPathKey(kusuriyaFolders.single.path),
        localMediaPathKey(kusuriya.path));
    expect(libraryKeys, contains(localMediaPathKey(kusuriya.path)));
  });

  test('任务文件未落盘时搜刮键不回退目录本身', () {
    final root = Directory(p.join(temp.path, 'mix'));
    root.createSync(recursive: true);
    // 混部目录里的其他番剧文件
    File(p.join(root.path, '[ANi] Kaze Tachibana - 01 [1080P][Baha].mp4'))
        .createSync();
    const fileName =
        '[LoliHouse] Tempal - Item no Chikara - 06 [WebRip 1080p HEVC-10bit AAC ASSx2].mkv';
    MagnetDownloadEntry buildEntry() => MagnetDownloadEntry(
          title: '[LoliHouse] Tempal - Item no Chikara - 06',
          sourceUri: 'magnet:?xt=urn:btih:test',
          addedAt: DateTime.now(),
          savePath: root.path,
          fileName: fileName,
          files: [
            MagnetDownloadFile(
              index: 0,
              name: fileName,
              path: fileName,
              size: 1,
              isStreamable: true,
            ),
          ],
        );

    final controller = MagnetController();

    // 文件尚未落盘（引擎校验前的瞬时完成态）：不能解析出键就返回空串，
    // 绝不能回退目录本身——否则任务被误标为已同步、媒体库永远未匹配。
    expect(controller.scrapeKeyForEntryForTest(buildEntry()), isEmpty);

    // 文件落盘后：键为标题分组逻辑路径（在目录内，但不是目录本身）。
    File(p.join(root.path, fileName)).createSync();
    final key = controller.scrapeKeyForEntryForTest(buildEntry());
    expect(key, isNotEmpty);
    expect(localMediaPathKey(key), isNot(localMediaPathKey(root.path)));
    expect(p.isWithin(root.path, key), isTrue);

    // 旧数据无文件清单：沿用旧行为回退真实落盘目录。
    final legacy = MagnetDownloadEntry(
      title: 'legacy',
      sourceUri: 'magnet:?xt=urn:btih:legacy',
      addedAt: DateTime.now(),
      savePath: root.path,
    );
    expect(
      localMediaPathKey(controller.scrapeKeyForEntryForTest(legacy)),
      localMediaPathKey(root.path),
    );
  });
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);

  final Directory _root;

  @override
  Future<String?> getApplicationSupportPath() async =>
      '${_root.path}/app_support';
}