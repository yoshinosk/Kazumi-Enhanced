import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/media/local_media_scanner.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late LocalMediaScanner scanner;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('kazumi_scan_test');
    scanner = LocalMediaScanner();
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  String pathOf(String relative) => p.join(temp.path, relative);

  test('单个番剧文件夹保持整体（不拆分）', () async {
    final sub = Directory(
        pathOf('[LoliHouse] Beheneko [01-12][WebRip 1080p HEVC-10bit AAC]'));
    sub.createSync(recursive: true);
    for (var i = 1; i <= 2; i++) {
      final n = i.toString().padLeft(2, '0');
      File(p.join(sub.path, '[LoliHouse] Beheneko - $n [WebRip].mkv'))
          .createSync();
    }

    final result = await scanner.scan(temp.path, groupByFolder: true);
    // 环境根目录无直接视频，只有那一部番剧的子目录，应只有 1 个条目，
    // 且该条目即整目录（文件全部清洗为同一个标题，不拆分）。
    expect(result, hasLength(1));
    expect(result.single.files, hasLength(2));
  });

  test('日期文件夹内含多部番剧会按标题拆分', () async {
    final sub = Directory(pathOf('202607'));
    sub.createSync(recursive: true);
    File(p.join(sub.path, 'Behenko - 01 [1080p].mkv')).createSync();
    File(p.join(sub.path, 'Behenko - 02 [1080p].mkv')).createSync();
    File(p.join(sub.path, 'Mato Seihei no Slave - 01.mkv')).createSync();

    final result = await scanner.scan(temp.path, groupByFolder: true);
    // 目录内有两个不同标题，应拆成两个分组条目
    final titles = result.map((f) => f.name).toList();
    expect(titles, containsAll(['Behenko', 'Mato Seihei no Slave']));
  });

  test('groupByFolder=false 时仍按标题分组', () async {
    File(pathOf('ShowOne [S01E01].mkv')).createSync();
    File(pathOf('ShowOne [S01E02].mkv')).createSync();
    File(pathOf('ShowTwo [S01E01].mkv')).createSync();

    final result = await scanner.scan(temp.path, groupByFolder: false);
    final titles = result.map((f) => f.name).toList();
    expect(titles, containsAll(['ShowTwo', 'ShowOne']));
  });

  test('剧集文件按集数自然排序', () {
    final files = [
      LocalMediaFile(
        path: pathOf('Show - 10.mkv'),
        name: 'Show - 10.mkv',
        size: 0,
        modifiedAt: DateTime(2026),
      ),
      LocalMediaFile(
        path: pathOf('Show - 2.mkv'),
        name: 'Show - 2.mkv',
        size: 0,
        modifiedAt: DateTime(2026),
      ),
      LocalMediaFile(
        path: pathOf('Show - 1.mkv'),
        name: 'Show - 1.mkv',
        size: 0,
        modifiedAt: DateTime(2026),
      ),
    ]..sort(compareLocalMediaFilesForTest);

    expect(files.map((file) => file.name), [
      'Show - 1.mkv',
      'Show - 2.mkv',
      'Show - 10.mkv',
    ]);
  });

  test('路径去重遵循当前平台大小写规则', () {
    final upper = localMediaPathIdentityForTest(pathOf('Anime/EP01.mkv'));
    final lower = localMediaPathIdentityForTest(pathOf('anime/ep01.mkv'));
    expect(upper == lower, Platform.isWindows);
  });

  test('scanWithGroupings 单标题时分组键为整目录', () async {
    final sub = Directory(pathOf('202607'));
    sub.createSync(recursive: true);
    File(p.join(sub.path, 'Behenko - 01 [1080p].mkv')).createSync();

    final result =
        await scanner.scanWithGroupings(temp.path, groupByFolder: true);
    expect(result.folders, hasLength(1));
    final grouping = result.groupings[localMediaPathKey(sub.path)];
    expect(grouping, isNotNull);
    // 单标题 → 分组路径即目录本身，键为归一化标题
    expect(grouping!.values.single, sub.path);
    expect(grouping.keys.single, 'behenko');
  });

  test('scanWithGroupings 多标题时分组键为标题逻辑路径', () async {
    final sub = Directory(pathOf('202607'));
    sub.createSync(recursive: true);
    File(p.join(sub.path, 'Behenko - 01 [1080p].mkv')).createSync();
    File(p.join(sub.path, 'Mato Seihei no Slave - 01.mkv')).createSync();

    final result =
        await scanner.scanWithGroupings(temp.path, groupByFolder: true);
    final grouping = result.groupings[localMediaPathKey(sub.path)];
    expect(grouping, isNotNull);
    expect(grouping!.keys, containsAll(['behenko', 'matoseiheinoslave']));
    expect(
      localMediaPathKey(grouping['behenko']!),
      localMediaPathKey(p.join(sub.path, 'Behenko')),
    );
    expect(
      localMediaPathKey(grouping['matoseiheinoslave']!),
      localMediaPathKey(p.join(sub.path, 'Mato Seihei no Slave')),
    );
  });
}
