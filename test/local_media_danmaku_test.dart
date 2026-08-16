import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/utils/local_episode_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('local media danmaku sidecar', () {
    late Directory tempDir;
    late DownloadController controller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kazumi_danmaku_test');
      controller = DownloadController(
        _FakeDownloadRepository(),
        _FakeDownloadManager(),
        PluginsController(),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('write+read per-episode sidecar round-trip', () async {
      final danmaku = DanmakuEntry(
        message: '测试',
        time: 123.5,
        type: 1,
        color: Colors.white,
        source: '',
      );

      await controller.writeDirectoryDanmaku(tempDir.path, [danmaku], 176158,
          episode: 1);

      final file = File('${tempDir.path}/danmaku_1.json');
      expect(await file.exists(), isTrue, reason: '分集侧车文件应生成');

      final sidecar = await controller.readDirectoryDanmaku(tempDir.path,
          episode: 1);
      expect(sidecar, isNotNull);
      expect(sidecar!.danDanBangumiID, 176158);
      expect(sidecar.danmakus, hasLength(1));
      expect(sidecar.danmakus.first.message, '测试');
      expect(sidecar.danmakus.first.time, 123.5);
    });

    test('不同集数互不覆盖', () async {
      await controller.writeDirectoryDanmaku(tempDir.path, [
        DanmakuEntry(
            message: '第1集',
            time: 1.0,
            type: 1,
            color: Colors.white,
            source: ''),
      ], 100, episode: 1);
      await controller.writeDirectoryDanmaku(tempDir.path, [
        DanmakuEntry(
            message: '第2集',
            time: 2.0,
            type: 1,
            color: Colors.white,
            source: ''),
      ], 100, episode: 2);

      final ep1 = await controller.readDirectoryDanmaku(tempDir.path,
          episode: 1);
      final ep2 = await controller.readDirectoryDanmaku(tempDir.path,
          episode: 2);
      expect(ep1!.danmakus.first.message, '第1集');
      expect(ep2!.danmakus.first.message, '第2集');
    });

    test('无集数时读写 danmaku.json（下载记录格式兼容）', () async {
      await controller.writeDirectoryDanmaku(tempDir.path, [
        DanmakuEntry(
            message: '默认',
            time: 1.0,
            type: 1,
            color: Colors.white,
            source: ''),
      ], 99);

      final sidecar = await controller.readDirectoryDanmaku(tempDir.path);
      expect(sidecar, isNotNull);
      expect(sidecar!.danmakus, hasLength(1));
    });
  });

  group('real media library filename parsing', () {
    const samples = [
      '[LoliHouse] Beheneko - 01 [WebRip 1080p HEVC-10bit AAC SRTx2].mkv',
      '[LoliHouse] Beheneko - 12 [WebRip 1080p HEVC-10bit AAC SRTx2].mkv',
      '[LoliHouse] Sword Art Online Alternative - Gun Gale Online II - 05 [WebRip].mkv',
      '[LoliHouse] VTuber Nanda ga Haishin Kiri Wasuretara Densetsu 04.mkv',
    ];

    test('Beheneko folder episode numbers', () {
      final expected = [1, 12, 5, 4];
      for (var i = 0; i < samples.length; i++) {
        expect(parseLocalEpisodeNumber(samples[i]), expected[i],
            reason: '${samples[i]} -> ${expected[i]}');
      }
    });

    test('清洗出可用于弹幕检索的番剧名', () {
      final expected = [
        'Beheneko',
        'Beheneko',
        'Sword Art Online Alternative - Gun Gale Online II',
        'VTuber Nanda ga Haishin Kiri Wasuretara Densetsu',
      ];
      for (var i = 0; i < samples.length; i++) {
        expect(sanitizeAnimeTitle(samples[i]), expected[i],
            reason: '${samples[i]} -> ${expected[i]}');
      }
    });
  });
}

class _FakeDownloadRepository implements IDownloadRepository {
  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<void> deleteEpisode(String recordKey, int episodeNumber) async {}

  @override
  Future<void> deleteRecord(String key) async {}

  @override
  List<DownloadRecord> getAllRecords() => [];

  @override
  List<DownloadEpisode> getCompletedEpisodes(
      int bangumiId, String pluginName) {
    return [];
  }

  @override
  DownloadEpisode? getEpisode(
      int bangumiId, String pluginName, int episodeNumber) {
    return null;
  }

  @override
  DownloadEpisode? getEpisodeByUrl(
      int bangumiId, String pluginName, String episodePageUrl) {
    return null;
  }

  @override
  bool getForceAdBlocker() => false;

  @override
  DownloadRecord? getRecord(String key) => null;

  @override
  DownloadRecord? getRecordByBangumiId(int bangumiId, String pluginName) =>
      null;

  @override
  Future<void> putRecord(DownloadRecord record) async {}

  @override
  Future<void> updateEpisode(
      String recordKey, int episodeNumber, DownloadEpisode episode) async {}
}

class _FakeDownloadManager implements IDownloadManager {
  @override
  ProgressCallback? onProgress;

  @override
  Future<void> cancel(String recordKey, int episodeNumber) async {}

  @override
  Future<void> deleteEpisodeFiles(int bangumiId, String pluginName,
      int episodeNumber,
      {DownloadEpisode? episode}) async {}

  @override
  Future<void> deleteRecordFiles(int bangumiId, String pluginName,
      {DownloadRecord? record}) async {}

  @override
  Future<void> enqueue(DownloadRequest request) async {}

  @override
  Future<void> enqueuePriority(DownloadRequest request) async {}

  @override
  String? getLocalVideoPath(DownloadEpisode? episode) => null;

  @override
  double getSpeed(String recordKey, int episodeNumber) => 0;

  @override
  bool isDownloading(String recordKey, int episodeNumber) => false;

  @override
  Future<void> pause(String recordKey, int episodeNumber) async {}

  @override
  Future<void> resume(DownloadRequest request) async {}
}