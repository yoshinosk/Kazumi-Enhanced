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
}
