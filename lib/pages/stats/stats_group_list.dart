part of 'stats_page.dart';

/// 按年份 → 季度归档的收藏列表。
class StatsGroupList extends StatelessWidget {
  const StatsGroupList({
    super.key,
    required this.entries,
    required this.undatedCount,
    required this.onOpen,
    required this.onMarkSeason,
  });

  final List<CollectedBangumi> entries;
  final int undatedCount;
  final ValueChanged<BangumiItem> onOpen;

  /// 跳转到对应年份 / 季度的补标页
  final void Function(int year, int month) onMarkSeason;

  @override
  Widget build(BuildContext context) {
    final groups = groupByAirDate(entries);
    if (groups.isEmpty) {
      return const GeneralEmptyState(
        icon: Icons.event_busy_rounded,
        title: '没有带放送日期的条目，无法按季度归档',
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      const inset = 16.0;
      final contentWidth = constraints.maxWidth - inset * 2;
      return CustomScrollView(
        primary: true,
        slivers: [
          if (undatedCount > 0)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(inset, 12, inset, 0),
              sliver: SliverToBoxAdapter(child: _UndatedBanner(count: undatedCount)),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(inset, 0, inset, 24),
            sliver: SliverMainAxisGroup(
              slivers: [
                for (final yearGroup in groups) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: '${yearGroup.year} 年',
                      count: yearGroup.total,
                      isYear: true,
                    ),
                  ),
                  for (final quarter in yearGroup.quarters) ...[
                    SliverToBoxAdapter(
                      child: _SectionHeader(
                        title: '${quarter.month} 月新番',
                        count: quarter.entries.length,
                        trailing: IconButton(
                          tooltip: '补标 ${quarter.year} 年 ${quarter.month} 月新番',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.playlist_add_check_rounded,
                              size: 20),
                          onPressed: () => onMarkSeason(
                              quarter.year, quarter.month),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                      sliver: _grid(quarter.entries, contentWidth),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _grid(List<CollectedBangumi> entries, double contentWidth) {
    return Builder(builder: (context) {
      final portrait =
          MediaQuery.orientationOf(context) == Orientation.portrait;
      final spacing = portrait ? (contentWidth < 600 ? 8.0 : 12.0) : 16.0;
      final scaler = MediaQuery.textScalerOf(context);
      final textScale = (scaler.scale(14) / 14).clamp(1.0, double.infinity);
      final minWidth =
          (contentWidth < 600 ? 136.0 : 172.0) + 32 * (textScale - 1);
      final columns = portrait
          ? 3
          : ((contentWidth + spacing) / (minWidth + spacing)).floor().clamp(1, 6);
      final width = (contentWidth - spacing * (columns - 1)) / columns;
      return SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: portrait ? 12 : spacing,
          mainAxisExtent: _StatsCard.extent(width, scaler),
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) => _StatsCard(
          key: ValueKey('stats-${entries[index].bangumiItem.id}'),
          entry: entries[index],
          onOpen: () => onOpen(entries[index].bangumiItem),
        ),
      );
    });
  }
}

class _UndatedBanner extends StatelessWidget {
  const _UndatedBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      shape: cardShape(context, 16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: 18, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '有 $count 部条目没有放送日期，未计入季度归档',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    this.isYear = false,
    this.trailing,
  });

  final String title;
  final int count;
  final bool isYear;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(
          top: isYear ? 20 : 14, bottom: isYear ? 2 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: (isYear
                    ? theme.textTheme.titleLarge
                    : theme.textTheme.titleMedium)
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(
            '$count 部',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    super.key,
    required this.entry,
    required this.onOpen,
  });

  final CollectedBangumi entry;
  final VoidCallback onOpen;

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
    final item = entry.bangumiItem;
    final title = CollectLibraryQuery.titleOf(entry);
    final type = CollectType.fromValue(entry.type);
    final titleHeight = (scaler.scale(13) * 2.7).ceilToDouble();
    final statusHeight = (scaler.scale(11) * 1.4).ceilToDouble();

    return Material(
      color: colors.surfaceContainerLow,
      shape: cardShape(context, 16),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: '$title，${type.label}',
        child: InkWell(
          onTap: onOpen,
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
                      Positioned(
                        left: 6,
                        top: 6,
                        child: _StatusChip(type: type),
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
                    SizedBox(height: statusHeight, child: _statusLine(theme)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusLine(ThemeData theme) {
    final item = entry.bangumiItem;
    final type = CollectType.fromValue(entry.type);
    final hasRating = item.ratingScore > 0;
    final style = theme.textTheme.bodySmall?.copyWith(
      fontSize: 11,
      height: 1.4,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        Text(type.label, style: style),
        const Spacer(),
        if (hasRating) Text('${item.ratingScore.toStringAsFixed(1)} 分', style: style),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.type});

  final CollectType type;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (Color background, Color foreground) = switch (type) {
      CollectType.watching => (colors.primary, colors.onPrimary),
      CollectType.planToWatch => (colors.tertiary, colors.onTertiary),
      CollectType.watched => (colors.secondary, colors.onSecondary),
      CollectType.onHold => (
          colors.surfaceContainerHighest,
          colors.onSurface
        ),
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
