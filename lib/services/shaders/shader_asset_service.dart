import 'dart:io';

import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:kazumi/services/logging/logger.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 着色器资源包版本。
///
/// 只要增删或替换 assets/shaders 下的着色器，就必须递增此值。
/// 早期实现仅判断文件是否存在，导致升级应用后老用户仍在使用旧着色器。
const int shaderBundleVersion = 2;

class ShaderAssetService {
  static const String _shaderAssetPrefix = 'assets/shaders/';
  static const String _versionFileName = '.shader_bundle_version';

  late Directory shadersDirectory;

  Future<void> copyShadersToExternalDirectory() async {
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = assetManifest.listAssets();
    final directory = await getApplicationSupportDirectory();
    shadersDirectory = Directory(path.join(directory.path, 'anime_shaders'));

    if (!await shadersDirectory.exists()) {
      await shadersDirectory.create(recursive: true);
      KazumiLogger()
          .i('ShaderManager: Create GLSL Shader: ${shadersDirectory.path}');
    }

    final shaderFiles = assets
        .where((String asset) =>
            asset.startsWith(_shaderAssetPrefix) && asset.endsWith('.glsl'))
        .toList();

    if (await _isBundleUpToDate()) {
      KazumiLogger().i(
          'ShaderManager: bundle v$shaderBundleVersion is up to date, skip copy');
      return;
    }

    int copiedFilesCount = 0;

    for (var filePath in shaderFiles) {
      final fileName = filePath.split('/').last;
      final targetFile = File(path.join(shadersDirectory.path, fileName));

      try {
        final data = await rootBundle.load(filePath);
        final List<int> bytes = data.buffer.asUint8List();
        await targetFile.writeAsBytes(bytes);
        copiedFilesCount++;
        KazumiLogger().i('ShaderManager: Copy: ${targetFile.path}');
      } catch (e) {
        KazumiLogger().e('ShaderManager: Copy: ($filePath)', error: e);
      }
    }

    // 只有全部拷贝成功才记录版本，失败的文件才能在下次启动时补上。
    if (copiedFilesCount == shaderFiles.length) {
      await _writeBundleVersion();
    } else {
      KazumiLogger().w('ShaderManager: only $copiedFilesCount/'
          '${shaderFiles.length} shaders copied, version not recorded');
    }

    KazumiLogger().i(
        'ShaderManager: $copiedFilesCount GLSL files copied to ${shadersDirectory.path}');
  }

  Future<bool> _isBundleUpToDate() async {
    final versionFile =
        File(path.join(shadersDirectory.path, _versionFileName));
    if (!await versionFile.exists()) {
      return false;
    }
    try {
      return (await versionFile.readAsString()).trim() ==
          shaderBundleVersion.toString();
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeBundleVersion() async {
    final versionFile =
        File(path.join(shadersDirectory.path, _versionFileName));
    try {
      await versionFile.writeAsString(shaderBundleVersion.toString());
    } catch (e) {
      KazumiLogger().e('ShaderManager: write version file', error: e);
    }
  }
}
