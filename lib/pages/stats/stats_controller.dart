import 'dart:async';

import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:mobx/mobx.dart';

part 'stats_controller.g.dart';

class StatsController = _StatsController with _$StatsController;

abstract class _StatsController with Store {
  _StatsController(this._collectCrudRepository);

  final ICollectCrudRepository _collectCrudRepository;

  StreamSubscription<void>? _changesSubscription;
  Timer? _reloadDebounce;

  @observable
  ObservableList<CollectedBangumi> collectibles =
      ObservableList<CollectedBangumi>();

  /// 没有放送日期、无法归档到季度的条目数
  @observable
  int undatedCount = 0;

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

  int get total => quarters.fold(0, (acc, quarter) => acc + quarter.entries.length);
}

/// 条目按放送日期归档：年份倒序 → 季度倒序 → 组内评分倒序。
/// 没有放送日期的条目不参与归档。
List<StatsYearGroup> groupByAirDate(List<CollectedBangumi> entries) {
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
              entries: byYear[year]![month]!..sort(_compareByScoreDesc),
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

int _compareByScoreDesc(CollectedBangumi a, CollectedBangumi b) {
  final comparison = b.bangumiItem.ratingScore
      .compareTo(a.bangumiItem.ratingScore);
  if (comparison != 0) return comparison;
  return a.bangumiItem.id.compareTo(b.bangumiItem.id);
}
