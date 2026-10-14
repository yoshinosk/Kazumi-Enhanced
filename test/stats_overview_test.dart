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

    test('组内按收藏时间倒序（sortOrder: collectTime）', () {
      CollectedBangumi entryAt(int id, String time) {
        final entry = _entry(id, CollectType.watched.value);
        // CollectedBangumi.time 在构造时固定为 DateTime(2024)，此处用副本替换
        return CollectedBangumi(entry.bangumiItem, DateTime.parse(time), 4);
      }

      final groups = groupByAirDate(
        [
          entryAt(1, '2024-05-01'),
          entryAt(2, '2024-05-03'),
          entryAt(3, '2024-05-02'),
        ],
        sortOrder: StatsSortOrder.collectTime,
      );
      expect(
        groups.single.quarters.single.entries.map((entry) => entry.bangumiItem.id),
        [2, 3, 1],
      );
    });

    test('组内按标题排序（sortOrder: title，中文名优先）', () {
      CollectedBangumi entryNamed(int id, String nameCn) {
        final entry = _entry(id, CollectType.watched.value);
        final item = entry.bangumiItem;
        item.nameCn = nameCn;
        return CollectedBangumi(item, entry.time, 4);
      }

      final groups = groupByAirDate(
        [
          entryNamed(1, '葬送的芙莉莲'),
          entryNamed(2, '孤独摇滚'),
          entryNamed(3, 'BanG Dream'),
        ],
        sortOrder: StatsSortOrder.title,
      );
      expect(
        groups.single.quarters.single.entries.map((entry) => entry.bangumiItem.id),
        [3, 2, 1],
      );
    });
  });

  group('RatingDistribution.of', () {
    test('按分桶统计并计算平均分，无评分条目被忽略', () {
      CollectedBangumi entryScored(int id, double score) {
        final entry = _entry(id, CollectType.watched.value);
        entry.bangumiItem.ratingScore = score;
        return entry;
      }

      final dist = RatingDistribution.of([
        entryScored(1, 5.2),
        entryScored(2, 6.5),
        entryScored(3, 7.3),
        entryScored(4, 9.8),
        entryScored(5, 0), // 无评分（score <= 0 视为未评分）
      ]);
      expect(dist.buckets, [1, 1, 1, 0, 1]);
      expect(dist.ratedCount, 4);
      expect(dist.averageScore, closeTo(7.2, 0.01));
    });

    test('空集合 / 全部无评分返回 0', () {
      final entry = _entry(1, CollectType.watching.value);
      entry.bangumiItem.ratingScore = 0;
      final dist = RatingDistribution.of([entry]);
      expect(dist.buckets, [0, 0, 0, 0, 0]);
      expect(dist.ratedCount, 0);
      expect(dist.averageScore, 0);
    });
  });
}
