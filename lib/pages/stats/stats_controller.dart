import 'dart:async';

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:mobx/mobx.dart';

part 'stats_controller.g.dart';

/// 组内排序方式
enum StatsSortOrder {
  score('评分优先'),
  collectTime('收藏时间'),
  title('标题');

  const StatsSortOrder(this.label);

  final String label;
}

class StatsController = _StatsController with _$StatsController;

abstract class _StatsController with Store {
  _StatsController(this._collectCrudRepository, this._collectController);

  final ICollectCrudRepository _collectCrudRepository;
  final CollectController _collectController;

  StreamSubscription<void>? _changesSubscription;
  Timer? _reloadDebounce;

  @observable
  ObservableList<CollectedBangumi> collectibles =
      ObservableList<CollectedBangumi>();

  /// 没有放送日期、无法归档到季度的条目数
  @observable
  int undatedCount = 0;

  /// 是否处于多选模式
  @observable
  bool selecting = false;

  /// 多选模式下已勾选的番剧 id
  @observable
  ObservableSet<int> selectedIds = ObservableSet<int>();

  /// 状态筛选，0 表示全部
  @observable
  int statusFilter = 0;

  /// 组内排序方式
  @observable
  StatsSortOrder sortOrder = StatsSortOrder.score;

  /// 页面存活期间订阅收藏写入（含导入 / 补标 / 同步回写），保持统计实时。
  /// 批量写入会连续触发变更，做 200ms 防抖只重载一次。
  void startListening() {
    _changesSubscription ??= _collectCrudRepository.changes.listen((_) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 200), load);
    });
  }

  void stopListening() {
    _changesSubscription?.cancel();
    _changesSubscription = null;
    _reloadDebounce?.cancel();
    _reloadDebounce = null;
  }

  @action
  void load() {
    final entries = _collectCrudRepository.getAllCollectibles();
    collectibles
      ..clear()
      ..addAll(entries);
    undatedCount = entries.where((entry) => _airDateOf(entry) == null).length;
  }

  @action
  void enterSelection() => selecting = true;

  @action
  void leaveSelection() {
    selecting = false;
    selectedIds.clear();
  }

  @action
  void toggleSelect(int id) {
    if (!selectedIds.add(id)) selectedIds.remove(id);
  }

  /// 全选 / 取消全选 [visibleEntries]（当前筛选下可见的条目）
  @action
  void toggleSelectAll(List<CollectedBangumi> visibleEntries) {
    final allSelected = visibleEntries.isNotEmpty &&
        visibleEntries.every(
            (entry) => selectedIds.contains(entry.bangumiItem.id));
    if (allSelected) {
      for (final entry in visibleEntries) {
        selectedIds.remove(entry.bangumiItem.id);
      }
    } else {
      selectedIds
          .addAll([for (final entry in visibleEntries) entry.bangumiItem.id]);
    }
  }

  @action
  void setStatusFilter(int value) => statusFilter = value;

  @action
  void setSortOrder(StatsSortOrder order) => sortOrder = order;

  /// 按状态筛选后的条目
  List<CollectedBangumi> filteredEntries() {
    final filter = statusFilter;
    if (filter == 0) return collectibles.toList();
    return collectibles.where((entry) => entry.type == filter).toList();
  }

  /// 已勾选条目对应的番剧信息（按收藏列表顺序）
  List<BangumiItem> selectedItems() => [
        for (final entry in collectibles)
          if (selectedIds.contains(entry.bangumiItem.id)) entry.bangumiItem,
      ];

  /// 批量打标，返回写入结果摘要
  Future<CollectImportSummary> bulkMark(
          List<BangumiItem> items, CollectType type) =>
      _collectController.bulkSetCollect(items, type.value);

  /// 批量删除收藏，返回（成功删除数, 失败数）
  Future<({int deleted, int failed})> bulkDelete(List<BangumiItem> items) =>
      _collectController.bulkDeleteCollect(items);
}

/// 某季度的计数（总数/看过/想看/抛弃）。
///
/// 总数包含全部收藏状态；「在看」「搁置」不在图表线里，只计入总数。
class StatsStatusCounts {
  const StatsStatusCounts({
    required this.total,
    required this.watched,
    required this.planToWatch,
    required this.abandoned,
  });

  final int total;
  final int watched;
  final int planToWatch;
  final int abandoned;

  static StatsStatusCounts of(Iterable<CollectedBangumi> entries) {
    var total = 0;
    var watched = 0;
    var planToWatch = 0;
    var abandoned = 0;
    for (final entry in entries) {
      total++;
      switch (entry.type) {
        case 4:
          watched++;
        case 2:
          planToWatch++;
        case 5:
          abandoned++;
      }
    }
    return StatsStatusCounts(
      total: total,
      watched: watched,
      planToWatch: planToWatch,
      abandoned: abandoned,
    );
  }
}

