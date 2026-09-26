import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/player_panel_hold.dart';

/// PlayerPanelHoldMenuAnchor 开合回调回归测试。
///
/// onOpen/onClose 由视频画面右键菜单用于联动本地命中层状态
/// （菜单打开期间接管左键点击，点击画面仅关闭菜单），必须与
/// onVisibilityChanged、PlayerPanelHold 生命周期保持一致：
/// - 重复 open() 不重复回调 onOpen、不重复持有 hold；
/// - 锚点在菜单打开期间被卸载（如锁定面板、页面退出）时，
///   onClose 与 hold 释放仍会发生。
void main() {
  Future<void> pumpAnchor(
    WidgetTester tester, {
    required ValueChanged<bool> onVisibilityChanged,
    required VoidCallback onOpen,
    required VoidCallback onClose,
    required PlayerPanelHold Function() acquireHold,
    bool alwaysOpen = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: PlayerPanelHoldMenuAnchor(
              acquirePlayerPanelHold: acquireHold,
              onVisibilityChanged: onVisibilityChanged,
              onOpen: onOpen,
              onClose: onClose,
              menuChildren: const [
                MenuItemButton(onPressed: null, child: Text('菜单项')),
              ],
              builder: (context, controller, child) => IconButton(
                onPressed: () {
                  if (alwaysOpen || !controller.isOpen) {
                    controller.open();
                  } else {
                    controller.close();
                  }
                },
                icon: const Icon(Icons.more_vert),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('打开/关闭菜单时 onOpen、onVisibilityChanged 与 hold 对称触发', (
    tester,
  ) async {
    int openCount = 0;
    int closeCount = 0;
    final List<bool> visibilityEvents = <bool>[];
    int holdsAcquired = 0;
    int holdsReleased = 0;

    await pumpAnchor(
      tester,
      onVisibilityChanged: visibilityEvents.add,
      onOpen: () => openCount++,
      onClose: () => closeCount++,
      acquireHold: () {
        holdsAcquired++;
        return PlayerPanelHold(onRelease: () => holdsReleased++);
      },
    );

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.text('菜单项'), findsOneWidget);
    expect(openCount, 1);
    expect(closeCount, 0);
    expect(visibilityEvents, <bool>[true]);
    expect(holdsAcquired, 1);
    expect(holdsReleased, 0);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.text('菜单项'), findsNothing);
    expect(openCount, 1);
    expect(closeCount, 1);
    expect(visibilityEvents, <bool>[true, false]);
    expect(holdsAcquired, 1);
    expect(holdsReleased, 1);
  });

  testWidgets('菜单已打开时再次 open() 先关闭再重开，hold 不泄漏', (tester) async {
    int openCount = 0;
    int closeCount = 0;
    final List<bool> visibilityEvents = <bool>[];
    int holdsAcquired = 0;
    int holdsReleased = 0;

    await pumpAnchor(
      tester,
      onVisibilityChanged: visibilityEvents.add,
      onOpen: () => openCount++,
      onClose: () => closeCount++,
      acquireHold: () {
        holdsAcquired++;
        return PlayerPanelHold(onRelease: () => holdsReleased++);
      },
      alwaysOpen: true,
    );

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    // SDK 语义：open() 在菜单已打开时会先 close() 再重新打开（重新定位），
    // 回调必须成对出现，且打开状态至多持有一个未释放的 hold。
    expect(find.text('菜单项'), findsOneWidget);
    expect(openCount, 2);
    expect(closeCount, 1);
    expect(visibilityEvents, <bool>[true, false, true]);
    expect(holdsAcquired, 2);
    expect(holdsReleased, 1);
    expect(holdsAcquired - holdsReleased, 1, reason: 'hold 不得泄漏');
  });

  testWidgets('锚点在菜单打开期间被卸载时仍触发 onClose 并释放 hold', (tester) async {
    int closeCount = 0;
    final List<bool> visibilityEvents = <bool>[];
    int holdsAcquired = 0;
    int holdsReleased = 0;

    await pumpAnchor(
      tester,
      onVisibilityChanged: visibilityEvents.add,
      onOpen: () {},
      onClose: () => closeCount++,
      acquireHold: () {
        holdsAcquired++;
        return PlayerPanelHold(onRelease: () => holdsReleased++);
      },
    );

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(closeCount, 0);
    expect(holdsReleased, 0);

    // 直接卸载锚点（等价于页面退出 / 锁定面板时 Observer 切换分支）。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(closeCount, 1);
    expect(visibilityEvents, <bool>[true, false]);
    expect(holdsAcquired, 1);
    expect(holdsReleased, 1);
  });
}
