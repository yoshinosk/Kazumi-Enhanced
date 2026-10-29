import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/media/media_title_matcher.dart';

BangumiItem _anime({
  required int id,
  required String name,
  required String nameCn,
  List<String> alias = const [],
}) {
  return BangumiItem(
    id: id,
    type: 2,
    name: name,
    nameCn: nameCn,
    summary: '',
    airDate: '2023-09-29',
    airWeekday: 5,
    rank: 0,
    images: const {
      'large': '',
      'common': '',
      'medium': '',
      'small': '',
      'grid': '',
    },
    tags: const [],
    alias: alias,
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

void main() {
  final frieren = _anime(
    id: 400602,
    name: '葬送のフリーレン',
    nameCn: '葬送的芙莉莲',
    alias: const ["Frieren: Beyond Journey's End", '葬送的芙莉蓮'],
  );
  final kusuriya = _anime(
    id: 367412,
    name: '薬屋のひとりごと',
    nameCn: '药屋少女的呢喃',
    alias: const ['The Apothecary Diaries'],
  );

  group('scoreTitle', () {
    test('标题包含中文名时给高分', () {
      final score = MediaTitleMatcher.scoreTitle(
        '[Lilith-Raws] 葬送的芙莉莲 - 28 [Baha][WEB-DL][1080p][AVC AAC][CHT][MP4]',
        name: frieren.name,
        nameCn: frieren.nameCn,
        alias: frieren.alias,
      );
      expect(score, greaterThanOrEqualTo(0.9));
    });

    test('标题使用别名（含标点差异）时也能命中', () {
      final score = MediaTitleMatcher.scoreTitle(
        '[ANi] Frieren Beyond Journey\'s End - 28 [1080P][Baha][WEB-DL]',
        name: frieren.name,
        nameCn: frieren.nameCn,
        alias: frieren.alias,
      );
      expect(score, greaterThanOrEqualTo(0.9));
    });

    test('繁体标题按简体归一后命中', () {
      final score = MediaTitleMatcher.scoreTitle(
        '[ANi] 葬送的芙莉蓮 - 28 [1080P]',
        name: frieren.name,
        nameCn: frieren.nameCn,
        alias: frieren.alias,
      );
      expect(score, greaterThanOrEqualTo(0.9));
    });

    test('别的番剧标题低于阈值', () {
      final score = MediaTitleMatcher.scoreTitle(
        '[ANi] 药屋少女的呢喃 - 24 [1080P][Baha][WEB-DL]',
        name: frieren.name,
        nameCn: frieren.nameCn,
        alias: frieren.alias,
      );
      expect(score, lessThan(MediaTitleMatcher.matchThreshold));
    });

    test('标题含当前搜索词且搜索词指向该番剧时给中等分', () {
      // 搜索词与番剧名对不上时不加分：否则任何关键词都能把归属挂上去。
      expect(
        MediaTitleMatcher.scoreTitle(
          '[Group] Sousou no Frieren - 28 [1080p]',
          name: frieren.name,
          nameCn: frieren.nameCn,
          alias: frieren.alias,
          queryHint: 'Sousou no Frieren',
        ),
        0,
      );

      // 标题只写了简称（不含任何候选全名），靠「搜索词指向该番剧 + 标题
      // 含搜索词」兜底：覆盖标题用罗马音 / 简称、别名未收录的情况。
      final withHint = MediaTitleMatcher.scoreTitle(
        '[Group] 芙莉莲 - 28 [1080p]',
        name: frieren.name,
        nameCn: frieren.nameCn,
        alias: frieren.alias,
        queryHint: '芙莉莲',
      );
      expect(withHint, 0.85);
    });
  });

  group('queryMatchesBangumi', () {
    test('同番关键词返回 true', () {
      expect(MediaTitleMatcher.queryMatchesBangumi('葬送的芙莉莲', frieren), isTrue);
      expect(
        MediaTitleMatcher.queryMatchesBangumi('葬送的芙莉莲 第二季', frieren),
        isTrue,
      );
      expect(MediaTitleMatcher.queryMatchesBangumi('Frieren', frieren), isTrue);
    });

    test('换到别的番剧返回 false', () {
      expect(MediaTitleMatcher.queryMatchesBangumi('药屋少女的呢喃', frieren), isFalse);
      expect(MediaTitleMatcher.queryMatchesBangumi('孤独摇滚', frieren), isFalse);
    });
  });

  group('resolveScrapeInfo', () {
    test('资源标题不属于关联番剧时丢弃归属，改走自动识别', () {
      final resolved = MediaTitleMatcher.resolveScrapeInfo(
        title: '[ANi] 药屋少女的呢喃 - 24 [1080P][Baha][WEB-DL]',
        info: MediaScrapeInfo.fromBangumiItem(frieren),
        anime: frieren,
      );
      expect(resolved.info, isNull);
      expect(resolved.confidence, 0);
    });

    test('资源标题属于关联番剧时保持满置信度', () {
      final info = MediaScrapeInfo.fromBangumiItem(frieren);
      final resolved = MediaTitleMatcher.resolveScrapeInfo(
        title: '[Lilith-Raws] 葬送的芙莉莲 - 28 [Baha][1080p]',
        info: info,
        anime: frieren,
      );
      expect(resolved.info, same(info));
      expect(resolved.confidence, 1.0);
    });

    test('用户在下载弹窗改选另一部番剧时按新番剧评分', () {
      // 旧关联是芙莉莲，但用户已把归属改成《药屋少女的呢喃》。
      final info = MediaScrapeInfo.fromBangumiItem(kusuriya);
      final resolved = MediaTitleMatcher.resolveScrapeInfo(
        title: '[ANi] 药屋少女的呢喃 - 24 [1080P][Baha][WEB-DL]',
        info: info,
        anime: frieren,
      );
      expect(resolved.info, same(info));
      expect(resolved.confidence, 1.0);
    });

    test('无归属时不产生置信度', () {
      final resolved = MediaTitleMatcher.resolveScrapeInfo(
        title: '[ANi] 葬送的芙莉莲 - 28',
        info: null,
        anime: frieren,
      );
      expect(resolved.info, isNull);
      expect(resolved.confidence, 0);
    });

    test('短名命中只保留归属，不给自动入库的置信度', () {
      // 「迷宫」这类两字名极易在别的标题里误命中：保留归属信息供人工
      // 确认，但置信度必须低于默认入库阈值（0.7），不能据此移动文件。
      final shortName = _anime(id: 900001, name: '', nameCn: '迷宫');
      final info = MediaScrapeInfo.fromBangumiItem(shortName);
      final resolved = MediaTitleMatcher.resolveScrapeInfo(
        title: '[Group] 迷宫饭 - 01 [1080p]',
        info: info,
        anime: shortName,
      );
      expect(resolved.info, same(info));
      expect(resolved.confidence, lessThan(0.7));
    });
  });
}
