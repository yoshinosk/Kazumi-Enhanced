part of 'stats_page.dart';

/// 图表线定义：折线颜色与主题色绑定，深浅色自动适配。
class _SeriesSpec {
  const _SeriesSpec(this.label, this.value, this.colorOf);

  final String label;
  final int Function(StatsStatusCounts counts) value;
  final Color Function(ColorScheme colors) colorOf;
}

final _seriesSpecs = <_SeriesSpec>[
  _SeriesSpec('追番数', (counts) => counts.total, (colors) => colors.primary),
  _SeriesSpec('看过', (counts) => counts.watched, (colors) => colors.tertiary),
  _SeriesSpec('想看', (counts) => counts.planToWatch, (colors) => colors.secondary),
  _SeriesSpec('抛弃', (counts) => counts.abandoned, (colors) => colors.error),
];

/// 追番曲线图：单年各季度 + 历年总览。
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
