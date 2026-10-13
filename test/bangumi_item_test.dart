import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';

/// 构造一个接近 next.bgm.tv /p1/calendar SlimSubject 的最小 JSON。
/// 默认不包含 tags 字段，模拟日历接口的真实返回结构。
Map<String, dynamic> _slimJson({
  List<Map<String, dynamic>>? tags,
  List<String>? metaTags,
  List<String>? metaTagsSnake,
}) {
  return {
    'id': 123,
    'type': 2,
    'name': '测试动画',
    'name_cn': '测试动画',
    'summary': '',
    'images': {'large': 'https://example.com/a.jpg'},
    'rating': {'rank': 5, 'score': 8.5, 'total': 100},
    if (tags != null) 'tags': tags,
    if (metaTags != null) 'metaTags': metaTags,
    if (metaTagsSnake != null) 'meta_tags': metaTagsSnake,
  };
}

void main() {
  group('BangumiItem.isJapaneseAnime', () {
    test('tags 含「日本」判定为日漫', () {
      final item = BangumiItem.fromJson(_slimJson(tags: [
        {'name': '搞笑', 'count': 1, 'total_cont': 1},
        {'name': '日本', 'count': 1, 'total_cont': 1},
      ]));
      expect(item.isJapaneseAnime, isTrue);
    });

    test('无 tags 字段时，metaTags 含「日本」判定为日漫（p1/calendar SlimSubject 场景）', () {
      final item =
          BangumiItem.fromJson(_slimJson(metaTags: ['校园', '日本', '漫画改']));
      expect(item.metaTags, ['校园', '日本', '漫画改']);
      expect(item.isJapaneseAnime, isTrue);
    });

    test('兼容下划线写法 meta_tags', () {
      final item = BangumiItem.fromJson(_slimJson(metaTagsSnake: ['日常', '日本']));
      expect(item.metaTags, ['日常', '日本']);
      expect(item.isJapaneseAnime, isTrue);
    });

    test('国漫标签（中国/国产）不被判定为日漫', () {
      final item = BangumiItem.fromJson(_slimJson(
        tags: [
          {'name': '中国', 'count': 1, 'total_cont': 1},
          {'name': '国产动画', 'count': 1, 'total_cont': 1},
        ],
        metaTags: ['中国', '国产'],
      ));
      expect(item.isJapaneseAnime, isFalse);
    });

    test('无任何标签时默认为非日漫', () {
      final item = BangumiItem.fromJson(_slimJson());
      expect(item.metaTags, isEmpty);
      expect(item.isJapaneseAnime, isFalse);
    });
  });

  group('BangumiItem 评分解析', () {
    test('镜像把收藏人数误写进 rating.total 时，评分人数以分布总和为准', () {
      // 复现 api.kazumi.fyi /p1/subjects 的真实脏数据：total=484（收藏数），
      // 分布实际只有 2 人评分。
      final item = BangumiItem.fromJson({
        'id': 654294,
        'type': 2,
        'name': '冰剑的魔术师将要统一世界 第二季',
        'summary': 'test',
        'rating': {
          'rank': 0,
          'score': 8.5,
          'total': 484,
          'count': {'1': 0, '10': 0, '2': 0, '3': 0, '4': 0, '5': 0, '6': 0, '7': 0, '8': 1, '9': 1},
        },
      });
      expect(item.votes, 2);
      expect(item.votesCount, [0, 0, 0, 0, 0, 0, 0, 1, 1, 0]);
      expect(item.ratingScore, 8.5);
    });

    test('p1 列表分布（List）与 total 一致时正常解析', () {
      final item = BangumiItem.fromJson({
        'id': 975,
        'type': 2,
        'name': 'CLANNAD',
        'summary': 'test',
        'rating': {
          'rank': 105,
          'score': 8.27,
          'total': 4,
          'count': [1, 0, 0, 0, 1, 0, 1, 0, 0, 1],
        },
      });
      expect(item.votes, 4);
      expect(item.rank, 105);
      expect(item.votesCount.length, 10);
    });

    test('count 缺失时评分人数回退 rating.total', () {
      final item = BangumiItem.fromJson(_slimJson());
      expect(item.votes, 100);
      expect(item.votesCount, isEmpty);
    });

    test('rating 缺失或畸形时兜底不抛错', () {
      final noRating = BangumiItem.fromJson({
        'id': 1,
        'type': 2,
        'name': 'x',
        'summary': '',
      });
      expect(noRating.votes, 0);
      expect(noRating.rank, 0);
      expect(noRating.ratingScore, 0.0);
      expect(noRating.votesCount, isEmpty);

      final nullRating = BangumiItem.fromJson({
        'id': 2,
        'type': 2,
        'name': 'x',
        'summary': '',
        'rating': null,
      });
      expect(nullRating.votes, 0);
      expect(nullRating.votesCount, isEmpty);
    });

    test('分布长度不足 10 时自动补零', () {
      final item = BangumiItem.fromJson({
        'id': 3,
        'type': 2,
        'name': 'x',
        'summary': '',
        'rating': {
          'rank': 1,
          'score': 7.0,
          'total': 3,
          'count': [2, 1],
        },
      });
      expect(item.votes, 3);
      expect(item.votesCount, [2, 1, 0, 0, 0, 0, 0, 0, 0, 0]);
    });
  });
}
