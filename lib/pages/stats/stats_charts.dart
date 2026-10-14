part of 'stats_page.dart';

/// 状态对应的主题色（与列表状态角标一致）
Color statusColorOf(ColorScheme colors, CollectType type) => switch (type) {
      CollectType.watching => colors.primary,
      CollectType.planToWatch => colors.tertiary,
      CollectType.watched => colors.secondary,
      CollectType.onHold => colors.surfaceContainerHighest,
      _ => colors.error,
    };

/// 图表线定义：折线颜色与主题色绑定，深浅色自动适配。
class _SeriesSpec {
  const _SeriesSpec(this.label, this.value, this.colorOf);

  final String label;
  final int Function(StatsStatusCounts counts) value;
  final Color Function(ColorScheme colors) colorOf;
}

final _seriesSpecs = <_SeriesSpec>[
  _SeriesSpec('追番数', (counts) => counts.total, (colors) => colors.primary),
  _SeriesSpec('看过', (counts) => counts.watched, (colors) => colors.secondary),
  _SeriesSpec('想看', (counts) => counts.planToWatch, (colors) => colors.tertiary),
  _SeriesSpec('抛弃', (counts) => counts.abandoned, (colors) => colors.error),
];

List<CollectType> get _collectedTypes =>
    CollectType.values.where((type) => type.isCollected).toList();

/// 追番曲线图：总览 / 状态分布 / 评分分布 / 单年各季度 / 历年总览。
class StatsCharts extends StatefulWidget {
  const StatsCharts({
    super.key,
    required this.entries,
  });

  final List<CollectedBangumi> entries;

  @override
  State<StatsCharts> createState() => _StatsChartsState();
}

class _StatsChartsState extends State<StatsCharts> {
  /// 当前选中的年份，null 表示取最近有记录的一年
  int? _year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = groupByAirDate(widget.entries);
    if (groups.isEmpty) {
      return const GeneralEmptyState(
        icon: Icons.event_busy_rounded,
        title: '没有带放送日期的条目，无法生成图表',
      );
    }
    final years = [for (final group in groups) group.year];
    final selected =
        _year != null && years.contains(_year) ? _year! : years.first;
    final selectedGroup = groups.firstWhere((group) => group.year == selected);

