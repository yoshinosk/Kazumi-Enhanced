import 'package:flutter/material.dart';

/// 一个顶部标签胶囊的数据。
class TabPillItem {
  const TabPillItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 标题栏内由 [TabController] 驱动的分类胶囊栏。
///
/// 与默认 [TabBar] 等分整行宽度不同，胶囊按内容自适应宽度横向排列，
/// 宽窗口下不会把标签拉伸得又宽又空；选中项以色调填充的圆角胶囊
/// 高亮。空间不足时可横向滚动，不会挤压换行。
class TabPillBar extends StatelessWidget {
  const TabPillBar({super.key, required this.controller, required this.items});

  final TabController controller;
  final List<TabPillItem> items;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final (index, item) in items.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _TabPill(
                    item: item,
                    selected: controller.index == index,
                    onTap: () => controller.animateTo(index),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final TabPillItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: selected
          ? theme.colorScheme.secondaryContainer
          : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? item.selectedIcon : item.icon,
                size: 20,
                color: foreground,
              ),
              const SizedBox(width: 8),
              Text(
                item.label,
                maxLines: 1,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
