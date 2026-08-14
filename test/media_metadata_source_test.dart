import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/search/image_search_module.dart';
import 'package:kazumi/services/media/local_media_models.dart';

void main() {
  test('AniList identity is not exposed as a Bangumi identity', () {
    final info = MediaScrapeInfo.fromAniList(Anilist(
      id: 12345,
      title: AnilistTitle(romaji: 'Example Anime'),
    ));

    expect(info.source, MediaMetadataSource.anilist);
    expect(info.bangumiId, isNull);
    expect(info.toBangumiItem().id, -12345);
    expect(info.identityKey, 'anilist:12345');
  });

  test('legacy metadata is not trusted as a Bangumi identity', () {
    final info = MediaScrapeInfo.fromJson({
      'id': 42,
      'name': 'Legacy',
      'nameCn': '',
      'summary': '',
      'airDate': '',
      'coverUrl': '',
    });

    expect(info.source, MediaMetadataSource.legacy);
    expect(info.bangumiId, isNull);
    expect(info.toJson()['source'], 'legacy');
  });

  test('legacy metadata keeps its positive id for history compatibility', () {
    final info = MediaScrapeInfo.fromJson({
      'id': 42,
      'name': 'Legacy',
      'nameCn': '',
      'summary': '',
      'airDate': '',
      'coverUrl': '',
    });

    // legacy 播放 ID 保持正数，与旧版本历史记录 key 一致，避免播放进度失配。
    expect(info.toBangumiItem().id, 42);
  });

  test('legacy data with summary is inferred as bangumi', () {
    final info = MediaScrapeInfo.fromJson({
      'id': 42,
      'name': 'Legacy',
      'nameCn': '',
      'summary': 'Some plot summary',
      'airDate': '2020-01-01',
      'coverUrl': '',
    });

    // 旧版本只有 Bangumi 搜刮与图片识别兜底两条写入路径，兜底结果 summary 恒为空，
    // 因此 summary 非空且 id > 0 的旧数据可安全恢复为 bangumi。
    expect(info.source, MediaMetadataSource.bangumi);
    expect(info.bangumiId, 42);
    expect(info.toBangumiItem().id, 42);
  });

  test('explicit anilist source overrides legacy inference', () {
    final info = MediaScrapeInfo.fromJson({
      'id': 42,
      'name': 'Ani',
      'nameCn': '',
      'summary': 'Some plot summary',
      'airDate': '',
      'coverUrl': '',
      'source': 'anilist',
    });

    expect(info.source, MediaMetadataSource.anilist);
    expect(info.bangumiId, isNull);
    expect(info.toBangumiItem().id, -42);
  });

  test('source participates in grouping identity', () {
    const bangumi = MediaScrapeInfo(
      id: 10,
      name: 'Bangumi',
      nameCn: '',
      summary: '',
      airDate: '',
      coverUrl: '',
    );
    const anilist = MediaScrapeInfo(
      id: 10,
      name: 'AniList',
      nameCn: '',
      summary: '',
      airDate: '',
      coverUrl: '',
      source: MediaMetadataSource.anilist,
    );

    expect(bangumi.identityKey, isNot(anilist.identityKey));
  });
}