    return SingleChildScrollView(
      primary: true,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OverviewChips(entries: widget.entries),
              const SizedBox(height: 28),
              _StatusDonutChart(entries: widget.entries),
              const SizedBox(height: 28),
              _RatingDistributionChart(entries: widget.entries),
              const SizedBox(height: 28),
              Row(
                children: [
                  KazumiMenuButton(
                    builder: (context, toggle) => TextButton.icon(
                      onPressed: toggle,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.expand_more_rounded, size: 20),
                      label: Text(
                        '$selected 年',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    menuChildren: [
                      for (final year in years)
                        KazumiMenuItem(
                          label: '$year 年',
                          selected: year == selected,
                          onPressed: () => setState(() => _year = year),
                        ),
                    ],
                  ),
                  const Spacer(),
                  const _ChartLegend(),
                ],
              ),
              const SizedBox(height: 12),
              _StatusLineChart(
                xLabels: const ['1月', '4月', '7月', '10月'],
                counts: [
                  for (final month in const [1, 4, 7, 10])
                    StatsStatusCounts.of(selectedGroup.quarters
                        .firstWhere(
                          (quarter) => quarter.month == month,
                          orElse: () => const StatsQuarterGroup(
                              year: 0, month: 0, entries: []),
                        )
                        .entries),
                ],
              ),
              const SizedBox(height: 40),
              Text(
                '历年追番曲线',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _StatusLineChart(
                xLabels: [for (final group in groups.reversed) '${group.year}'],
                counts: [
                  for (final group in groups.reversed)
                    StatsStatusCounts.of(
                        group.quarters.expand((quarter) => quarter.entries)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 各状态数量总览
class _OverviewChips extends StatelessWidget {
  const _OverviewChips({required this.entries});

  final List<CollectedBangumi> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(context, '总收藏', entries.length, colors.primary),
        for (final type in _collectedTypes)
          _chip(
            context,
            type.label,
            entries.where((entry) => entry.type == type.value).length,
            statusColorOf(colors, type),
          ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, int count, Color color) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(width: 6),
          Text('$count',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// 状态分布环形图：触摸扇区或点击图例高亮，中心显示对应详情
class _StatusDonutChart extends StatefulWidget {
  const _StatusDonutChart({required this.entries});

  final List<CollectedBangumi> entries;

  @override
  State<_StatusDonutChart> createState() => _StatusDonutChartState();
}

class _StatusDonutChartState extends State<_StatusDonutChart> {
  int _touchedIndex = -1;

  void _select(int index) => setState(() {
        _touchedIndex = _touchedIndex == index ? -1 : index;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = <CollectType, int>{
      for (final type in _collectedTypes)
        type: widget.entries.where((entry) => entry.type == type.value).length,
    };
    final visibleTypes = [
      for (final type in _collectedTypes)
        if (counts[type]! > 0) type,
    ];
    final total = widget.entries.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '状态分布',
          style:
              theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 190,
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: _Donut(
                  visibleTypes: visibleTypes,
                  counts: counts,
                  total: total,
                  touchedIndex: _touchedIndex,
                  onSelect: _select,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 4,
                child: _DonutLegend(
                  visibleTypes: visibleTypes,
                  counts: counts,
                  total: total,
                  touchedIndex: _touchedIndex,
                  onSelect: _select,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Donut extends StatelessWidget {
  const _Donut({
    required this.visibleTypes,
    required this.counts,
    required this.total,
    required this.touchedIndex,
    required this.onSelect,
  });

  final List<CollectType> visibleTypes;
  final Map<CollectType, int> counts;
  final int total;
  final int touchedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final touchedType = touchedIndex >= 0 ? visibleTypes[touchedIndex] : null;
    final touchedCount = touchedType == null ? 0 : counts[touchedType]!;
    final percentage = total > 0 && touchedType != null
        ? (touchedCount / total * 100).toStringAsFixed(0)
        : '0';

    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: PieChart(
            duration: const Duration(milliseconds: 200),
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 46,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions &&
                      response?.touchedSection == null) {
                    if (touchedIndex != -1) onSelect(-1);
                    return;
                  }
                  final index =
                      response?.touchedSection?.touchedSectionIndex ?? -1;
                  if (index != touchedIndex) onSelect(index);
                },
              ),
              sections: [
                for (var i = 0; i < visibleTypes.length; i++)
                  PieChartSectionData(
                    value: counts[visibleTypes[i]]!.toDouble(),
                    color: statusColorOf(colors, visibleTypes[i]),
                    radius: i == touchedIndex ? 30 : 26,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                touchedType == null ? '$total' : '$touchedCount',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                touchedType == null
                    ? '总收藏'
                    : '${touchedType.label} · $percentage%',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutLegend extends StatelessWidget {
  const _DonutLegend({
    required this.visibleTypes,
    required this.counts,
    required this.total,
    required this.touchedIndex,
    required this.onSelect,
  });

  final List<CollectType> visibleTypes;
  final Map<CollectType, int> counts;
  final int total;
  final int touchedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < visibleTypes.length; i++)
          _row(context, i, visibleTypes[i]),
      ],
    );
  }

  Widget _row(BuildContext context, int index, CollectType type) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final count = counts[type]!;
    final highlighted = touchedIndex == index;
    return InkWell(
      onTap: () => onSelect(index),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: statusColorOf(colors, type),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                type.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: highlighted ? FontWeight.w700 : null,
                ),
              ),
            ),
            Text(
              '$count',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 4),
            Text(
              '${total > 0 ? (count / total * 100).toStringAsFixed(0) : 0}%',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 收藏番剧的 Bangumi 评分分布柱状图
class _RatingDistributionChart extends StatelessWidget {
  const _RatingDistributionChart({required this.entries});

  final List<CollectedBangumi> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final axisStyle = theme.textTheme.bodySmall
        ?.copyWith(color: colors.onSurfaceVariant);
    final dist = RatingDistribution.of(entries);
    final maxCount = dist.buckets.reduce((a, b) => a > b ? a : b);
    final maxY = (maxCount + 1).clamp(4, double.infinity).toDouble();
    final leftInterval = (maxY / 4).ceilToDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '评分分布',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Text(
              dist.ratedCount > 0
                  ? '平均 ${dist.averageScore.toStringAsFixed(1)} 分 · ${dist.ratedCount} 部已评分'
                  : '暂无评分数据',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 1.8,
          child: BarChart(
            duration: const Duration(milliseconds: 200),
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: colors.outlineVariant.withValues(alpha: 0.4),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: leftInterval,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      space: 8,
                      child: Text(value.toInt().toString(), style: axisStyle),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      space: 8,
                      child: Text(
                        RatingDistribution
                            .bucketLabels[value.toInt().clamp(
                                0, RatingDistribution.bucketLabels.length - 1)],
                        style: axisStyle,
                      ),
                    ),
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => colors.inverseSurface,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                      rod.toY <= 0
                          ? null
                          : BarTooltipItem(
                              '${RatingDistribution.bucketLabels[groupIndex.clamp(0, RatingDistribution.bucketLabels.length - 1)]} '
                              '${rod.toY.toInt()} 部',
                              TextStyle(
                                color: colors.onInverseSurface,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < dist.buckets.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: dist.buckets[i].toDouble(),
                        width: 20,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                        color: colors.primary.withValues(alpha: 0.85),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = theme.textTheme.labelSmall
        ?.copyWith(color: colors.onSurfaceVariant);
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final spec in _seriesSpecs)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: spec.colorOf(colors),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(spec.label, style: style),
            ],
          ),
      ],
    );
  }
}

class _StatusLineChart extends StatelessWidget {
  const _StatusLineChart({
    required this.xLabels,
    required this.counts,
  });

  /// x 轴标签与计数一一对应
  final List<String> xLabels;
  final List<StatsStatusCounts> counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final axisStyle = theme.textTheme.bodySmall
        ?.copyWith(color: colors.onSurfaceVariant);
    return AspectRatio(
      aspectRatio: 1.6,
      child: LineChart(
        duration: const Duration(milliseconds: 200),
        LineChartData(
          minY: 0,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: colors.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  space: 8,
                  child: Text(value.toInt().toString(), style: axisStyle),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  space: 8,
                  child: Text(
                    xLabels[value.toInt().clamp(0, xLabels.length - 1)],
                    style: axisStyle,
                  ),
                ),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => colors.inverseSurface,
              getTooltipItems: (spots) => [
                for (final spot in spots)
                  LineTooltipItem(
                    '${xLabels[spot.x.toInt()]} '
                    '${_seriesSpecs[spot.barIndex].label} ${spot.y.toInt()}',
                    TextStyle(
                      color: colors.onInverseSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            for (final spec in _seriesSpecs)
              LineChartBarData(
                spots: [
                  for (var i = 0; i < counts.length; i++)
                    FlSpot(i.toDouble(), spec.value(counts[i]).toDouble()),
                ],
                isCurved: true,
                barWidth: 2.5,
                color: spec.colorOf(colors),
                dotData: const FlDotData(show: true),
              ),
          ],
        ),
      ),
    );
  }
}
