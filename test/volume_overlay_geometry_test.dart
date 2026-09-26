import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 音量滑块浮层几何回归测试。
///
/// Overlay 会给 entry 子树施加 tight 全屏约束（`_RenderTheater` 对非
/// Positioned 子节点使用 StackFit.expand 等价约束），浮层必须用
/// UnconstrainedBox 放松约束，否则 `Container(width: 56)` 会被撑满
/// 整个 Overlay，黑色卡片装饰变成覆盖画面的巨大遮罩。
/// 对应实现：`player_item_panel.dart` 的 `_showVolumeOverlay`。
void main() {
  const Size surfaceSize = Size(800, 600);

  Future<void> pumpOverlay(WidgetTester tester) async {
    final LayerLink link = LayerLink();
    await tester.pumpWidget(
      MaterialApp(
        home: Overlay(
          initialEntries: <OverlayEntry>[
            // 模拟底栏右下角的音量按钮（48×48），用 Align 贴右下角，
            // 与应用内"按钮位于底栏末端"的布局方式一致。
            OverlayEntry(
              builder: (BuildContext context) => Align(
                alignment: Alignment.bottomRight,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: CompositedTransformTarget(
                    key: const Key('volumeTarget'),
                    link: link,
                    child: const ColoredBox(color: Colors.red),
                  ),
                ),
              ),
            ),
            OverlayEntry(
              builder: (BuildContext context) => CompositedTransformFollower(
                link: link,
                targetAnchor: Alignment.topCenter,
                followerAnchor: Alignment.bottomCenter,
                child: UnconstrainedBox(
                  alignment: Alignment.bottomCenter,
                  child: MouseRegion(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          key: const Key('volumeCard'),
                          width: 56,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('80'),
                              SizedBox(height: 4),
                              SizedBox(
                                height: 120,
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: Slider(
                                    value: 80,
                                    min: 0,
                                    max: 200,
                                    onChanged: null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('浮层卡片保持内容尺寸，不被 Overlay tight 约束撑满', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surfaceSize;
    addTearDown(tester.view.reset);

    await pumpOverlay(tester);

    final Rect cardRect = tester.getRect(find.byKey(const Key('volumeCard')));
    expect(cardRect.width, 56, reason: '卡片宽度必须保持 56，撑满即回归遮罩缺陷');
    expect(cardRect.height, lessThan(200), reason: '卡片高度应为内容高度');
  });

  testWidgets('浮层卡片贴在音量按钮上方，命中区覆盖 8px 空隙', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surfaceSize;
    addTearDown(tester.view.reset);

    await pumpOverlay(tester);

    final Rect cardRect = tester.getRect(find.byKey(const Key('volumeCard')));
    final Rect targetRect = tester.getRect(
      find.byKey(const Key('volumeTarget')),
    );
    // followerAnchor bottomCenter（含 8px bottom padding）对齐按钮 topCenter：
    // 卡片底边 = 按钮顶边 - 8，水平中心 = 按钮水平中心。
    expect(cardRect.bottom, targetRect.top - 8);
    expect(cardRect.center.dx, targetRect.center.dx);
  });
}
