import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/media/media_scraper.dart';

BangumiItem _item({
  required int id,
  required String name,
  String? nameCn,
  String airDate = '',
  List<String> alias = const [],
}) {
  return BangumiItem(
    id: id,
    type: 2,
    name: name,
    nameCn: nameCn ?? name,
    summary: '',
    airDate: airDate,
    airWeekday: 0,
    rank: 0,
    images: const {},
    tags: const [],
    alias: alias,
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

void main() {
  final scraper = MediaScraper();

  setUp(MediaScraper.clearCachesForTest);

  group('打分：负例', () {
    test('长关键词不应命中 3 字短名', () {
      final match = scraper.bestMatchForTest(
        '关于我转生变成史莱姆这档事',
        [_item(id: 1, name: '史莱姆')],
      );
      expect(match, isNull);
    });

    test('跨季标题只共享前缀时不命中', () {
      final match = scraper.bestMatchForTest(
        '进击的巨人最终季',
        [_item(id: 2, name: '进击的巨人第二季')],
      );
      expect(match, isNull);
    });

    test('短名片段占关键词比例过低时不命中', () {
      expect(
        scraper.nameSimilarityForTest('关于我转生变成史莱姆这档事', '转生史莱姆'),
        0,
      );
    });

    test('保留 x，避免 xxxHOLiC 与 HOLiC 折叠成同一部', () {
      expect(
        scraper.nameSimilarityForTest('xxxHOLiC', 'HOLiC'),
        lessThan(0.6),
      );
    });
  });

  group('打分：正例', () {
    test('完全相同给 1.0', () {
      final match = scraper.bestMatchForTest(
        '铃芽之旅',
        [_item(id: 3, name: '铃芽之旅')],
      );
      expect(match, isNotNull);
      expect(match!.confidence, closeTo(1.0, 0.001));
    });

    test('短关键词包含于长标题给 0.9', () {
      final match = scraper.bestMatchForTest(
        '无职转生',
        [_item(id: 4, name: '无职转生～到了异世界就拿出真本事～')],
      );
      expect(match, isNotNull);
      expect(match!.confidence, closeTo(0.9, 0.001));
    });

    test('× 与 x 视为同一写法', () {
      expect(
        scraper.nameSimilarityForTest('HUNTER×HUNTER', 'Hunter x Hunter'),
        1.0,
      );
    });

    test('次优差距不足时判为未命中', () {
      final match = scraper.bestMatchForTest(
        'abcdefghij',
        [
          _item(id: 5, name: 'abcdefg'),
          _item(id: 6, name: 'abcdef'),
        ],
      );
      expect(match, isNull);
    });

    test('次优差距足够时采纳最高分', () {
      final match = scraper.bestMatchForTest(
        'abcdefghij',
        [_item(id: 7, name: 'abcdefg')],
      );
      expect(match, isNotNull);
      expect(match!.confidence, closeTo(0.525, 0.001));
    });
  });

  group('季数与置信度', () {
    test('第一季同样会降权第三季条目', () {
      final match = scraper.bestMatchForTest(
        '测试番剧',
        [_item(id: 8, name: '测试番剧 第三季')],
        season: 1,
      );
      expect(match, isNotNull);
      expect(match!.confidence, closeTo(0.78, 0.001));
    });

    test('季数 + 年份加分不会让置信度超过 1', () {
      final match = scraper.bestMatchForTest(
        '测试番剧',
        [_item(id: 9, name: '测试番剧 第一季', airDate: '2020-01-01')],
        season: 1,
        year: 2020,
      );
      expect(match, isNotNull);
      expect(match!.confidence, 1.0);
    });

    test('2期 / 1st Season 可解析', () {
      expect(scraper.parseSeason('某番剧 2期'), 2);
      expect(scraper.parseSeason('某番剧 ２期'), 2);
      expect(scraper.parseSeason('某番剧 1st Season'), 1);
      expect(scraper.parseSeason('某番剧 第3期'), 3);
    });
  });

  group('清洗：点号分隔的集数', () {
    test('Show.Name.-.01', () {
      expect(scraper.cleanName('Show.Name.-.01'), 'Show Name');
    });

    test('Show.Name.01', () {
      expect(scraper.cleanName('Show.Name.01'), 'Show Name');
    });

    test('保留四位年份', () {
      expect(scraper.cleanName('Show.Name.2020'), 'Show Name 2020');
    });
  });
}
