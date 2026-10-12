import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/stats/stats_controller.dart';

CollectedBangumi _entry(int id, int type, {String date = '2024-04-01'}) {
  final item = BangumiItem.fromJson({
    'id': id,
    'type': 2,
    'name': 'n$id',
    'name_cn': '',
    'summary': '',
    'date': date,
    'images': {'large': 'https://example.com/$id.jpg'},
    'rating': {'rank': 1, 'score': 5, 'total': 10},
  });
  return CollectedBangumi(item, DateTime(2024), type);
}

void main() {
  group('StatsStatusCounts.of', () {
    test('总数包含在看 / 搁置，曲线计数只统计对应状态', () {
      final counts = StatsStatusCounts.of([
        _entry(1, CollectType.watching.value),
        _entry(2, CollectType.planToWatch.value),
        _entry(3, CollectType.onHold.value),
        _entry(4, CollectType.watched.value),
        _entry(5, CollectType.abandoned.value),
        _entry(6, CollectType.watched.value),
      ]);
      expect(counts.total, 6);
      expect(counts.watched, 2);
      expect(counts.planToWatch, 1);
      expect(counts.abandoned, 1);
    });

    test('空集合返回全 0', () {
      final counts = StatsStatusCounts.of(const []);
      expect(counts.total, 0);
      expect(counts.watched, 0);
      expect(counts.planToWatch, 0);
      expect(counts.abandoned, 0);
    });
  });

  group('groupByAirDate', () {
    test('按年 / 季度倒序归档，无放送日期的条目被过滤', () {
      final groups = groupByAirDate([
        _entry(1, CollectType.watched.value, date: '2024-04-02'),
        _entry(2, CollectType.watched.value, date: '2024-01-15'),
        _entry(3, CollectType.planToWatch.value, date: '2023-10-01'),
        _entry(4, CollectType.watched.value, date: ''),
      ]);
      expect(groups.map((group) => group.year), [2024, 2023]);
      expect(groups.first.quarters.map((quarter) => quarter.month), [4, 1]);
      expect(groups.first.total, 2);
      expect(groups.last.quarters.single.month, 10);
    });

    test('组内按评分倒序、同分按 id 升序', () {
      final groups = groupByAirDate([
        _entry(10, CollectType.watched.value, date: '2024-04-02'),
        _entry(3, CollectType.watched.value, date: '2024-04-02'),
      ]);
      expect(
        groups.single.quarters.single.entries
            .map((entry) => entry.bangumiItem.id),
        [3, 10],
      );
    });

    test('季度起始月换算：12 月归入 1 月档（沿用 bangumi-note 口径）', () {
      final groups = groupByAirDate([
        _entry(1, CollectType.watched.value, date: '2024-12-20'),
      ]);
      expect(groups.single.year, 2024);
      expect(groups.single.quarters.single.month, 1);
      expect(groups.single.total, 1);
    });
  });
}
