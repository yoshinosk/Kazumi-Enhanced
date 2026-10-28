import 'package:kazumi/modules/history/history_module.dart';

enum HistorySourceFilter {
  all('全部'),
  online('在线'),
  offline('缓存');

  const HistorySourceFilter(this.label);

  final String label;

  bool _matches(History history) => switch (this) {
        all => true,
        online => HistoryEntryKind.normalize(history.entryKind) ==
            HistoryEntryKind.online,
        offline => HistoryEntryKind.normalize(history.entryKind) ==
            HistoryEntryKind.offline,
      };
}

class HistoryDateGroup {
  HistoryDateGroup._(this.date, this.entries);

  final DateTime date;
  final List<HistoryGroup> entries;

  String label(DateTime now) {
    final localNow = now.toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    if (date == today) return '今天';
    if (date == DateTime(today.year, today.month, today.day - 1)) return '昨天';
    final prefix = date.year == today.year ? '' : '${date.year}年';
    return '$prefix${date.month}月${date.day}日';
  }
}

/// 同一番剧的多来源历史聚合。
///
/// 历史存储按「来源 + 番剧 + 在线/缓存」分键，本类只在显示层把同一番剧
/// 的多条记录合并成一张卡片：[primary] 为最近播放的一条，其余记录保留在
/// [entries] 中，供当前来源失效后续播回退。
class HistoryGroup {
  HistoryGroup._(this.entries);

  /// 按最近观看时间倒序排列，第一条为 [primary]。
  final List<History> entries;

  History get primary => entries.first;

  bool get hasAlternatives => entries.length > 1;

  String get key => 'bangumi-${primary.bangumiItem.id}';

  /// 除最近播放外，其余来源的可读名称（按最近观看时间排序）。
  List<String> get alternativeLabels =>
      [for (final history in entries.skip(1)) historySourceLabel(history)];
}

/// 按番剧 ID 聚合多来源历史，返回按最近观看时间倒序的卡片分组。
List<HistoryGroup> groupHistoriesByBangumi(Iterable<History> histories) {
  final byBangumi = <int, List<History>>{};
  for (final history in histories) {
    byBangumi.putIfAbsent(history.bangumiItem.id, () => []).add(history);
  }
  final groups = <HistoryGroup>[];
  for (final entries in byBangumi.values) {
    entries.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
    groups.add(HistoryGroup._(entries));
  }
  groups.sort(
    (a, b) => b.primary.lastWatchTime.compareTo(a.primary.lastWatchTime),
  );
  return groups;
}

List<HistoryDateGroup> groupHistoryEntries(
  Iterable<History> entries, {
  String query = '',
  HistorySourceFilter source = HistorySourceFilter.all,
}) {
  final keyword = query.trim().toLowerCase();
  final filtered = entries.where((entry) {
    if (!source._matches(entry)) return false;
    final item = entry.bangumiItem;
    return keyword.isEmpty ||
        [item.name, item.nameCn, ...item.alias, historySourceLabel(entry)]
            .any((value) => value.toLowerCase().contains(keyword));
  });
  final grouped = groupHistoriesByBangumi(filtered);

  final groups = <HistoryDateGroup>[];
  for (final entry in grouped) {
    final localTime = entry.primary.lastWatchTime.toLocal();
    final date = DateTime(localTime.year, localTime.month, localTime.day);
    if (groups.isEmpty || groups.last.date != date) {
      groups.add(HistoryDateGroup._(date, []));
    }
    groups.last.entries.add(entry);
  }
  return groups;
}
