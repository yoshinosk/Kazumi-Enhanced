import 'package:flutter/material.dart';

/// 半透明卡片底色在页面遮罩基础上的额外衰减：卡片比页面更透，
/// 背景图在卡片内更明显，层次更清楚；它同时是卡片底色的上限。
const double cardSurfaceAlphaScale = 0.32;

/// 半透明卡片底色的下限，避免「背景不透明度」调得很低时文字读不清。
const double minCardSurfaceAlpha = 0.18;

/// 卡片描边样式的唯一来源。
///
/// 底色本身由主题色板的 surfaceContainer 等角色提供（半透明底色见
/// `backgroundSurfaceTheme`），这里只额外描述描边：主界面启用自定义背景图后，
/// 卡片底色变半透明，若不补一层描边，相邻卡片与背景图会糊在一起。
@immutable
class KazumiSurfaces extends ThemeExtension<KazumiSurfaces> {
  const KazumiSurfaces({required this.cardOutline});

  /// 未启用背景图：描边关闭，视觉与引入本扩展前完全一致。
  const KazumiSurfaces.solid() : cardOutline = BorderSide.none;

  /// 启用背景图：卡片补一层细描边，从背景图里浮起来。
  ///
  /// 深浅主题都用 `onSurface` 压低透明度，描边在两种主题下都只比底色略深一点。
  factory KazumiSurfaces.glass(ColorScheme colors) => KazumiSurfaces(
        cardOutline:
            BorderSide(color: colors.onSurface.withValues(alpha: 0.14)),
      );

  /// 卡片描边；[BorderSide.none] 表示不描边。
  final BorderSide cardOutline;

  @override
  KazumiSurfaces copyWith({BorderSide? cardOutline}) => KazumiSurfaces(
        cardOutline: cardOutline ?? this.cardOutline,
      );

  @override
  KazumiSurfaces lerp(covariant KazumiSurfaces? other, double t) {
    if (other == null) return this;
    return KazumiSurfaces(
      cardOutline: BorderSide.lerp(cardOutline, other.cardOutline, t),
    );
  }
}

extension KazumiSurfaceTheme on BuildContext {
  /// 当前生效的卡片表面样式；主题未注册扩展时视为不描边。
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
