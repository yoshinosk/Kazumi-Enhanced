import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/media/media_scraper.dart';
import 'package:kazumi/utils/chinese_convert.dart';

/// 取自用户真实媒体库 `F:\Animate` 的 [ANi] / [Baha] 台配片源文件名。
///
/// 这类命名的共同特点：繁体标题 + 中文季数后缀 + 全角标点 + 地区限定标记，
/// 而 Bangumi 条目名以简体/日文原名为主，不做繁简与季数归一就完全搜不到。
void main() {
  final scraper = MediaScraper();

  group('toSimplifiedChinese', () {
    test('converts traditional anime titles', () {
      expect(toSimplifiedChinese('杖與劍的魔劍譚'), '杖与剑的魔剑谭');
      expect(toSimplifiedChinese('歡迎來到實力至上主義的教室'), '欢迎来到实力至上主义的教室');
      expect(toSimplifiedChinese('在地下城尋求邂逅是否搞錯了什麼'), '在地下城寻求邂逅是否搞错了什么');
      expect(toSimplifiedChinese('無職轉生'), '无职转生');
    });

    test('covers taiwan-only variants missing from TSCharacters', () {
      expect(toSimplifiedChinese('與妳相戀到生命盡頭'), '与你相恋到生命尽头');
    });

    test('leaves simplified and latin text untouched', () {
      expect(toSimplifiedChinese('无职转生'), '无职转生');
      expect(toSimplifiedChinese('Steins;Gate'), 'Steins;Gate');
      expect(toSimplifiedChinese(''), '');
    });

    test('detects traditional characters', () {
      expect(containsTraditionalChinese('杖與劍的魔劍譚'), isTrue);
      expect(containsTraditionalChinese('杖与剑的魔剑谭'), isFalse);
      expect(containsTraditionalChinese('Bocchi the Rock'), isFalse);
    });
  });

  group('MediaScraper.cleanName on real [ANi] releases', () {
    test('normalizes fullwidth colon so Re: title stays searchable', () {
      expect(
        scraper.cleanName(
            '[ANi] Re：從零開始的異世界生活 第四季 - 09 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4'),
        'Re:從零開始的異世界生活 第四季',
      );
    });

    test('strips fullwidth region-lock marker', () {
      expect(
        scraper.cleanName(
            '[ANi] ATRI -My Dear Moments-（僅限港澳台） - 13 [1080P][Bilibili][WEB-DL][AAC AVC][CHT CHS].mp4'),
        'ATRI -My Dear Moments',
      );
    });

    test('keeps chinese quotes inside the title', () {
      expect(
        scraper.cleanName(
            '[ANi] 想結束這場「我愛你」的遊戲 - 10 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4'),
        '想結束這場「我愛你」的遊戲',
      );
    });

    test('keeps numbers that belong to the title', () {
      expect(
        scraper.cleanName(
            '[ANi] 超超超超超喜歡你的 100 個女朋友 - 24 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4'),
        '超超超超超喜歡你的 100 個女朋友',
      );
    });
  });

  group('MediaScraper.parseSeason on real [ANi] releases', () {
    test('parses chinese season from traditional title', () {
      expect(
        scraper.parseSeason(
            '[ANi] 無職轉生～到了異世界就拿出真本事～第三季 - 01 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4'),
        3,
      );
      expect(
        scraper.parseSeason(
            '[ANi] 在地下城尋求邂逅是否搞錯了什麼 第五季 - 15 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4'),
        5,
      );
    });

    test('parses english Season n', () {
      expect(
        scraper.parseSeason(
            '[ANi] 杖與劍的魔劍譚 Season 2 - 19 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4'),
        2,
      );
    });
  });

  group('MediaScraper.stripSeasonSuffix', () {
    test('drops chinese season and everything after it', () {
      expect(
        scraper.stripSeasonSuffix('歡迎來到實力至上主義的教室 第四季 2年級篇 第一學期'),
        '歡迎來到實力至上主義的教室',
      );
      expect(scraper.stripSeasonSuffix('在地下城尋求邂逅是否搞錯了什麼 第五季'),
          '在地下城尋求邂逅是否搞錯了什麼');
    });

    test('drops english season suffix', () {
      expect(scraper.stripSeasonSuffix('杖與劍的魔劍譚 Season 2'), '杖與劍的魔劍譚');
      expect(scraper.stripSeasonSuffix('Watashi no Shiawase na Kekkon S2'),
          'Watashi no Shiawase na Kekkon');
    });

    test('leaves titles without a season marker intact', () {
      expect(scraper.stripSeasonSuffix('與妳相戀到生命盡頭'), '與妳相戀到生命盡頭');
      expect(scraper.stripSeasonSuffix('Mato Seihei no Slave 2'),
          'Mato Seihei no Slave 2');
    });
  });

  group('MediaScraper.stripSubtitle', () {
    test('drops wave-dash subtitle', () {
      expect(scraper.stripSubtitle('無職轉生～到了異世界就拿出真本事～'), '無職轉生');
    });

    test('drops dash-wrapped english subtitle', () {
      expect(scraper.stripSubtitle('ATRI -My Dear Moments'), 'ATRI');
    });

    test('keeps hyphenated proper names', () {
      expect(scraper.stripSubtitle('86-Eighty Six'), '86-Eighty Six');
    });
  });

  group('MediaScraper.expandKeyword', () {
    test('puts simplified variants before traditional originals', () {
      final kws = scraper.expandKeyword('杖與劍的魔劍譚 Season 2');
      expect(kws.first, '杖与剑的魔剑谭 Season 2');
      expect(kws, contains('杖与剑的魔剑谭'));
      expect(kws, contains('杖與劍的魔劍譚'));
      // 简体候选必须全部排在繁体之前，避免浪费必然落空的请求
      final firstTraditional =
          kws.indexWhere(containsTraditionalChinese);
      final lastSimplified =
          kws.lastIndexWhere((k) => !containsTraditionalChinese(k));
      expect(lastSimplified, lessThan(firstTraditional));
    });

    test('expands season and subtitle layers', () {
      final kws = scraper.expandKeyword('無職轉生～到了異世界就拿出真本事～第三季');
      expect(kws, contains('无职转生'));
    });

    test('yields a single entry for plain simplified titles', () {
      expect(scraper.expandKeyword('铃芽之旅'), ['铃芽之旅']);
    });

    test('caps the number of variants', () {
      final kws = scraper.expandKeyword('歡迎來到實力至上主義的教室 第四季 2年級篇 第一學期');
      expect(kws.length, lessThanOrEqualTo(6));
      expect(kws, contains('欢迎来到实力至上主义的教室'));
    });
  });
}
