import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 自定义标题栏右上角的「最大化 / 还原」按钮（配合无边框窗口使用）。
///
/// 监听窗口最大化状态以切换图标：未最大化显示方框（最大化），
/// 已最大化显示重叠方框（还原）。
class WindowMaximizeButton extends StatefulWidget {
  const WindowMaximizeButton({super.key});

  @override
  State<WindowMaximizeButton> createState() => _WindowMaximizeButtonState();
}

class _WindowMaximizeButtonState extends State<WindowMaximizeButton>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncState();
  }

  Future<void> _syncState() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted && maximized != _maximized) {
        setState(() => _maximized = maximized);
      }
    } catch (_) {
      // 窗口尚未就绪时忽略。
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted && !_maximized) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted && _maximized) setState(() => _maximized = false);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _maximized ? '还原' : '最大化',
      onPressed: () async {
        if (_maximized) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      icon: Icon(_maximized ? Icons.filter_none : Icons.crop_square),
    );
  }
}
