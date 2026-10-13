import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/settings/background_provider.dart';
import 'package:kazumi/utils/surface_theme.dart';

/// 背景遮罩的不透明度：与「背景不透明度」设置反向，遮罩越淡背景图越明显。
///
/// 页面 / 导航等「表面」都用它乘主题底色得到半透明遮罩色，既能透出背景图，
/// 又保证文字在图片上的可读性。
double backgroundVeilAlpha(BackgroundProvider background) =>
    (1.0 - background.opacity).clamp(0.0, 1.0);

/// 页面遮罩色（半透明）：背景图之上的那层「玻璃」。
///
/// 遮罩由 [AppSurfaceLayer] 在背景图与所有页面之间全局铺一层，
/// 页面 Scaffold 自身全透明。需要在页面内容上自绘同款遮罩的地方
/// （外观设置的背景预览、详情页页眉渐隐等）用它保持一致。
/// 未启用背景图（非玻璃态）时返回不透明的主题底色，行为与从前一致。
Color backgroundVeilColor(BuildContext context) {
  final theme = Theme.of(context);
  final base = pageVeilBaseColor(theme);
  if (!(theme.extension<KazumiSurfaces>()?.glass ?? false)) return base;
  final background = context.watch<BackgroundProvider>();
  return base.withValues(alpha: backgroundVeilAlpha(background));
}

/// 背景启用时使用的全局主题：页面与卡片表面统一改为半透明。
///
/// - 页面遮罩不再由页面铺：scaffoldBackgroundColor 置透明，遮罩由
///   [AppSurfaceLayer] 在背景图与路由树之间全局铺唯一一层，页面互相叠放
///   时遮罩不会翻倍，切换结束被盖路由剔除时也不会亮度跳变；
/// - 卡片等表面色按 [cardSurfaceAlphaScale] 在遮罩基础上再衰减一档，
///   并以 [minCardSurfaceAlpha] 兜底：卡片比页面更透，背景图在卡片内更明显，
///   极端不透明度下文字仍然可读；
/// - `surface` / `surfaceContainerLowest` 保持不透明：底部弹层等浮层叠在页面之上，
///   需要足够的对比度；弹窗另由 dialogTheme 与 modalSurfaceColor 兜住；
/// - 卡片描边由 [KazumiSurfaces.glass] 提供，卡片用 [cardShape] 取；
///   未自带 shape 的 [Card] 由这里的 cardTheme 统一补上；
/// - 路由切换统一用 M3 forwards 淡入切换（透明底色）：旧页面先淡出再被剔除，
///   新页面淡入，全程透出背景图，切换收尾不再闪跳。
ThemeData backgroundSurfaceTheme(ThemeData base, double veil) {
  final colors = base.colorScheme;
  final veilAlpha = veil.clamp(0.0, 1.0);
  final alpha =
      (veilAlpha * cardSurfaceAlphaScale).clamp(minCardSurfaceAlpha, 1.0);
  Color fade(Color color) => color.withValues(alpha: alpha);
  final surfaces =
      KazumiSurfaces.glass(colors, pageBase: pageVeilBaseColor(base));
  // 按扩展类型覆盖卡片表面样式，其余主题扩展保持不变。
  final extensions = Map<Object, ThemeExtension<dynamic>>.of(base.extensions)
    ..[KazumiSurfaces] = surfaces;
  // 浮层盖在内容之上，保持不透明：M3 下这些主题默认取 surface 家族，
  // 淡化后必须按各自的默认角色还原。
  final panel = colors.surfaceContainer.solidAlpha();
  final sheet = colors.surfaceContainerLow.solidAlpha();
  final dialog = colors.surfaceContainerHigh.solidAlpha();
  final glassTransitions = const FadeForwardsPageTransitionsBuilder(
      backgroundColor: Colors.transparent);

  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: base.appBarTheme.copyWith(
      // 页面遮罩已由 AppSurfaceLayer 全局铺好：标题条下方就是遮罩与背景图，
      // 再叠一层只会多出一条深色带，这里直接透明。
      // 需要遮住滚动内容的悬浮头部自己用 [HeaderScrim]。
      backgroundColor: Colors.transparent,
    ),
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        ...base.pageTransitionsTheme.builders,
        TargetPlatform.android: glassTransitions,
        TargetPlatform.windows: glassTransitions,
      },
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
    dialogTheme: base.dialogTheme.copyWith(backgroundColor: dialog),
    menuTheme: MenuThemeData(
      style: (base.menuTheme.style ?? const MenuStyle()).copyWith(
        backgroundColor: WidgetStatePropertyAll(panel),
      ),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(color: panel),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: (base.dropdownMenuTheme.menuStyle ?? const MenuStyle())
          .copyWith(backgroundColor: WidgetStatePropertyAll(panel)),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(backgroundColor: sheet),
    extensions: extensions.values,
  );
}

