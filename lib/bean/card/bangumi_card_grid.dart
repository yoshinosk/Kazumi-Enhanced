import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';

/// 番剧卡片封面的宽高比（宽 / 高）。
const double bangumiCardCoverRatio = 0.65;

/// 番剧卡片网格的视图大小档位（追番统计 / 季度补标共用）。
///
/// [large] 为兼容旧版的默认档：竖屏固定 3 列、字号与列数上限均与历史版本
/// 一致；[medium] / [small] 逐级增加列数并缩小卡片文字，单屏可容纳更多条目。
enum BangumiCardViewSize {
  large('大视图'),
  medium('中视图'),
  small('小视图');

  const BangumiCardViewSize(this.label);

  final String label;

  static BangumiCardViewSize fromName(String? name) =>
      BangumiCardViewSize.values.firstWhere(
        (size) => size.name == name,
        orElse: () => BangumiCardViewSize.large,
      );

  /// 竖屏下的固定列数。
  int get portraitColumns => switch (this) {
        BangumiCardViewSize.large => 3,
        BangumiCardViewSize.medium => 4,
        BangumiCardViewSize.small => 5,
      };

  /// 横屏 / 桌面端单列的最小宽度基准；[narrow] 为窄窗口（内容宽 < 600）。
  double minWidth(bool narrow) => switch (this) {
        BangumiCardViewSize.large => narrow ? 136.0 : 172.0,
        BangumiCardViewSize.medium => narrow ? 104.0 : 128.0,
        BangumiCardViewSize.small => narrow ? 84.0 : 100.0,
      };

  /// 横屏 / 桌面端的最大列数上限。
  int get maxColumns => switch (this) {
        BangumiCardViewSize.large => 6,
        BangumiCardViewSize.medium => 9,
        BangumiCardViewSize.small => 12,
      };

  /// 卡片标题字号（两行）。
  double get titleFontSize => switch (this) {
        BangumiCardViewSize.large => 13,
        BangumiCardViewSize.medium => 12,
        BangumiCardViewSize.small => 11,
      };

  /// 卡片状态行字号（单行）。
  double get statusFontSize => switch (this) {
        BangumiCardViewSize.large => 11,
        BangumiCardViewSize.medium => 10,
        BangumiCardViewSize.small => 10,
      };
}

/// 一次番剧卡片网格布局计算的结果。
class BangumiCardGridLayout {
  const BangumiCardGridLayout._({
    required this.columns,
    required this.spacing,
    required this.mainAxisSpacing,
    required this.cardWidth,
    required this.cardExtent,
  });

  /// 列数
  final int columns;

  /// 水平间距
  final double spacing;

  /// 垂直间距
  final double mainAxisSpacing;

  /// 单张卡片宽度
  final double cardWidth;

  /// 单张卡片总高度（封面 + 文字区），供 `mainAxisExtent` 使用
  final double cardExtent;

  /// 按内容宽度与视图档位计算网格布局。
  ///
  /// large 档的结果与历史版本的行内计算完全一致；其余档位按各自
  /// 的最小宽度 / 列数上限推导。
  static BangumiCardGridLayout compute({
    required double contentWidth,
    required bool portrait,
    required TextScaler scaler,
    required BangumiCardViewSize size,
  }) {
    final spacing = portrait ? (contentWidth < 600 ? 8.0 : 12.0) : 16.0;
    final textScale = (scaler.scale(14) / 14).clamp(1.0, double.infinity);
    final minWidth =
        size.minWidth(contentWidth < 600) + 32 * (textScale - 1);
    final columns = portrait
        ? size.portraitColumns
        : ((contentWidth + spacing) / (minWidth + spacing))
            .floor()
            .clamp(1, size.maxColumns);
    final cardWidth = (contentWidth - spacing * (columns - 1)) / columns;
    final titleHeight =
        (scaler.scale(size.titleFontSize) * 2.7).ceilToDouble();
    final statusHeight =
        (scaler.scale(size.statusFontSize) * 1.4).ceilToDouble();
    final cardExtent = cardWidth / bangumiCardCoverRatio +
        8 +
        titleHeight +
        4 +
        statusHeight +
        8;
    return BangumiCardGridLayout._(
      columns: columns,
      spacing: spacing,
      mainAxisSpacing: portrait ? 12 : spacing,
      cardWidth: cardWidth,
      cardExtent: cardExtent,
    );
  }
}

/// 视图大小选择菜单（追番统计 / 季度补标的 AppBar 共用）。
class BangumiCardViewSizeMenu extends StatelessWidget {
  const BangumiCardViewSizeMenu({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final BangumiCardViewSize value;
  final ValueChanged<BangumiCardViewSize> onChanged;

  @override
  Widget build(BuildContext context) {
    return KazumiMenuButton(
      builder: (context, toggle) => IconButton(
        tooltip: '视图大小',
        icon: const Icon(Icons.photo_size_select_large_rounded),
        onPressed: toggle,
      ),
      menuChildren: [
        for (final size in BangumiCardViewSize.values)
          KazumiMenuItem(
            label: size.label,
            selected: size == value,
            onPressed: () => onChanged(size),
          ),
      ],
    );
  }
}
