import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:kazumi/utils/device.dart';

/// 桌面端全局 ESC 返回。
///
/// 挂载在根 Navigator 之上（MaterialApp.builder），焦点路由内的按键事件会
/// 沿焦点树上溯到这里的 Shortcuts 焦点节点。自行声明 ESC 语义的更近层
/// （播放器全屏快捷键的 early handler、对话框 DismissIntent、页面级搜索
/// 关闭快捷键）在焦点链上更靠近焦点，天然优先，不会被本组件截胡。
///
/// 弹出逻辑为「最内层能弹出的 Navigator 先退」：从焦点所在位置向上收集
/// 元素祖先链上的所有 Navigator（内层在前），对第一个 `canPop` 的执行
/// `maybePop`（尊重 PopScope 守卫），全部不可弹出则无操作。因此嵌套路由
/// （设置页子面板、tab 内部路由）先于宿主页面退出；主界面 shell 路由不可
/// 弹出，ESC 在无返回按钮的 tab 页上不产生任何效果。
///
/// 注意不能用 `Navigator.maybeOf(navigator.context)` 逐级向上找父 Navigator：
/// 该 API 对 Navigator 自身的 context 会优先返回自身（StatefulElement 自匹配），
/// 会形成死循环。
class EscBackScope extends StatelessWidget {
  const EscBackScope({super.key, this.child});

  final Widget? child;

  static void _handleEscape() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null || !focusContext.mounted) {
      return;
    }

    // 焦点在文本输入框内时把 ESC 留给输入（结束候选/合成），不触发返回。
    if (focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null) {
      return;
    }

    final navigators = <NavigatorState>[];
    focusContext.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is NavigatorState) {
        navigators.add(element.state as NavigatorState);
      }
      return true;
    });
    for (final navigator in navigators) {
      if (navigator.canPop()) {
        navigator.maybePop();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktop()) {
      return child ?? const SizedBox.shrink();
    }
    return CallbackShortcuts(
      bindings: const {
        SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
      },
      child: child ?? const SizedBox.shrink(),
    );
  }
}
