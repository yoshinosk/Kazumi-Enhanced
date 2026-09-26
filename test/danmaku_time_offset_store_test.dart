import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/danmaku_time_offset_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 验证弹幕轴偏移的遗留数据迁移：
/// 1. 旧版误写入全局设置的遗留偏移（如 -82 秒）被一次性清零，
///    不再作为 effectiveOffset 兜底污染所有未命中作用域的视频。
/// 2. 迁移只执行一次（标记位落地），此后用户主动设置的全局偏移保留。
/// 3. 分集 / 番剧作用域偏移不受全局迁移影响。
void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('kazumi_danmaku_offset_test_');
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

  setUp(() async {
    await GStorage.putSetting<double>(
        SettingsKeys.danmakuTimeOffset, -82.0);
    await GStorage.putSetting<bool>(
        SettingsKeys.danmakuTimeOffsetGlobalMigrated, false);
    await GStorage.putSetting<String>(
        SettingsKeys.danmakuTimeOffsetByEpisode, '');
  });

  test('migrateLegacyGlobalOffset clears polluted global offset once', () async {
    expect(DanmakuTimeOffsetStore.effectiveOffset(19782, 197820008), -82.0,
        reason: '未命中作用域时应回退到全局偏移（复现污染场景）');

    await DanmakuTimeOffsetStore.migrateLegacyGlobalOffset();

    expect(DanmakuTimeOffsetStore.effectiveOffset(19782, 197820008), 0.0);
    expect(
        GStorage.getSetting<bool>(
            SettingsKeys.danmakuTimeOffsetGlobalMigrated),
        isTrue);
  });

  test('migrateLegacyGlobalOffset keeps user global offset after migration',
      () async {
    await DanmakuTimeOffsetStore.migrateLegacyGlobalOffset();

    await GStorage.putSetting<double>(SettingsKeys.danmakuTimeOffset, 5.0);
    await DanmakuTimeOffsetStore.migrateLegacyGlobalOffset();

    expect(DanmakuTimeOffsetStore.effectiveOffset(0, 0), 5.0,
        reason: '迁移只执行一次，此后主动设置的全局偏移应保留');
  });

  test('scoped offsets are untouched by global migration', () async {
    await DanmakuTimeOffsetStore.setScopedOffset(100, 200, -10);
    await DanmakuTimeOffsetStore.migrateLegacyGlobalOffset();

    expect(DanmakuTimeOffsetStore.effectiveOffset(100, 200), -10.0);
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
