import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:watcher/watcher.dart';

/// Windows 媒体库文件夹监听器：目录变化（创建 / 删除 / 重命名 / 修改）
/// 经去抖后触发一次重扫回调。
///
/// 基于 `package:watcher` 的 [DirectoryWatcher]（Windows 上递归监听、运行在
/// 独立 isolate，避免缓冲区溢出）。Android 没有纯 Dart 的目录监听，媒体库页
/// 保留定时轮询兜底，这里只对 Windows 生效；[supported] 恒为 false 时
/// 所有调用都是安全的空操作。
class MediaFolderWatcher {
  MediaFolderWatcher({required this.onChanged});

  /// 目录变化去抖后触发（约 1.5 秒内合并连续事件）。
  final VoidCallback onChanged;

  final List<StreamSubscription<WatchEvent>> _subscriptions = [];
  Timer? _debounce;
  bool _started = false;

  static bool get supported => Platform.isWindows;

  /// 重建监听集合（先停旧的）。[folders] 为空时仅停止。
  void start(List<String> folders) {
    if (!supported) return;
    stop();
    if (folders.isEmpty) return;
    _started = true;
    for (final folder in folders) {
      try {
        final watcher = DirectoryWatcher(folder);
        _subscriptions.add(watcher.events.listen(
          _handleEvent,
          onError: (Object e) {
            KazumiLogger()
                .w('MediaFolderWatcher: watch error for $folder', error: e);
          },
        ));
      } catch (e) {
        KazumiLogger().w('MediaFolderWatcher: cannot watch $folder', error: e);
      }
    }
    if (_subscriptions.isNotEmpty) {
      KazumiLogger().i(
          'MediaFolderWatcher: watching ${_subscriptions.length} folders on Windows');
    }
  }

  void _handleEvent(WatchEvent event) {
    if (!_started) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), () {
      if (_started) {
        onChanged();
      }
    });
  }

  void stop() {
    _started = false;
    _debounce?.cancel();
    _debounce = null;
    for (final subscription in _subscriptions) {
      try {
        subscription.cancel();
      } catch (_) {}
    }
    _subscriptions.clear();
  }
}
