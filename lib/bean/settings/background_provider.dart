import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 自定义背景图的全局状态。
///
/// 背景图铺在整窗底部（AppSurfaceLayer），所有页面都能透出；卡片等表面在
/// 玻璃态下半透明，播放器与图片预览自行退出玻璃效果。
class BackgroundProvider extends ChangeNotifier {
  BackgroundProvider() {
    final stored = GStorage.getSetting(SettingsKeys.customBackgroundPath);
    _imagePath = stored.isNotEmpty && File(stored).existsSync() ? stored : null;
    _blurEnabled = GStorage.getSetting(SettingsKeys.customBackgroundBlur);
    _blurSigma = GStorage.getSetting(SettingsKeys.customBackgroundBlurSigma);
    _opacity = GStorage.getSetting(SettingsKeys.customBackgroundOpacity);
  }

  static const Set<String> _allowedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
  };

  String? _imagePath;
  bool _blurEnabled = false;
  double _blurSigma = 24.0;
  double _opacity = 0.35;

  /// 当前背景图路径；null 表示未设置。
  String? get imagePath => _imagePath;

  bool get hasImage => _imagePath != null;

  bool get blurEnabled => _blurEnabled;

  double get blurSigma => _blurSigma;

  double get opacity => _opacity;

  /// 安装新背景图：拷贝进应用数据目录，避免源文件位于可移动存储或
  /// 临时目录时被移动 / 清理后背景失效。每次拷贝使用独立文件名，
  /// 旧副本待新图生效后再删除，避免同路径缓存导致刷新不及时。
  Future<void> installImage(String sourcePath) async {
    try {
      final directory = await _backgroundDirectory();
      final ext = p.extension(sourcePath).toLowerCase();
      final targetExt = _allowedExtensions.contains(ext) ? ext : '.img';
      final targetPath = p.join(
        directory.path,
        'custom_background_${DateTime.now().microsecondsSinceEpoch}$targetExt',
      );
      await File(sourcePath).copy(targetPath);
      final previous = _imagePath;
      await GStorage.putSetting(SettingsKeys.customBackgroundPath, targetPath);
      _imagePath = targetPath;
      notifyListeners();
      if (previous != null && previous != targetPath) {
        _deleteQuietly(previous);
      }
    } catch (e) {
      KazumiLogger().w('Background: install image failed', error: e);
      rethrow;
    }
  }

  /// 清除背景图并删除本地副本。
  Future<void> clearImage() async {
    final previous = _imagePath;
    _imagePath = null;
    notifyListeners();
    await GStorage.putSetting(SettingsKeys.customBackgroundPath, '');
    if (previous != null) {
      _deleteQuietly(previous);
    }
  }

  Future<void> setBlurEnabled(bool value) async {
    if (_blurEnabled == value) return;
    _blurEnabled = value;
    notifyListeners();
    await GStorage.putSetting(SettingsKeys.customBackgroundBlur, value);
  }

  Future<void> setBlurSigma(double value) async {
    _blurSigma = value;
    notifyListeners();
    await GStorage.putSetting(SettingsKeys.customBackgroundBlurSigma, value);
  }

  Future<void> setOpacity(double value) async {
    _opacity = value.clamp(0.05, 1.0);
    notifyListeners();
    await GStorage.putSetting(SettingsKeys.customBackgroundOpacity, _opacity);
  }

  Future<Directory> _backgroundDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'background'));
    await directory.create(recursive: true);
    return directory;
  }

  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      KazumiLogger().w('Background: delete old image failed', error: e);
    }
  }
}
