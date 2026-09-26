import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/window_maximize_button.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/utils/device.dart';

class SysAppBar extends StatefulWidget implements PreferredSizeWidget {
  final double? toolbarHeight;

  final Widget? title;

  final Color? backgroundColor;

  final double? elevation;

  final ShapeBorder? shape;

  final List<Widget>? actions;

  final Widget? leading;

  final double? leadingWidth;

  final PreferredSizeWidget? bottom;

  final bool needTopOffset;

  const SysAppBar({
    super.key,
    this.toolbarHeight,
    this.title,
    this.backgroundColor,
    this.elevation,
    this.shape,
    this.actions,
    this.leading,
    this.leadingWidth,
    this.bottom,
    this.needTopOffset = true,
  });

  bool showWindowButton() {
    return GStorage.getSetting(SettingsKeys.showWindowButton);
  }

  @override
  State<SysAppBar> createState() => _SysAppBarState();

  @override
  Size get preferredSize {
    // macOS needs to add 22(macOS title bar height)
    // to default toolbar height to build appbar like normal
    double baseHeight;
    if (Platform.isMacOS && needTopOffset && showWindowButton()) {
      baseHeight = (toolbarHeight ?? kToolbarHeight) + 22;
    } else {
      baseHeight = toolbarHeight ?? kToolbarHeight;
    }
    // bottom（如 TabBar）的高度需要计入，否则标题会被底部组件遮挡
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(baseHeight + bottomHeight);
  }
}

class _SysAppBarState extends State<SysAppBar> {
  /// 双击最大化：手动检测两次主键单击。
  ///
  /// GestureDetector 的 DoubleTap 与 Pan 识别器在手势竞技场中互斥：
  /// 鼠标按下期间抖动超过 2px（kPrecisePointerPanSlop）即被 Pan 抢占并
  /// 进入原生拖拽循环，双击最大化几乎必然失效，故改用手动检测。
  DateTime? _lastTapUpAt;
  Offset? _lastTapUpLocalPosition;

  /// 拖拽窗口：按下后在标题栏工具区内移动超过阈值才启动原生拖拽
  /// （按下即启动会吞掉子按钮的点击）。
  Offset? _primaryDownPosition;
  bool _dragStarted = false;

  static const Duration _doubleTapInterval = Duration(milliseconds: 300);
  static const double _doubleTapMaxDistance = 32;
  static const double _dragSlop = 4;

  bool get _isDesktop => isDesktop();

  double get _toolbarHeight {
    // 与 preferredSize 的口径一致（macOS 隐藏标题栏布局需要 +22 偏移）。
    if (Platform.isMacOS && widget.needTopOffset && widget.showWindowButton()) {
      return (widget.toolbarHeight ?? kToolbarHeight) + 22;
    }
    return widget.toolbarHeight ?? kToolbarHeight;
  }

  /// 双击标题栏在最大化 / 还原之间切换（与原生标题栏行为一致）。
  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {
      // 窗口尚未就绪时忽略。
    }
  }

  /// 仅标题栏工具区参与拖拽 / 双击；bottom（如 TabBar）区域完全交给
  /// 子组件：双击 Tab 栏空白处不应触发最大化，拖动 Tab 栏应滚动 Tab
  /// 而不是拖动窗口。
  bool _inToolbarArea(Offset localPosition) {
    return localPosition.dy < _toolbarHeight;
  }

  void _handleTapUp(TapUpDetails details) {
    final box = context.findRenderObject();
    if (box is! RenderBox) {
      return;
    }
    final local = box.globalToLocal(details.globalPosition);
    if (!_inToolbarArea(local)) {
      _lastTapUpAt = null;
      return;
    }
    final now = DateTime.now();
    final lastAt = _lastTapUpAt;
    final lastPos = _lastTapUpLocalPosition;
    _lastTapUpAt = now;
    _lastTapUpLocalPosition = local;
    if (lastAt == null || lastPos == null) {
      return;
    }
    if (now.difference(lastAt) <= _doubleTapInterval &&
        (local - lastPos).distance <= _doubleTapMaxDistance) {
      _lastTapUpAt = null;
      _toggleMaximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> acs = [];
    if (widget.actions != null) {
      acs.addAll(widget.actions!);
    }
    if (_isDesktop) {
      // acs.add(IconButton(onPressed: () => windowManager.minimize(), icon: const Icon(Icons.minimize)));
      if (!widget.showWindowButton()) {
        acs.add(const WindowMaximizeButton());
        acs.add(CloseButton(onPressed: () => windowManager.close()));
      }
      acs.add(const SizedBox(width: 8));
    }
    final appBar = AppBar(
      toolbarHeight: widget.preferredSize.height,
      scrolledUnderElevation: 0.0,
      title: widget.title != null
          ? EmbeddedNativeControlArea(
              requireOffset: widget.needTopOffset,
              child: widget.title!,
            )
          : null,
      centerTitle: Platform.isIOS ? true : false,
      actions: acs.map((e) {
        return EmbeddedNativeControlArea(
          requireOffset: widget.needTopOffset,
          child: e,
        );
      }).toList(),
      leading: widget.leading != null
          ? EmbeddedNativeControlArea(
              requireOffset: widget.needTopOffset,
              child: widget.leading!,
            )
          : (ModalRoute.of(context)?.impliesAppBarDismissal ?? false)
          ? EmbeddedNativeControlArea(
              requireOffset: widget.needTopOffset,
              child: IconButton(
                onPressed: () {
                  context.maybePop();
                },
                icon: Icon(Icons.arrow_back),
              ),
            )
          : null,
      leadingWidth: widget.leadingWidth,
      backgroundColor: widget.backgroundColor,
      elevation: widget.elevation,
      shape: widget.shape,
      bottom: widget.bottom,
      automaticallyImplyLeading: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            Theme.of(context).brightness == Brightness.light
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
    if (!_isDesktop) {
      return appBar;
    }
    // onTapUp 走手势竞技场：点击子按钮时子识别器获胜，父级 tap 不触发，
    // 双击按钮不会被误判为双击标题栏；空标题栏区域的 tap 由父级获得，
    // 用于手动双击检测。
    return Listener(
      onPointerDown: (event) {
        if (event.buttons != kPrimaryButton) return;
        _dragStarted = false;
        _primaryDownPosition = event.localPosition;
      },
      onPointerMove: (event) {
        if (event.buttons != kPrimaryButton) return;
        if (_dragStarted) return;
        final down = _primaryDownPosition;
        if (down == null || !_inToolbarArea(down)) return;
        if ((event.localPosition - down).distance > _dragSlop) {
          _dragStarted = true;
          _lastTapUpAt = null;
          windowManager.startDragging();
        }
      },
      onPointerUp: (_) {
        _primaryDownPosition = null;
        _dragStarted = false;
      },
      onPointerCancel: (_) {
        _primaryDownPosition = null;
        _dragStarted = false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: _handleTapUp,
        child: appBar,
      ),
    );
  }
}
