part of 'season_mark_page.dart';

/// 补标页网格卡片：非多选时点按弹出状态菜单，多选时点按勾选。
class _MarkCard extends StatelessWidget {
  const _MarkCard({
    super.key,
    required this.item,
    required this.collectType,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMark,
    required this.onOpenDetails,
  });

  final BangumiItem item;

  /// 当前收藏状态（0 = 未收藏）
  final int collectType;
  final bool selecting;
  final bool selected;

  /// 多选模式下的点按（切换勾选）
  final VoidCallback onTap;

  /// 进入多选模式
  final VoidCallback onLongPress;

  /// 打标 / 取消收藏（type 0）
  final ValueChanged<int> onMark;
  final VoidCallback onOpenDetails;

  static const _coverRatio = 0.65;

  static double extent(double width, TextScaler scaler) {
    final titleHeight = (scaler.scale(13) * 2.7).ceilToDouble();
    final statusHeight = (scaler.scale(11) * 1.4).ceilToDouble();
    return width / _coverRatio + 8 + titleHeight + 4 + statusHeight + 8;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final title = item.nameCn.trim().isNotEmpty ? item.nameCn : item.name;
    final type = CollectType.fromValue(collectType);
    final titleHeight = (scaler.scale(13) * 2.7).ceilToDouble();
    final statusHeight = (scaler.scale(11) * 1.4).ceilToDouble();

    final menuChildren = [
      for (final status
          in CollectType.values.where((status) => status.isCollected))
        MenuItemButton(
          leadingIcon: status == type
              ? const Icon(Icons.check_rounded)
              : null,
          onPressed: status == type ? null : () => onMark(status.value),
          child: Text(status.label),
        ),
      if (type.isCollected) ...[
        const Divider(indent: 16, endIndent: 16),
        MenuItemButton(
          onPressed: () => onMark(0),
          child: Text('取消收藏', style: TextStyle(color: colors.error)),
        ),
      ],
      MenuItemButton(
        leadingIcon: const Icon(Icons.info_outline_rounded, size: 18),
        onPressed: onOpenDetails,
        child: const Text('查看详情'),
      ),
    ];

    return MenuAnchor(
      consumeOutsideTap: true,
      menuChildren: menuChildren,
      builder: (context, menuController, _) {
        return Material(
          color: colors.surfaceContainerLow,
          shape: cardShape(context, 16),
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            button: true,
            label: '$title，${type.isCollected ? type.label : '未标记'}',
            child: InkWell(
              onTap: selecting
                  ? onTap
                  : () => menuController.isOpen
                      ? menuController.close()
                      : menuController.open(),
              onLongPress: onLongPress,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child: AspectRatio(
                      aspectRatio: _coverRatio,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: LayoutBuilder(
                              builder: (context, constraints) => Hero(
                                tag: item.id,
                                transitionOnUserGestures: true,
                                flightShuttleBuilder:
                                    NetworkImgLayer.heroFlightShuttleBuilder,
                                child: NetworkImgLayer(
                                  src: item.images['large'] ??
                                      item.images['common'] ??
                                      '',
                                  width: constraints.maxWidth,
                                  height: constraints.maxHeight,
                                ),
                              ),
                            ),
                          ),
                          if (type.isCollected && !selecting)
                            Positioned(
                              left: 6,
                              top: 6,
                              child: _MarkStatusChip(type: type),
                            ),
                          if (selecting)
                            Positioned.fill(
                              child: Container(
                                color: selected
                                    ? colors.primary.withValues(alpha: 0.35)
                                    : Colors.transparent,
                              ),
                            ),
                          if (selecting)
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                size: 24,
                                color: selected
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                                shadows: const [
                                  Shadow(
                                      blurRadius: 4,
                                      color: Colors.black38,
                                      offset: Offset(0, 1)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: SizedBox(
                            height: titleHeight,
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 13,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: statusHeight,
                          child: Row(
                            children: [
                              Text(
                                type.isCollected ? type.label : '未标记',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  height: 1.4,
                                  color: type.isCollected
                                      ? colors.primary
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              if (item.ratingScore > 0)
                                Text(
                                  item.ratingScore.toStringAsFixed(1),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    height: 1.4,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MarkStatusChip extends StatelessWidget {
  const _MarkStatusChip({required this.type});

  final CollectType type;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (Color background, Color foreground) = switch (type) {
      CollectType.watching => (colors.primary, colors.onPrimary),
      CollectType.planToWatch => (colors.tertiary, colors.onTertiary),
      CollectType.watched => (colors.secondary, colors.onSecondary),
      CollectType.onHold => (colors.surfaceContainerHighest, colors.onSurface),
      _ => (colors.errorContainer, colors.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        type.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
      ),
    );
  }
}
