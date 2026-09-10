part of 'collect_library_view.dart';

class _CollectLibraryCard extends StatelessWidget {
  const _CollectLibraryCard({
    super.key,
    required this.entry,
    required this.onOpen,
    required this.onChangeType,
    this.localCount = 0,
    this.cacheCount = 0,
  });

  final CollectedBangumi entry;
  final VoidCallback onOpen;
  final ValueChanged<CollectType>? onChangeType;
  final int localCount;
  final int cacheCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final item = entry.bangumiItem;
    final title = CollectLibraryQuery.titleOf(entry);
    final type = CollectType.fromValue(entry.type);
    final airDate = DateTime.tryParse(item.airDate);
    final metadata = [
      if (airDate != null) '${airDate.year} 年',
      if (item.ratingScore > 0) '${item.ratingScore.toStringAsFixed(1)} 分',
    ];
    final badges = <Widget>[
      if (localCount > 0)
        _AvailabilityBadge(
          text: '本地$localCount',
          color: colors.primary,
          foreground: colors.onPrimary,
        ),
      if (cacheCount > 0)
        _AvailabilityBadge(
          text: '缓存$cacheCount',
          color: colors.tertiary,
          foreground: colors.onTertiary,
        ),
    ];

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Keep the menu outside the card's focus and pointer subtree.
          Positioned.fill(
            child: Semantics(
              button: true,
              label: [title, ...metadata].join('，'),
              child: InkWell(onTap: onOpen),
            ),
          ),
          if (badges.isNotEmpty)
            Positioned(
              left: 12,
              top: 12,
              child: Row(mainAxisSize: MainAxisSize.min, children: badges),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: Hero(
                      tag: item.id,
                      transitionOnUserGestures: true,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: NetworkImgLayer(
                          src: item.images['large'] ??
                              item.images['common'] ??
                              '',
                          width: 80,
                          height: 120,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: IgnorePointer(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 76),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                                  ),
                                  if (metadata.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        metadata.join('  ·  '),
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      _statusMenu(context, type, title),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusMenu(BuildContext context, CollectType type, String title) {
    final colors = Theme.of(context).colorScheme;
    const itemStyle = ButtonStyle(
      visualDensity: VisualDensity.standard,
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
      minimumSize: WidgetStatePropertyAll(Size(192, 48)),
    );

    return MenuAnchor(
      consumeOutsideTap: true,
      style: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      menuChildren: [
        for (final status
            in CollectType.values.where((type) => type.isCollected))
          MenuItemButton(
            style: itemStyle,
            trailingIcon:
                status == type ? const Icon(Icons.check_rounded) : null,
            onPressed: onChangeType == null || status == type
                ? null
                : () => onChangeType!(status),
            child: Text(status.label),
          ),
        const Divider(indent: 16, endIndent: 16),
        MenuItemButton(
          style: itemStyle,
          onPressed: onChangeType == null
              ? null
              : () => onChangeType!(CollectType.none),
          child: Text('取消收藏', style: TextStyle(color: colors.error)),
        ),
      ],
      builder: (context, controller, child) => Tooltip(
        message: '调整《$title》的观看状态',
        child: FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 0),
          ),
          onPressed: onChangeType == null
              ? null
              : () =>
                  controller.isOpen ? controller.close() : controller.open(),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          label: Text(type.label),
        ),
      ),
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({
    required this.text,
    required this.color,
    required this.foreground,
  });

  final String text;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
      ),
    );
  }
}