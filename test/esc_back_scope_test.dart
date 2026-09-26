import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/esc_back_scope.dart';

/// 全局 ESC 返回回归测试（`esc_back_scope.dart`）。
///
/// EscBackScope 挂载在根 Navigator 之上，按键事件从焦点路由沿焦点树冒泡：
/// - 推入页面（左上角有返回按钮的页面）按 ESC 应退出；
/// - 嵌套路由（设置面板 / tab 内路由）先退最内层能弹出的 Navigator；
/// - 不可弹出的根路由（主界面 tab shell）按 ESC 无效果；
/// - 文本框聚焦时 ESC 留给输入，不触发返回；
/// - PopScope 保护中的页面（canPop: false）按 ESC 走 onPopInvoked 守卫，
///   与系统返回键行为一致。
void main() {
  Widget wrapApp(Widget home) {
    return MaterialApp(
      builder: (context, child) => EscBackScope(child: child),
      home: home,
    );
  }

  Future<void> pressEscape(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  testWidgets('推入页面按 ESC 返回上一页', (tester) async {
    await tester.pumpWidget(wrapApp(
      const Scaffold(body: Text('home')),
    ));
    tester.state<NavigatorState>(find.byType(Navigator)).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('pushed')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('pushed'), findsOneWidget);

    await pressEscape(tester);
    expect(find.text('pushed'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('嵌套路由先退最内层，再次 ESC 才退宿主页面', (tester) async {
    const nestedSubPageKey = Key('nested-sub-page');
    const nestedIndexKey = Key('nested-index');
    await tester.pumpWidget(wrapApp(
      const Scaffold(body: Text('home')),
    ));
    final rootNavigator = tester.state<NavigatorState>(find.byType(Navigator));
    rootNavigator.push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: Navigator(
          initialRoute: 'nested/',
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: SizedBox(key: nestedIndexKey)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final nestedNavigator = tester.state<NavigatorState>(
      find.byType(Navigator).last,
    );
    nestedNavigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: SizedBox(key: nestedSubPageKey)),
    ));
    await tester.pumpAndSettle();

    await pressEscape(tester);
    expect(find.byKey(nestedSubPageKey), findsNothing);
    expect(find.byKey(nestedIndexKey), findsOneWidget);

    await pressEscape(tester);
    expect(find.byKey(nestedIndexKey), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('主界面不可弹出，按 ESC 无效果', (tester) async {
    await tester.pumpWidget(wrapApp(
      const Scaffold(body: Text('home')),
    ));
    await pressEscape(tester);
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文本框聚焦时按 ESC 不触发返回', (tester) async {
    await tester.pumpWidget(wrapApp(
      const Scaffold(body: Text('home')),
    ));
    tester.state<NavigatorState>(find.byType(Navigator)).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: TextField(autofocus: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);

    await pressEscape(tester);
    expect(tester.takeException(), isNull);
    // 页面仍在：推入路由未被弹出（home 文本被推入页遮挡，不直接断言）。
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isTrue);
  });

  testWidgets('PopScope 保护中的页面按 ESC 触发守卫，解除保护后再次 ESC 才退出',
      (tester) async {
    var protected = true;
    await tester.pumpWidget(wrapApp(
      const Scaffold(body: Text('home')),
    ));
    tester.state<NavigatorState>(find.byType(Navigator)).push(
      MaterialPageRoute<void>(
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => PopScope(
            canPop: !protected,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && protected) {
                protected = false;
                // 与历史页编辑模式一致：先退保护状态，再按才真正返回。
                setState(() {});
              }
            },
            child: const Scaffold(body: Text('guarded')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('guarded'), findsOneWidget);

    await pressEscape(tester);
    expect(protected, isFalse);
    expect(find.text('guarded'), findsOneWidget);

    await pressEscape(tester);
    expect(find.text('guarded'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}
