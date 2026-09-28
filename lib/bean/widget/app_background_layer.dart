import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/settings/background_provider.dart';
import 'package:kazumi/utils/surface_theme.dart';

/// 背景遮罩的不透明度：与「背景不透明度」设置反向，遮罩越淡背景图越明显。
double backgroundVeilAlpha(BackgroundProvider background) =>
    (1.0 - background.opacity).clamp(0.0, 1.0);

/// 背景启用时，页面 / 导航等「表面」使用的半透明底色：
/// 主题 scaffoldBackgroundColor 乘以 (1 - 背景不透明度)。
///
/// 统一用它而非全透明，既能透出背景图，又保证文字在图片上的可读性；
/// 固定头部（媒体库 / 时间表）以 scaffoldBackgroundColor 铺底，会自动跟随。
Color backgroundVeilColor(BuildContext context, BackgroundProvider background) {
  final scaffoldColor = Theme.of(context).scaffoldBackgroundColor;
  return scaffoldColor.withValues(alpha: backgroundVeilAlpha(background));
}

/// 背景启用时 outlet 子树使用的主题：页面与卡片表面统一改为半透明。
///
/// - [veil] 是页面遮罩的不透明度，与 [backgroundVeilColor] 同源，
///   负责 Scaffold / AppBar 底色；
/// - 卡片等表面色在遮罩基础上按 [cardSurfaceAlphaScale] 再衰减一档，
///   并以 [minCardSurfaceAlpha] 兜底：卡片比页面更透，背景图在卡片内更明显，
///   极端不透明度下文字仍然可读；
/// - `surface` / `surfaceContainerLowest` 保持不透明：弹窗、底部弹层叠在页面之上，
///   需要足够的对比度；
/// - 卡片描边由 [KazumiSurfaces.glass] 提供，卡片用 [cardShape] 取；
///   未自带 shape 的 [Card] 由这里的 cardTheme 统一补上。
ThemeData backgroundSurfaceTheme(ThemeData base, double veil) {
  final colors = base.colorScheme;
  final veilAlpha = veil.clamp(0.0, 1.0);
  final alpha =
      (veilAlpha * cardSurfaceAlphaScale).clamp(minCardSurfaceAlpha, 1.0);
  Color fade(Color color) => color.withValues(alpha: alpha);
  final surfaces = KazumiSurfaces.glass(colors);
  // 按扩展类型覆盖卡片表面样式，其余主题扩展保持不变。
  final extensions = Map<Object, ThemeExtension<dynamic>>.of(base.extensions)
    ..[KazumiSurfaces] = surfaces;

  return base.copyWith(
    scaffoldBackgroundColor:
        base.scaffoldBackgroundColor.withValues(alpha: veilAlpha),
    appBarTheme: base.appBarTheme.copyWith(
      // AppBar 默认底色是 colorScheme.surface（保持不透明），这里按遮罩淡化成半透明，
      // 主界面那些不显式指定底色的 SliverAppBar 才能透出背景图。
      backgroundColor: (base.appBarTheme.backgroundColor ?? colors.surface)
          .withValues(alpha: veilAlpha),
    ),
    colorScheme: colors.copyWith(
      surfaceContainer: fade(colors.surfaceContainer),
      surfaceContainerLow: fade(colors.surfaceContainerLow),
      surfaceContainerHigh: fade(colors.surfaceContainerHigh),
      surfaceContainerHighest: fade(colors.surfaceContainerHighest),
      primaryContainer: fade(colors.primaryContainer),
      secondaryContainer: fade(colors.secondaryContainer),
      tertiaryContainer: fade(colors.tertiaryContainer),
    ),
    cardTheme: base.cardTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        side: surfaces.cardOutline,
      ),
    ),
    extensions: extensions.values,
  );
}

/// 主界面自定义背景图层：铺满父级，按设置绘制图片与毛玻璃（高斯模糊）。
///
/// 未设置背景图时渲染为空；透明度由页面侧的 [backgroundVeilColor]
/// 半透明底色实现，本组件只负责图片本身。
class AppBackgroundLayer extends StatelessWidget {
  const AppBackgroundLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final background = context.watch<BackgroundProvider>();
    final path = background.imagePath;
    if (path == null) {
      return const SizedBox.shrink();
    }

    Widget image = Image.file(
      File(path),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      cacheWidth: _decodeWidth(context),
    );
    if (background.blurEnabled) {
      // ImageFiltered 只模糊图片本身，开销远小于对整页实时 BackdropFilter；
      // 静态内容会被光栅缓存，滑动页面时不重复计算。
      image = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: background.blurSigma,
          sigmaY: background.blurSigma,
        ),
        child: image,
      );
    }

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 图片解码完成前先垫上默认背景色，避免闪白 / 闪黑。
          ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          image,
        ],
      ),
    );
  }

  /// 按屏幕最长边限制解码尺寸，控制整屏背景图的内存占用；
  /// 覆盖裁切下该尺寸已足够清晰，毛玻璃模式下更看不出差异。
  int _decodeWidth(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (size.longestSide * dpr).round().clamp(640, 4096);
  }
}
