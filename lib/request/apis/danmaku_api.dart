import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/clients/danmaku_client.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_match_response.dart';
import 'package:kazumi/utils/dandan_file_hash.dart';
import 'package:kazumi/utils/string_similarity.dart';
import 'package:path/path.dart' as p;

class DanmakuApi {
  static final DanmakuClient _client = DanmakuClient.instance;

  // 从BgmBangumiID获取DanDanBangumiID
  static Future<int> getDanDanBangumiIDByBgmBangumiID(int bgmBangumiID) async {
    var path = ApiEndpoints.formatUrl(
        ApiEndpoints.dandanAPIInfoByBgmBangumiId, [bgmBangumiID]);
    var endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(endPoint);
    DanmakuEpisodeResponse danmakuEpisodeResponse =
        DanmakuEpisodeResponse.fromJson(jsonData);
    return danmakuEpisodeResponse.bangumiId;
  }

  // 从标题获取DanDanBangumiID
  //
  // [minSimilarity] 为可接受的最低标题相似度。低于该阈值时宁可返回 0（交由上层
  // 继续尝试其它策略），也不要返回一个风马牛不相及的番剧——错误的 animeId 会
  // 直接导致加载到完全无关的弹幕。
  static Future<int> getBangumiIDByTitle(
    String title, {
    double minSimilarity = 0.35,
  }) async {
    DanmakuSearchResponse danmakuSearchResponse =
        await getDanmakuSearchResponse(title);

    int bestAnimeId = 0;
    double maxSimilarity = 0;

    for (var anime in danmakuSearchResponse.animes) {
      int animeId = anime.animeId;
      // 早期实现额外排除了 animeId >= 100000 的条目，但弹弹 Play 近年新增番剧的
      // animeId 普遍已超过该阈值，这会把绝大多数新番直接过滤掉。
      if (animeId < 2) {
        continue;
      }

      String animeTitle = anime.animeTitle;
      double similarity = calculateSimilarity(animeTitle, title);
      if (similarity == 1) {
        KazumiLogger().i('Danmaku: total match $title');
        return animeId;
      }

      if (similarity > maxSimilarity) {
        maxSimilarity = similarity;
        bestAnimeId = animeId;
        KazumiLogger().i(
            'Danmaku: match anime danmaku $title --- $animeTitle similarity: $similarity');
      }
    }

    if (maxSimilarity < minSimilarity) {
      KazumiLogger().w(
          'Danmaku: best similarity $maxSimilarity below threshold $minSimilarity for "$title", discarded');
      return 0;
    }

    return bestAnimeId;
  }

  /// 通过弹弹 Play 的文件匹配接口精确定位本地视频对应的分集。
  ///
  /// 相比「标题检索 + 集数猜测」，该接口直接以文件哈希命中弹幕库，
  /// 不受字幕组命名、季度拆分、BGM ID 映射缺失的影响，是本地媒体的首选方案。
  static Future<DanmakuMatchResponse> matchLocalFile(String filePath) async {
    if (filePath.isEmpty) return DanmakuMatchResponse.empty;

    final fileHash = await calculateDandanFileHash(filePath);
    if (fileHash == null) {
      KazumiLogger().w('Danmaku: unable to hash local file $filePath');
      return DanmakuMatchResponse.empty;
    }
    final fileSize = await readFileSize(filePath);
    final fileName = p.basenameWithoutExtension(filePath);

    final endPoint = ApiEndpoints.dandanAPIDomain + ApiEndpoints.dandanAPIMatch;
    KazumiLogger()
        .i('Danmaku: matching local file "$fileName" (size: $fileSize)');

    final jsonData = await _client.post(endPoint, data: {
      'fileName': fileName,
      'fileHash': fileHash,
      'fileSize': fileSize,
      'videoDuration': 0,
      'matchMode': 'hashAndFileName',
    });
    if (jsonData is! Map) {
      return DanmakuMatchResponse.empty;
    }
    return DanmakuMatchResponse.fromJson(Map<String, dynamic>.from(jsonData));
  }

