import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/app_background_layer.dart';
import 'package:kazumi/utils/surface_theme.dart';
import 'package:kazumi/utils/theme.dart';

ThemeData _baseTheme() =>
    buildAppTheme(brightness: Brightness.dark, fontFamily: null, color: Colors.green);

void main() {
  group('backgroundSurfaceTheme', () {
    test('页面遮罩与卡片表面都变半透明，浮层用的 surface 保持不透明', () {
      final base = _baseTheme();
      final theme = backgroundSurfaceTheme(base, 0.65);
      final colors = theme.colorScheme;

      expect(theme.scaffoldBackgroundColor.a, closeTo(0.65, 0.0001));
      expect(theme.appBarTheme.backgroundColor!.a, closeTo(0.65, 0.0001));
      // 卡片比页面更透，背景图在卡片内更明显。
      expect(colors.surfaceContainerLow.a,
          closeTo(0.65 * cardSurfaceAlphaScale, 0.0001));
      expect(colors.surfaceContainerHighest.a, lessThan(0.3));
      // 弹窗、底部弹层叠在页面之上，必须保持不透明。
      expect(colors.surface.a, base.colorScheme.surface.a);
      expect(colors.surfaceContainerLowest.a, base.colorScheme.surfaceContainerLowest.a);
    });

    test('卡片补上描边，未自带 shape 的 Card 由 cardTheme 带上', () {
      final theme = backgroundSurfaceTheme(_baseTheme(), 0.65);
      final outline = theme.extension<KazumiSurfaces>()!.cardOutline;

      expect(outline.width, 1);
      expect(outline.color.a, closeTo(0.14, 0.0001));
      final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(shape.side, outline);
    });

    test('极端背景不透明度下卡片底色仍有上下限', () {
      final nearlyTransparentPage = backgroundSurfaceTheme(_baseTheme(), 1.0);
      expect(nearlyTransparentPage.colorScheme.surfaceContainerLow.a,
          closeTo(cardSurfaceAlphaScale, 0.0001));

      final nearlyOpaquePage = backgroundSurfaceTheme(_baseTheme(), 0.0);
      expect(nearlyOpaquePage.colorScheme.surfaceContainerLow.a,
          closeTo(minCardSurfaceAlpha, 0.0001));
    });

    test('浅色主题下卡片底色接近白色半透明', () {
      final base = buildAppTheme(
          brightness: Brightness.light, fontFamily: null, color: Colors.green);
      final card = backgroundSurfaceTheme(base, 0.65).colorScheme.surfaceContainerLow;

      expect(card.a, closeTo(0.65 * cardSurfaceAlphaScale, 0.0001));
      // 浅色主题的 surfaceContainerLow 本身就是接近白的颜色。
      expect((card.r + card.g + card.b) / 3, greaterThan(0.9));
    });
  });

  group('KazumiSurfaces', () {
    test('未启用背景图时不描边，视觉与引入前一致', () {
      final surfaces = _baseTheme().extension<KazumiSurfaces>()!;

      expect(surfaces, isNotNull);
      expect(surfaces.cardOutline, BorderSide.none);
      expect(surfaces.cardOutline.width, 0);
    });

    test('copyWith / lerp 保持描边描述完整', () {
      final glass = KazumiSurfaces.glass(_baseTheme().colorScheme);
      final solid = const KazumiSurfaces.solid();

      expect(glass.copyWith().cardOutline, glass.cardOutline);
      expect(solid.lerp(glass, 0.5).cardOutline.width, closeTo(0.5, 0.0001));
      expect(glass.lerp(null, 0.5), glass);
    });
  });
}
