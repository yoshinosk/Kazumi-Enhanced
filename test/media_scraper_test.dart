import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/media/media_scraper.dart';

void main() {
  final scraper = MediaScraper();

  group('MediaScraper.cleanName', () {
    test('strips release group tags and resolution', () {
      expect(
        scraper.cleanName('[VCB-Studio] Steins;Gate [Ma10p_1080p]'),
        'Steins;Gate',
      );
    });

    test('strips episode numbers from standard anime folder', () {
      expect(
        scraper.cleanName('命运石之门 第01话'),
        '命运石之门',
      );
    });

    test('keeps simple chinese names intact', () {
      expect(scraper.cleanName('铃芽之旅'), '铃芽之旅');
    });

    test('handles parentheses and season markers', () {
      expect(
        scraper.cleanName('BOCCHI THE ROCK! Season 1'),
        'BOCCHI THE ROCK! Season 1',
      );
    });
  });

  group('MediaScraper.parseSeason', () {
    test('parses english S2', () {
      expect(scraper.parseSeason('某番剧 S2'), 2);
    });

    test('parses Season 3', () {
      expect(scraper.parseSeason('某番剧 Season 3'), 3);
    });

    test('parses Chinese 第二季', () {
      expect(scraper.parseSeason('某番剧 第二季'), 2);
    });

    test('returns null without season marker', () {
      expect(scraper.parseSeason('无职转生'), isNull);
    });
  });

  group('MediaScraper.parseYear', () {
    test('extracts year from parentheses', () {
      expect(scraper.parseYear('命运石之门 (2011)'), 2011);
    });

    test('returns null for invalid year', () {
      expect(scraper.parseYear('No year here'), isNull);
    });
  });
}