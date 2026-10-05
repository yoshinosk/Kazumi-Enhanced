import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/utils/bangumi_note_json.dart';

/// 构造一条接近 bangumi-note 导出格式的记录：
/// bgm.tv /v0 条目字段 + `type` 覆盖为个人收藏状态 + `nice` 推荐标记。
Map<String, dynamic> _noteItem({
  int id = 501844,
  int noteType = 2, // bangumi-note: 看过
  bool nice = false,
  String date = '2025-07-19',
  bool withRating = true,
  bool withImages = true,
}) {
  return {
    'id': id,
    // bangumi-note 的 SubjectItem 把条目类型覆盖成了收藏状态
    'type': noteType,
    'nice': nice,
    'name': '怪獣8号 第2期',
    'name_cn': '怪兽8号 第二季',
    'summary': '「怪獣8号」の強大すぎる力に向き合うことになった日比野カフカ。',
    'date': date,
    'platform': 'TV',
    if (withImages)
      'images': {
        'large': 'https://lain.bgm.tv/pic/cover/l/19/39/501844_Lh308.jpg',
        'common': 'https://lain.bgm.tv/r/400/pic/cover/l/19/39/501844_Lh308.jpg',
      },
    'infobox': [
      {'key': '中文名', 'value': '怪兽8号 第二季'},
      {'key': '别名', 'value': ['怪兽八号', 'Kaiju No. 8']},
    ],
    'tags': [
      {'name': '战斗', 'count': 208, 'total_cont': 0},
      {'name': '日本', 'count': 75, 'total_cont': 0},
    ],
    if (withRating)
      'rating': {
        'rank': 1204,
        'score': 7.9,
        'total': 511,
        'count': {'10': 102, '9': 130, '8': 150},
      },
    'meta_tags': ['日本', '漫画改'],
  };
}

BangumiItem _bangumiItem({List<String> alias = const []}) {
  return BangumiItem.fromJson({
    'id': 501844,
    'type': 2,
    'name': '怪獣8号 第2期',
    'name_cn': '怪兽8号 第二季',
    'summary': 'summary',
    'date': '2025-07-19',
    'images': {'large': 'https://example.com/a.jpg'},
    'rating': {'rank': 1204, 'score': 7.9, 'total': 511},
    'tags': [
      {'name': '战斗', 'count': 208, 'total_cont': 0},
    ],
    if (alias.isNotEmpty) 'infobox': [
      {'key': '别名', 'value': alias},
    ],
    'meta_tags': ['日本'],
  });
}

