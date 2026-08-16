import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/request/apis/trace_api.dart';
import 'package:kazumi/services/media/video_frame_extractor.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 端到端验证「ffmpeg 抽帧 → trace.moe 识别」链路。
///
/// 沙盒/CI 无 ffmpeg、无可用的本地视频或无法初始化存储时整体跳过，不视为失败。
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 恢复真实网络请求（flutter_test 默认把所有 HTTP mock 成 400）。
  HttpOverrides.global = null;
  PathProviderPlatform.instance = _FakePathProvider();

  final sampleVideo = Platform.environment['KAZUMI_TEST_VIDEO'] ??
      r'F:\Animate\202604\[Feibanyama] Witch Hat Atelier S01E09 [CR WebRip 1080p HEVC AAC Multi-Audio Multi-Subs].mkv';

  bool storageReady = false;
  try {
    await Hive.initFlutter();
    await GStorage.init();
    storageReady = true;
  } catch (_) {
    storageReady = false;
  }

  final available = VideoFrameExtractor.instance.isAvailable &&
      File(sampleVideo).existsSync() &&
      storageReady;

  test('extractFrame produces a readable jpeg', () async {
    final extractor = VideoFrameExtractor.instance;
    final frame = await extractor.extractFrame(sampleVideo);
    expect(frame, isNotNull, reason: 'should extract a frame');
    final bytes = await frame!.readAsBytes();
    expect(bytes.length, greaterThan(0));
    await frame.delete();
  }, skip: available ? false : 'no ffmpeg or sample video');

  test('trace.moe recognizes the extracted frame', () async {
    final extractor = VideoFrameExtractor.instance;
    final frame = await extractor.extractFrame(sampleVideo);
    expect(frame, isNotNull);
    final result = await TraceApi.searchAnimeByImageFile(
      frame!,
      anilistInfo: 2,
    );
    await frame.delete();

    expect(result.result, isNotNull);
    expect(result.result, isNotEmpty);
    final best = result.result!
        .reduce((a, b) => (a.similarity ?? 0) >= (b.similarity ?? 0) ? a : b);
    expect(best.similarity, greaterThan(0.5));
    expect(best.anilist?.title?.romaji, isNotNull);
  }, skip: available ? false : 'no ffmpeg or sample video');
}

class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      Directory.systemTemp.createTempSync('kazumi_hive').path;
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.path;
  @override
  Future<String?> getApplicationCachePath() async => Directory.systemTemp.path;
  @override
  Future<String?> getDownloadsPath() async => Directory.systemTemp.path;
}