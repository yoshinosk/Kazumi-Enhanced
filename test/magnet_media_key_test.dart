import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/media/local_media_scanner.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:path/path.dart' as p;

/// 复现用户真实场景：单文件种子直接落在下载根目录（混多部番剧），
/// 验证 scanFoldersForDir 产出的键与媒体库扫描一致，磁力同步可用它
/// 作为搜刮结果键。
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('kazumi_scrape_key_test');
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
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
}