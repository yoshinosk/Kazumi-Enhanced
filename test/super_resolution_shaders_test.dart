import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';

/// 档位链路配置错误不会在编译期暴露，只会在运行时表现为着色器加载失败或画面异常，
/// 因此用测试守住：引用的着色器必须真实存在，且存储值不得漂移。
void main() {
  final Directory shaderDir = Directory('assets/shaders');

  Set<String> availableShaders() => shaderDir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .toSet();

  test('assets/shaders 目录可用', () {
    expect(shaderDir.existsSync(), isTrue,
        reason: '测试需在项目根目录运行');
  });

  test('每个档位引用的着色器都存在于 assets/shaders', () {
    final available = availableShaders();
    for (final mode in SuperResolutionMode.values) {
      for (final shader in mode.shaders) {
        expect(available, contains(shader),
            reason: '${mode.name} 引用了不存在的着色器 $shader');
      }
    }
  });

  test('除关闭档外，每个档位至少包含一个着色器', () {
    for (final mode in SuperResolutionMode.values) {
      if (mode == SuperResolutionMode.off) {
        expect(mode.shaders, isEmpty);
      } else {
        expect(mode.shaders, isNotEmpty, reason: '${mode.name} 未配置着色器');
      }
    }
  });

  test('storageValue 唯一', () {
    final values = SuperResolutionMode.values.map((m) => m.storageValue).toList();
    expect(values.toSet().length, values.length,
        reason: 'storageValue 存在重复，会导致读回时档位错乱');
  });

  test('已发布档位的 storageValue 保持不变', () {
    // 老用户本地已持久化这些值，改动会让其设置静默错位。
    expect(SuperResolutionMode.off.storageValue, 1);
    expect(SuperResolutionMode.efficiency.storageValue, 2);
    expect(SuperResolutionMode.quality.storageValue, 3);
  });

  test('任意 storageValue 都能安全读回', () {
    for (final mode in SuperResolutionMode.values) {
      expect(
        SuperResolutionMode.fromStorageValue(mode.storageValue),
        mode,
        reason: '${mode.name} 无法从 storageValue 还原',
      );
    }
    // 脏数据应回落到关闭，而不是抛异常
    expect(SuperResolutionMode.fromStorageValue(-1), SuperResolutionMode.off);
    expect(SuperResolutionMode.fromStorageValue(999), SuperResolutionMode.off);
  });

  test('Clamp_Highlights 必须位于链路首位', () {
    // 该着色器在所处位置采集图像统计，并在所有着色器执行完后钳制高光。
    // 放在后面会导致统计基准错误，产生振铃。
    for (final mode in SuperResolutionMode.values) {
      if (mode.shaders.isEmpty) continue;
      expect(mode.shaders.first, 'Anime4K_Clamp_Highlights.glsl',
          reason: '${mode.name} 缺少首位的 Clamp_Highlights');
    }
  });
}