  // 从BangumiID获取分集ID
  static Future<DanmakuEpisodeResponse> getDanmakuEpisodesByBangumiID(
      int bangumiID) async {
    var path = ApiEndpoints.formatUrl(
        ApiEndpoints.dandanAPIInfoByBgmBangumiId, [bangumiID]);
    var endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(endPoint);
    DanmakuEpisodeResponse danmakuEpisodeResponse =
        DanmakuEpisodeResponse.fromJson(jsonData);
    return danmakuEpisodeResponse;
  }

  // 从DanDanBangumiID获取分集ID
  static Future<DanmakuEpisodeResponse> getDanDanEpisodesByDanDanBangumiID(
      int bangumiID) async {
    var path = ApiEndpoints.dandanAPIInfo + bangumiID.toString();
    var endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(endPoint);
    DanmakuEpisodeResponse danmakuEpisodeResponse =
        DanmakuEpisodeResponse.fromJson(jsonData);
    return danmakuEpisodeResponse;
  }

  // 从标题检索DanDan番剧数据库
  static Future<DanmakuSearchResponse> getDanmakuSearchResponse(
      String title) async {
    var path = ApiEndpoints.dandanAPISearch;
    var endPoint = ApiEndpoints.dandanAPIDomain + path;
    Map<String, String> keywordMap = {
      'keyword': title,
    };

    final jsonData = await _client.get(endPoint, queryParameters: keywordMap);
    DanmakuSearchResponse danmakuSearchResponse =
        DanmakuSearchResponse.fromJson(jsonData);
    return danmakuSearchResponse;
  }

  static Future<List<DanmakuEntry>> getDanDanmaku(
      int bangumiID, int episode) async {
    List<DanmakuEntry> danmakus = [];
    if (bangumiID == 0) {
      return danmakus;
    }
    // 关键修正：不再猜测 `animeId * 10000 + 集数` 的弹幕库 ID。
    // 该命名规则并未写入弹弹 Play 官方文档，对大量番剧（尤其新番、多季、合集）
    // 都不成立，会直接表现为“弹弹明明有该番剧弹幕库却关联不到”。
    // 改为查询番剧真实分集列表，按集数定位 episodeId 后再取弹幕。
    final episodeId = await _resolveDanDanEpisodeId(bangumiID, episode);
    if (episodeId == 0) {
      KazumiLogger().w(
          'Danmaku: cannot resolve episodeId for bangumi $bangumiID episode $episode');
      return danmakus;
    }
    return await getDanDanmakuByEpisodeID(episodeId);
  }

  /// 在弹弹番剧分集列表中按集数定位真实 episodeId。
  ///
  /// 1. 优先按分集标题中解析出的集数匹配（兼容 "01" / "1" / "第1话" / "EP1" 等写法）；
  /// 2. 退化时按数组下标匹配（TV 番剧通常顺序即集数）。
  static Future<int> _resolveDanDanEpisodeId(int bangumiID, int episode) async {
    try {
      final resp = await getDanDanEpisodesByDanDanBangumiID(bangumiID);
      if (!resp.success || resp.episodes.isEmpty) {
        return 0;
      }
      for (final ep in resp.episodes) {
        if (_parseEpisodeNumber(ep.episodeTitle) == episode) {
          return ep.episodeId;
        }
      }
      if (episode >= 1 && episode <= resp.episodes.length) {
        return resp.episodes[episode - 1].episodeId;
      }
    } catch (e) {
      KazumiLogger().w('Danmaku: failed to resolve episodeId', error: e);
    }
    return 0;
  }

  static int _parseEpisodeNumber(String title) {
    final match = RegExp(r'(\d+)').firstMatch(title.trim());
    if (match == null) return -1;
    return int.tryParse(match.group(1)!) ?? -1;
  }

  static Future<List<DanmakuEntry>> getDanDanmakuByEpisodeID(
      int episodeID) async {
    var path = ApiEndpoints.dandanAPIComment + episodeID.toString();
    var endPoint = ApiEndpoints.dandanAPIDomain + path;
    List<DanmakuEntry> danmakus = [];
    Map<String, String> withRelated = {
      'withRelated': 'true',
    };
    final jsonData = await _client.get(endPoint, queryParameters: withRelated);
    List<dynamic> comments = jsonData['comments'];

    for (var comment in comments) {
      DanmakuEntry danmaku = DanmakuEntry.fromJson(comment);
      danmakus.add(danmaku);
    }
    return danmakus;
  }
}
