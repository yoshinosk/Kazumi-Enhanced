import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/history/history_list_query.dart';

void main() {
  final now = DateTime(2026, 10, 28, 12);

  group('groupHistoriesByBangumi', () {
    test('merges the same bangumi from different sources', () {
      final older = _history(
        id: 1,
        adapterName: 'source-a',
        time: now.subtract(const Duration(hours: 2)),
      );
      final newer = _history(id: 1, adapterName: 'source-b', time: now);
      final other = _history(
        id: 2,
        adapterName: 'source-a',
        time: now.subtract(const Duration(minutes: 10)),
      );

      final groups = groupHistoriesByBangumi([older, newer, other]);

      expect(groups, hasLength(2));
      expect(groups.first.primary, same(newer));
      expect(groups.first.entries, [newer, older]);
      expect(groups.first.hasAlternatives, isTrue);
      expect(groups.first.alternativeLabels, ['在线 · source-a']);
      expect(groups.last.primary, same(other));
    });

    test('merges online and cached records of the same bangumi', () {
      final online = _history(
        id: 1,
        adapterName: 'source-a',
        time: now,
        episodeNumber: 5,
      );
      final cached = _history(
        id: 1,
        adapterName: 'source-a',
        time: now.subtract(const Duration(days: 1)),
        entryKind: HistoryEntryKind.offline,
        episodeNumber: 3,
      );

      final groups = groupHistoriesByBangumi([cached, online]);

      expect(groups, hasLength(1));
      expect(groups.single.primary, same(online));
      expect(groups.single.entries, [online, cached]);
      expect(groups.single.alternativeLabels, ['缓存 · source-a']);
    });
  });

  group('groupHistoryEntries', () {
    test('date groups follow the primary record watch time', () {
      final older = _history(
        id: 1,
        adapterName: 'source-a',
        time: DateTime(2026, 10, 27, 23),
      );
      final newer = _history(
        id: 1,
        adapterName: 'source-b',
        time: DateTime(2026, 10, 28, 1),
      );

      final groups = groupHistoryEntries([older, newer]);

      expect(groups, hasLength(1));
      expect(groups.single.date, DateTime(2026, 10, 28));
      expect(groups.single.entries.single.primary, same(newer));
    });

    test('source filter applies before merging', () {
      final online = _history(id: 1, adapterName: 'source-a', time: now);
      final cached = _history(
        id: 1,
        adapterName: 'source-a',
        time: now.subtract(const Duration(days: 1)),
        entryKind: HistoryEntryKind.offline,
      );

      final groups = groupHistoryEntries([
        online,
        cached,
      ], source: HistorySourceFilter.offline);

      expect(groups, hasLength(1));
      expect(groups.single.entries.single.primary, same(cached));
    });

    test('search matches an alternative source and shows that record', () {
      final older = _history(
        id: 1,
        adapterName: 'source-a',
        time: now.subtract(const Duration(days: 1)),
      );
      final newer = _history(id: 1, adapterName: 'source-b', time: now);

      final groups = groupHistoryEntries([older, newer], query: 'source-a');

      expect(groups, hasLength(1));
      expect(groups.single.entries.single.primary, same(older));
      expect(groups.single.entries.single.hasAlternatives, isFalse);
    });
  });

  group('historySourceLabel', () {
    test('uses readable labels for special adapters', () {
      expect(
        historySourceLabel(
          _history(id: 1, adapterName: kLocalMediaAdapterName, time: now),
        ),
        '本地媒体库',
      );
      expect(
        historySourceLabel(
          _history(id: 1, adapterName: kMagnetStreamAdapterName, time: now),
        ),
        '边下边播',
      );
      expect(
        historySourceLabel(
          _history(
            id: 1,
            adapterName: 'source-a',
            time: now,
            entryKind: HistoryEntryKind.offline,
          ),
        ),
        '缓存 · source-a',
      );
    });
  });
}

History _history({
  required int id,
  required String adapterName,
  required DateTime time,
  String entryKind = HistoryEntryKind.online,
  int episodeNumber = 1,
}) {
  return History(
    _item(id),
    episodeNumber,
    adapterName,
    time,
    '',
    'EP$episodeNumber',
    entryKind: entryKind,
    episodePageUrl: '/ep$episodeNumber',
  );
}

BangumiItem _item(int id) {
  return BangumiItem(
    id: id,
    type: 2,
    name: 'subject $id',
    nameCn: '条目 $id',
    summary: '',
    airDate: '2026-10-01',
    airWeekday: 3,
    rank: 0,
    images: const {},
    tags: const [],
    alias: const [],
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}