/// 玻璃态的反向：把半透明表面恢复为不透明。
///
/// 播放器与图片预览这类全屏页面要靠它退出玻璃效果——画面本身压着背景图，
/// 界面控件再用半透明底色就几乎看不见了。淡化只改 alpha，因此恢复不透明
/// 不会丢失主题配色；非玻璃态原样返回。
ThemeData opaqueSurfaceTheme(ThemeData theme) {
  if (!(theme.extension<KazumiSurfaces>()?.glass ?? false)) return theme;
  // 按扩展类型覆盖卡片表面样式，其余主题扩展保持不变。
  final extensions = Map<Object, ThemeExtension<dynamic>>.of(theme.extensions)
    ..[KazumiSurfaces] = const KazumiSurfaces.solid();
  return theme.copyWith(
    // 玻璃态的 scaffoldBackgroundColor 是透明的，页面实底色存在扩展里。
    scaffoldBackgroundColor: pageVeilBaseColor(theme),
    appBarTheme: theme.appBarTheme.copyWith(
      backgroundColor:
          theme.appBarTheme.backgroundColor?.withValues(alpha: 1),
    ),
    colorScheme: theme.colorScheme.copyWith(
      surfaceContainer: theme.colorScheme.surfaceContainer.solidAlpha(),
      surfaceContainerLow: theme.colorScheme.surfaceContainerLow.solidAlpha(),
      surfaceContainerHigh:
          theme.colorScheme.surfaceContainerHigh.solidAlpha(),
      surfaceContainerHighest:
          theme.colorScheme.surfaceContainerHighest.solidAlpha(),
      primaryContainer: theme.colorScheme.primaryContainer.solidAlpha(),
      secondaryContainer: theme.colorScheme.secondaryContainer.solidAlpha(),
      tertiaryContainer: theme.colorScheme.tertiaryContainer.solidAlpha(),
    ),
    cardTheme: theme.cardTheme.copyWith(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    extensions: extensions.values,
  );
}

extension on Color {
  /// 还原不透明：玻璃态的淡化只改 alpha，RGB 保持不变。
  Color solidAlpha() => withValues(alpha: 1);
}

/// 悬浮头部（吸顶标签栏、固定分组标题）的遮罩。
///
/// 头部下方有内容滚动经过，不能完全透明；但整块铺实色会在半透明页面上留下一条
/// 深色硬边，而页面遮罩之上再叠一层遮罩会更深。玻璃态下改成「顶部实色 → 底部
/// 渐隐」：内容从底部淡出，硬边消失，下半部分仍透出背景图。未启用背景图时行为
/// 与之前一致（铺实色）。
///
/// [fade] 是底部渐隐占头部高度的比例，其余部分为实色。
class HeaderScrim extends StatelessWidget {
  const HeaderScrim({
    super.key,
    required this.child,
    this.fade = 0.6,
    this.strength = 1,
  });

  final Widget child;

  /// 底部渐隐所占比例（0 表示全部实色，1 表示整条渐隐）。
  final double fade;

  /// 遮罩浓度：可随标题栏收起进度淡入淡出（展开时无需遮罩）。
  final double strength;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = theme.extension<KazumiSurfaces>()?.glass ?? false;
    if (!glass || fade >= 1) {
      return ColoredBox(color: theme.scaffoldBackgroundColor, child: child);
    }
    // 玻璃态下 scaffoldBackgroundColor 是透明的，遮罩实底色从扩展里取。
    final solid = pageVeilBaseColor(theme);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            solid.withValues(alpha: strength.clamp(0.0, 1.0)),
            solid.withValues(alpha: 0),
          ],
          stops: [1 - fade.clamp(0.0, 1.0), 1],
        ),
      ),
      child: child,
    );
  }
}

/// 自定义背景图层：铺满整窗，并把整棵路由树换成半透明玻璃表面。
///
/// 挂在 `MaterialApp.builder` 上，位于根 Navigator 之下，结构为
/// 「背景图 → 全局唯一页面遮罩 → 半透明玻璃主题的路由树」：
/// 设置、详情、搜索、磁力等整页都能透出背景图。遮罩全局只铺一层且不随
/// 路由切换重建，页面互相叠放时不会翻倍变暗，切换收尾被盖路由剔除时也
/// 不会亮度跳变（这正是此前设置页等页面闪烁的根源）。播放器等全屏页面
/// 用 [opaqueSurfaceTheme] 退出。
class AppSurfaceLayer extends StatelessWidget {
  const AppSurfaceLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final background = context.watch<BackgroundProvider>();
    if (!background.hasImage) return child;
    final theme = Theme.of(context);
    final veil = backgroundVeilAlpha(background);
    return Stack(
      fit: StackFit.expand,
      children: [
        const AppBackgroundLayer(),
        // 全局唯一遮罩：取主题底色乘遮罩不透明度。页面 Scaffold 全透明，
        // 所有路由共用这一层，遮罩浓度在任意页面、任意切换时刻都恒定。
        ColoredBox(
          color: theme.scaffoldBackgroundColor.withValues(alpha: veil),
        ),
        Theme(
          data: backgroundSurfaceTheme(theme, veil),
          child: child,
        ),
      ],
    );
  }
}

/// 自定义背景图层：铺满父级，按设置绘制图片与毛玻璃（高斯模糊）。
///
/// 未设置背景图时渲染为空；本组件只负责图片本身，遮罩由
/// [AppSurfaceLayer] 统一铺在图片之上。
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
          // 图片解码完成前先垫上遮罩实底色，避免闪白 / 闪黑。
          // 玻璃态下 scaffoldBackgroundColor 已透明，实底色从扩展里取。
          ColoredBox(color: pageVeilBaseColor(Theme.of(context))),
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