/// 收藏条目的 Bangumi 评分分布（按分桶统计）
class RatingDistribution {
  const RatingDistribution({
    required this.buckets,
    required this.averageScore,
    required this.ratedCount,
  });

  /// 各分桶数量，与 [bucketLabels] 一一对应
  final List<int> buckets;

  /// 平均分，无已评分条目时为 0
  final double averageScore;

  /// 有 Bangumi 评分的条目数
  final int ratedCount;

  static const bucketLabels = ['<6', '6~7', '7~8', '8~9', '9+'];

  static int bucketIndexOf(double score) {
    if (score < 6) return 0;
    if (score < 7) return 1;
    if (score < 8) return 2;
    if (score < 9) return 3;
    return 4;
  }

  factory RatingDistribution.of(Iterable<CollectedBangumi> entries) {
    final buckets = List<int>.filled(bucketLabels.length, 0);
    var sum = 0.0;
    var rated = 0;
    for (final entry in entries) {
      final score = entry.bangumiItem.ratingScore;
      if (score <= 0) continue;
      buckets[bucketIndexOf(score)]++;
      sum += score;
      rated++;
    }
    return RatingDistribution(
      buckets: buckets,
      averageScore: rated > 0 ? sum / rated : 0,
      ratedCount: rated,
    );
  }
}

/// 单年单季度的条目分组
class StatsQuarterGroup {
  const StatsQuarterGroup({
    required this.year,
    required this.month,
    required this.entries,
  });

  final int year;

  /// 季度起始月：1 / 4 / 7 / 10
  final int month;
  final List<CollectedBangumi> entries;
}

/// 单年的季度分组集合（ quarters 按季度倒序 ）
class StatsYearGroup {
  const StatsYearGroup({required this.year, required this.quarters});

  final int year;
  final List<StatsQuarterGroup> quarters;

  int get total =>
      quarters.fold(0, (acc, quarter) => acc + quarter.entries.length);
}

/// 条目按放送日期归档：年份倒序 → 季度倒序 → 组内按 [sortOrder] 排序。
/// 没有放送日期的条目不参与归档。
List<StatsYearGroup> groupByAirDate(
  List<CollectedBangumi> entries, {
  StatsSortOrder sortOrder = StatsSortOrder.score,
}) {
  final byYear = <int, Map<int, List<CollectedBangumi>>>{};
  for (final entry in entries) {
    final airDate = _airDateOf(entry);
    if (airDate == null) continue;
    final quarters =
        byYear.putIfAbsent(airDate.year, () => <int, List<CollectedBangumi>>{});
    quarters.putIfAbsent(_quarterMonthOf(airDate.month), () => []).add(entry);
  }

  final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final year in years)
      StatsYearGroup(
        year: year,
        quarters: [
          for (final month
              in (byYear[year]!.keys.toList()..sort((a, b) => b.compareTo(a))))
            StatsQuarterGroup(
              year: year,
              month: month,
              entries: byYear[year]![month]!..sort(_comparatorOf(sortOrder)),
            ),
        ],
      ),
  ];
}

/// 季度起始月：12/1/2 月归入 1 月档，以此类推（沿用 bangumi-note 的口径）
int _quarterMonthOf(int month) => switch (month) {
      12 || 1 || 2 => 1,
      3 || 4 || 5 => 4,
      6 || 7 || 8 => 7,
      _ => 10,
    };

DateTime? _airDateOf(CollectedBangumi entry) {
  final airDate = entry.bangumiItem.airDate;
  if (airDate.isEmpty) return null;
  return DateTime.tryParse(airDate);
}

int Function(CollectedBangumi, CollectedBangumi) _comparatorOf(
    StatsSortOrder order) {
  return switch (order) {
    StatsSortOrder.score => _compareByScoreDesc,
    StatsSortOrder.collectTime => (a, b) {
        final comparison = b.time.compareTo(a.time);
        if (comparison != 0) return comparison;
        return a.bangumiItem.id.compareTo(b.bangumiItem.id);
      },
    StatsSortOrder.title => (a, b) {
        final comparison = _titleOf(a).compareTo(_titleOf(b));
        if (comparison != 0) return comparison;
        return a.bangumiItem.id.compareTo(b.bangumiItem.id);
      },
  };
}

String _titleOf(CollectedBangumi entry) {
  final item = entry.bangumiItem;
  return item.nameCn.isNotEmpty ? item.nameCn : item.name;
}

int _compareByScoreDesc(CollectedBangumi a, CollectedBangumi b) {
  final comparison =
      b.bangumiItem.ratingScore.compareTo(a.bangumiItem.ratingScore);
  if (comparison != 0) return comparison;
  return a.bangumiItem.id.compareTo(b.bangumiItem.id);
}
