import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/local_episode_parser.dart';

void main() {
  group('parseLocalEpisodeNumber', () {
    final cases = <String, int>{
      // 常见字幕组命名：集数在独立方括号
      '[Nekomoe kissaten][Sousou no Frieren][01][1080p][JPSC].mp4': 1,
      '[Sakurato] Bocchi the Rock! [01][AVC-8bit 1080p AAC][CHS].mp4': 1,
      '[VCB-Studio] Steins;Gate 0 [05][Ma10p_1080p][x265_flac].mkv': 5,
      '[Airota][86 -Eighty Six-][07][1080p][CHS].mp4': 7,
      // 发布档期干扰
      '【喵萌奶茶屋】★10月新番★[葬送的芙莉莲][12][1080p][简日双语].mp4': 12,
      '【幻樱字幕组】★4月新番[某科学的超电磁炮][03][GB][720P].mp4': 3,
      // 季度数字干扰
      '[ANi] 我推的孩子 2 - 08 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4': 8,
      'Re Zero kara Hajimeru Isekai Seikatsu 2nd Season - 04.mkv': 4,
      // SxxExx
      'Fate.Zero.S01E05.1080p.BluRay.x264.mkv': 5,
      'Kaguya-sama.wa.Kokurasetai.S03E11.mkv': 11,
      // 中文集数
      '2024年新番 迷宫饭 第09话.mp4': 9,
      '进击的巨人 第25集 [1080p].mkv': 25,
      // EP 前缀
      'Jujutsu Kaisen EP23 [1080p][x265].mkv': 23,
      // 破折号分隔
      '[Lilith-Raws] Sousou no Frieren - 18 [Baha][WEB-DL][1080p][AVC AAC][CHT].mp4':
          18,
      // 版本号后缀
      '[Airota][Bokura no Ame-iro Protocol][06v2][1080p][CHS].mkv': 6,
      // CRC32 后缀
      '[Ohys-Raws] Spy x Family - 14 (CX 1280x720 x264 AAC) [A1B2C3D4].mp4': 14,
      // 无集数信息
      'movie.mp4': 0,
      'OVA.mkv': 0,
    };

    cases.forEach((fileName, expected) {
      test('"$fileName" -> $expected', () {
        expect(parseLocalEpisodeNumber(fileName), expected);
      });
    });

    test('空文件名返回 0', () {
      expect(parseLocalEpisodeNumber(''), 0);
      expect(parseLocalEpisodeNumber('   '), 0);
    });
  });

  group('sanitizeAnimeTitle', () {
    final cases = <String, String>{
      '[Nekomoe kissaten][Sousou no Frieren][01][1080p][JPSC].mp4':
          'Sousou no Frieren',
      '【喵萌奶茶屋】★10月新番★[葬送的芙莉莲][12][1080p][简日双语].mp4': '葬送的芙莉莲',
      '[ANi] 我推的孩子 2 - 08 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4': '我推的孩子 2',
      '[Sakurato] Bocchi the Rock! [01][AVC-8bit 1080p AAC][CHS].mp4':
          'Bocchi the Rock!',
    };

    cases.forEach((fileName, expected) {
      test('"$fileName" -> "$expected"', () {
        expect(sanitizeAnimeTitle(fileName), expected);
      });
    });

    test('空文件名返回空串', () {
      expect(sanitizeAnimeTitle(''), '');
    });
  });
}
