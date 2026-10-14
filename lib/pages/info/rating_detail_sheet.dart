import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';

/// 打开番剧详细评分底部面板：平均分、排名、评分人数与 1~10 分分布明细。
///
/// 调用方需保证 [bangumiItem] 有评分数据（votes > 0），并遵守
/// 详情页「隐藏评分」开关（showRating 为 false 时不应调用）。
Future<void> showRatingDetailSheet(
  BuildContext context, {
  required BangumiItem bangumiItem,
}) {
  return showAdaptiveBottomSheet(
    context: context,
    builder: (context) => RatingDetailSheet(bangumiItem: bangumiItem),
  );
}

class RatingDetailSheet extends StatelessWidget {
  const RatingDetailSheet({super.key, required this.bangumiItem});

  final BangumiItem bangumiItem;

  String get _displayName =>
      bangumiItem.nameCn.isEmpty ? bangumiItem.name : bangumiItem.nameCn;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasRating = bangumiItem.votes > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '评分详情',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (!hasRating)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  '暂无评分',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  bangumiItem.ratingScore.toStringAsFixed(1),
                  style: textTheme.displaySmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RatingBarIndicator(
                        itemCount: 5,
                        rating: bangumiItem.ratingScore / 2,
                        itemBuilder: (context, index) => Icon(
                          Icons.star_rounded,
                          color: colors.primary,
                        ),
                        itemSize: 20.0,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${bangumiItem.votes} 人评分',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              bangumiItem.rank > 0
                  ? 'Bangumi 排名 #${bangumiItem.rank}'
                  : 'Bangumi 排名 未上榜',
              style: textTheme.bodyMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: RatingDistributionChart(bangumiItem: bangumiItem),
            ),
            const SizedBox(height: 16),
            RatingBreakdownList(bangumiItem: bangumiItem),
          ],
        ],
      ),
    );
  }
}

/// 1~10 分评分分布柱状图（详情页卡片与评分详情面板共用）。
class RatingDistributionChart extends StatefulWidget {
  const RatingDistributionChart({super.key, required this.bangumiItem});

  final BangumiItem bangumiItem;

  @override
  State<RatingDistributionChart> createState() =>
      _RatingDistributionChartState();
}

class _RatingDistributionChartState extends State<RatingDistributionChart> {
  int touchedIndex = -1;

  List<int> get _votesCount {
    final votesCount = widget.bangumiItem.votesCount;
    if (votesCount.length >= 10) {
      return votesCount.sublist(0, 10);
    }
    return [
      ...votesCount,
      ...List.filled(10 - votesCount.length, 0),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final votesCount = _votesCount;
    final votes = widget.bangumiItem.votes;

    return BarChart(
      duration: const Duration(milliseconds: 80),
      BarChartData(
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        barTouchData: BarTouchData(
          touchCallback: (FlTouchEvent event, barTouchResponse) {
            setState(() {
              if (!event.isInterestedForInteractions ||
                  barTouchResponse == null ||
                  barTouchResponse.spot == null) {
                touchedIndex = -1;
                return;
              }
              touchedIndex = barTouchResponse.spot!.touchedBarGroupIndex;
            });
          },
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => colors.inverseSurface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final count = votesCount[groupIndex];
              final percentage = votes > 0 ? count / votes * 100 : 0.0;
              return BarTooltipItem(
                '$count 人 (${percentage.toStringAsFixed(2)}%)',
                TextStyle(color: colors.onInverseSurface),
              );
            },
          ),
        ),
        barGroups: List<BarChartGroupData>.generate(
          10,
          (i) => BarChartGroupData(
            x: i + 1,
            barRods: [
              BarChartRodData(
                toY: votesCount[i].toDouble(),
                color: touchedIndex == i
                    ? colors.primary
                    : Theme.of(context).disabledColor,
                width: 20,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(5)),
              )
            ],
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                space: 10,
                child: Text(value.toInt().toString()),
              ),
            ),
          ),
          topTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
        ),
      ),
    );
  }
}

/// 各星级评分人数与占比明细列表（10 星 → 1 星）。
class RatingBreakdownList extends StatelessWidget {
  const RatingBreakdownList({super.key, required this.bangumiItem});

  final BangumiItem bangumiItem;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final votesCount = bangumiItem.votesCount;
    final votes = bangumiItem.votes;
    if (votes <= 0 || votesCount.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxCount = votesCount
        .take(10)
        .fold<int>(0, (max, count) => count > max ? count : max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 10; i >= 1; i--)
          if (i <= votesCount.length)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      '$i 星',
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maxCount > 0
                            ? votesCount[i - 1] / maxCount
                            : 0,
                        minHeight: 10,
                        backgroundColor: colors.surfaceContainerHighest,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(colors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 88,
                    child: Text(
                      '${votesCount[i - 1]} 人 '
                      '${votes > 0 ? (votesCount[i - 1] / votes * 100).toStringAsFixed(1) : '0.0'}%',
                      textAlign: TextAlign.right,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