void main() {
  group('收藏状态双向映射', () {
    test('bangumi-note → Kazumi', () {
      expect(bangumiNoteTypeToKazumi[1], CollectType.planToWatch.value);
      expect(bangumiNoteTypeToKazumi[2], CollectType.watched.value);
      expect(bangumiNoteTypeToKazumi[3], CollectType.watching.value);
      expect(bangumiNoteTypeToKazumi[4], CollectType.onHold.value);
      expect(bangumiNoteTypeToKazumi[5], CollectType.abandoned.value);
    });

    test('Kazumi → bangumi-note 与正向映射互逆', () {
      for (final entry in bangumiNoteTypeToKazumi.entries) {
        expect(kazumiTypeToBangumiNote[entry.value], entry.key);
      }
    });
  });

  group('BangumiNoteJson.parse', () {
    test('解析收藏状态与条目字段', () {
      final result = BangumiNoteJson.parse('[${jsonEncode(_noteItem())}]');
      expect(result.failureCount, 0);
      expect(result.collectibles, hasLength(1));

      final collect = result.collectibles.single;
      expect(collect.type, CollectType.watched.value);
      expect(collect.bangumiItem.id, 501844);
      expect(collect.bangumiItem.nameCn, '怪兽8号 第二季');
      expect(collect.bangumiItem.airDate, '2025-07-19');
      expect(collect.bangumiItem.ratingScore, 7.9);
      expect(collect.bangumiItem.rank, 1204);
      expect(collect.bangumiItem.votes, 511);
      // 条目类型统一按动画处理，不把收藏状态写进 BangumiItem.type
      expect(collect.bangumiItem.type, 2);
      expect(collect.bangumiItem.alias, ['怪兽八号', 'Kaiju No. 8']);
      expect(collect.bangumiItem.metaTags, ['日本', '漫画改']);
      expect(collect.bangumiItem.tags.map((t) => t.name), contains('战斗'));
    });

    test('收藏状态未知或缺失时计为失败', () {
      final noType = _noteItem(id: 1)..remove('type');
      final zeroType = _noteItem(id: 2, noteType: 0);
      final result = BangumiNoteJson.parse(
          '[${jsonEncode(noType)}, ${jsonEncode(zeroType)}]');
      expect(result.collectibles, isEmpty);
      expect(result.failureCount, 2);
    });

    test('rating/images 缺失时兜底解析', () {
      final result = BangumiNoteJson.parse(
          '[${jsonEncode(_noteItem(withRating: false, withImages: false))}]');
      expect(result.failureCount, 0);
      expect(result.collectibles.single.bangumiItem.ratingScore, 0.0);
      expect(result.collectibles.single.bangumiItem.images, isEmpty);
    });

    test('非数组 JSON 抛出 FormatException', () {
      expect(() => BangumiNoteJson.parse('{"id": 1}'),
          throwsA(isA<FormatException>()));
    });
  });

  group('BangumiNoteJson.encode', () {
    CollectedBangumi collect(CollectType type, {BangumiItem? item}) {
      return CollectedBangumi(item ?? _bangumiItem(), DateTime(2026, 10, 5),
          type.value);
    }

    test('导出为 bangumi-note 兼容字段并反向映射收藏状态', () {
      final list = jsonDecode(
          BangumiNoteJson.encode([collect(CollectType.watching)])) as List;
      expect(list, hasLength(1));

      final subject = list.single as Map<String, dynamic>;
      expect(subject['id'], 501844);
      // Kazumi 在看(1) → bangumi-note 在看(3)
      expect(subject['type'], 3);
      expect(subject['nice'], false);
      expect(subject['name_cn'], '怪兽8号 第二季');
      expect(subject['date'], '2025-07-19');
      expect((subject['rating'] as Map)['rank'], 1204);
      expect((subject['meta_tags'] as List), ['日本']);
    });

    test('别名回填到 infobox，再次导入不丢失', () {
      final item = _bangumiItem(alias: ['别名甲']);
      final exported = BangumiNoteJson.encode([collect(CollectType.watched, item: item)]);
      final infobox =
          ((jsonDecode(exported) as List).single as Map)['infobox'] as List;
      expect(infobox, isNotEmpty);
      expect((infobox.first as Map)['key'], '别名');

      final roundTrip = BangumiNoteJson.parse(exported);
      expect(roundTrip.collectibles.single.bangumiItem.alias, ['别名甲']);
    });

    test('未收藏(type=0)的条目不导出', () {
      final list = jsonDecode(BangumiNoteJson.encode([
        collect(CollectType.watched),
        CollectedBangumi(_bangumiItem(), DateTime(2026, 10, 5),
            CollectType.none.value),
      ])) as List;
      expect(list, hasLength(1));
    });
  });

  group('normalizeSubjectJson', () {
    test('强制条目 type=2 并兜底缺失的 rating / images', () {
      final normalized = BangumiNoteJson.normalizeSubjectJson({
        'id': 1,
        'type': 4, // bangumi-note 的收藏状态残留
        'name': 'x',
        'name_cn': 'y',
      });
      expect(normalized['type'], 2);
      expect((normalized['rating'] as Map)['rank'], 0);
      expect(normalized['images'], isEmpty);

      final item = BangumiItem.fromJson(normalized);
      expect(item.type, 2);
      expect(item.ratingScore, 0.0);
    });

    test('稀疏 rating.count 补齐 1~10 键位，votesCount 不丢失', () {
      final normalized = BangumiNoteJson.normalizeSubjectJson({
        'id': 2,
        'type': 2,
        'name': 'n',
        'name_cn': 'nc',
        'rating': {'rank': 5, 'score': 7.0, 'total': 3, 'count': {'10': 3}},
        'images': {'large': 'https://example.com/a.jpg'},
      });
      final item = BangumiItem.fromJson(normalized);
      expect(item.votesCount, [0, 0, 0, 0, 0, 0, 0, 0, 0, 3]);
    });
  });

  group('导出导入往返', () {
    test('字段保持一致', () {
      final item = _bangumiItem(alias: ['怪兽八号']);
      final source = [CollectedBangumi(item, DateTime(2026, 10, 5), 4)];
      final roundTrip = BangumiNoteJson.parse(BangumiNoteJson.encode(source));

      expect(roundTrip.failureCount, 0);
      expect(roundTrip.collectibles, hasLength(1));
      final restored = roundTrip.collectibles.single;
      expect(restored.type, source.single.type);
      final restoredItem = restored.bangumiItem;
      expect(restoredItem.id, item.id);
      expect(restoredItem.name, item.name);
      expect(restoredItem.nameCn, item.nameCn);
      expect(restoredItem.summary, item.summary);
      expect(restoredItem.airDate, item.airDate);
      expect(restoredItem.ratingScore, item.ratingScore);
      expect(restoredItem.rank, item.rank);
      expect(restoredItem.votes, item.votes);
      expect(restoredItem.alias, item.alias);
      expect(restoredItem.metaTags, item.metaTags);
      expect(restoredItem.tags.map((t) => t.name).toList(),
          item.tags.map((t) => t.name).toList());
    });
  });
}
