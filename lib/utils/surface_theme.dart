import 'package:flutter/material.dart';

/// 半透明卡片底色在页面遮罩基础上的额外衰减：卡片比页面更透，
/// 背景图在卡片内更明显，层次更清楚；它同时是卡片底色的上限。
const double cardSurfaceAlphaScale = 0.32;

/// 半透明卡片底色的下限，避免「背景不透明度」调得很低时文字读不清。
const double minCardSurfaceAlpha = 0.18;

/// 卡片描边样式的唯一来源。
///
/// 底色本身由主题色板的 surfaceContainer 等角色提供（半透明底色见
/// `backgroundSurfaceTheme`），这里只额外描述描边：启用自定义背景图后，
/// 卡片底色变半透明，若不补一层描边，相邻卡片与背景图会糊在一起。
@immutable
class KazumiSurfaces extends ThemeExtension<KazumiSurfaces> {
  const KazumiSurfaces({
    required this.glass,
    required this.cardOutline,
  });

  /// 未启用背景图：表面不透明、不描边，视觉与引入本扩展前完全一致。
  const KazumiSurfaces.solid()
      : glass = false,
        cardOutline = BorderSide.none;

  /// 启用背景图：表面半透明，卡片补一层细描边，从背景图里浮起来。
  ///
  /// 深浅主题都用 `onSurface` 压低透明度，描边在两种主题下都只比底色略深一点。
  factory KazumiSurfaces.glass(ColorScheme colors) => KazumiSurfaces(
        glass: true,
        cardOutline:
            BorderSide(color: colors.onSurface.withValues(alpha: 0.14)),
      );

  /// 表面是否为玻璃态（半透明底色 + 卡片描边）。
  final bool glass;

  /// 卡片描边；[BorderSide.none] 表示不描边。
  final BorderSide cardOutline;

  @override
  KazumiSurfaces copyWith({bool? glass, BorderSide? cardOutline}) =>
      KazumiSurfaces(
        glass: glass ?? this.glass,
        cardOutline: cardOutline ?? this.cardOutline,
      );

  @override
  KazumiSurfaces lerp(covariant KazumiSurfaces? other, double t) {
    if (other == null) return this;
    return KazumiSurfaces(
      glass: t < 0.5 ? glass : other.glass,
      cardOutline: BorderSide.lerp(cardOutline, other.cardOutline, t),
    );
  }
}

extension KazumiSurfaceTheme on BuildContext {
  /// 当前生效的卡片表面样式；主题未注册扩展时视为不透明且不描边。
  KazumiSurfaces get surfaces =>
      Theme.of(this).extension<KazumiSurfaces>() ??
      const KazumiSurfaces.solid();
}

/// 卡片形状：圆角半径仍由各卡片自己决定，描边跟随 [KazumiSurfaces]。
///
/// 给 `Card.shape` / `Material.shape` 用，注意 Material 不允许同时传
/// `borderRadius` 与 `shape`，要替换而不是追加。
ShapeBorder cardShape(BuildContext context, double radius) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: context.surfaces.cardOutline,
    );

/// 模态浮层（弹窗、菜单）用的不透明底色。
///
/// 玻璃态下 surface 家族被淡化，而浮层是叠在页面之上的，长文本与输入框
/// 需要足够的对比度。淡化只改 alpha、不动 RGB，所以这里把 alpha 还原即可，
/// 未启用背景图时该调用是空操作。
Color modalSurfaceColor(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: 1);
