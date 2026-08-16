import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/media/media_scraper.dart';

void main() {
  group('MediaScraper on realistic anime folder names', () {
    MediaScraper newScraper() => MediaScraper();

    test('LoliHouse release group with episode range', () {
      final s = newScraper();
      expect(
        s.cleanName('[LoliHouse] Beheneko [01-12][WebRip 1080p HEVC-10bit AAC]'),
        'Beheneko',
      );
      expect(s.parseSeason(
          '[LoliHouse] Beheneko [01-12][WebRip 1080p HEVC-10bit AAC]'),
          isNull);
    });

    test('plain name with bare season number', () {
      final s = newScraper();
      expect(s.cleanName('Mato Seihei no Slave 2'), 'Mato Seihei no Slave 2');
    });

    test('dotted names are kept intact, tags stripped', () {
      final s = newScraper();
      expect(
        s.cleanName('Tomb.Raider.King.S01E01-E02.JPN.Pre-release'),
        'Tomb Raider King',
      );
    });

    test('season 2 via S2 suffix', () {
      final s = newScraper();
      expect(
        s.cleanName('[Nekomoe kissaten&LoliHouse] Watashi no Shiawase na '
            'Kekkon S2'),
        'Watashi no Shiawase na Kekkon S2',
      );
      expect(
        s.parseSeason('[Nekomoe kissaten&LoliHouse] Watashi no Shiawase na '
            'Kekkon S2'),
        2,
      );
    });

    test('title hidden inside brackets', () {
      final s = newScraper();
      expect(
        s.cleanName(
            '[Sakurato.sub][Busou Shoujo Machiavellianism][01-12END][GB][720P]'),
        'Busou Shoujo Machiavellianism',
      );
    });
  });
}