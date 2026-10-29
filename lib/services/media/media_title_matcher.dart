import 'dart:math' as math;

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/utils/chinese_convert.dart';

/// 番剧标题匹配工具：媒体库搜刮与磁力下载的「资源归属」判定共用。
///
/// 磁力搜索页从番剧详情进入时会带上该番剧作为默认归属，但用户随后可能
/// 换关键词去搜别的番剧。这里提供统一的判定口径：资源标题与番剧标题
/// （含别名）的相似度，低于阈值时必须放弃关联，改走下载完成后的自动搜刮，
/// 否则会把别的番剧刮成详情页那一部。
class MediaTitleMatcher {
  MediaTitleMatcher._();

  /// 低于该分数视为「不是这部番」。
  static const double matchThreshold = 0.4;

  /// 达到该分数视为「基本确定是这部番」。
  static const double highConfidenceThreshold = 0.9;

  /// 子串匹配时，条目名作为片段的最小长度。
  static const int _kMinFragmentNameLength = 4;

  /// 子串匹配时，条目名至少占关键词的比例。
  static const double _kMinFragmentCoverage = 0.5;

  static const int _kMinLcsLength = 3;
  static const double _kMinLcsRatio = 0.7;

  /// 参与标题匹配的名字最小长度：单字名（如「月」）几乎必然在字幕组名、
  /// 分辨率、集数等噪声里误命中，不参与资源归属判定。
  static const int _kMinTitleNameLength = 2;

  /// 达到该长度的名字在资源标题中命中时视为强证据。
  static const int _kStrongTitleNameLength = 4;

  /// 达到该长度的名字几乎不可能误命中（中文番名通常 5 字以上）。
  static const int _kVeryStrongTitleNameLength = 6;

  /// 归一化用于比较的字符串：转小写 + 去装饰符号 + **繁体转简体**。
  ///
  /// 繁简归一是关键：台配源（[ANi]/[Baha]）标题是繁体，而 Bangumi
  /// 条目名基本是简体或日文原名，不归一就永远打不上分。
  static String normalize(String s) {
    return toSimplifiedChinese(s)
        .toLowerCase()
        // `×` 是乘号，`x` 是字母：统一成 `x`。既保留 `HUNTER×HUNTER` /
        // `xxxHOLiC` 与普通短名的区分度，又让 `Hunter x Hunter` 仍能匹配。
        .replaceAll('×', 'x')
        .replaceAll(
            RegExp(r'''[\s\-_·・.。:：（）()\[\]【】{}「」『』"'~～+*]'''), '');
  }

  /// 番剧的候选标题（已归一化，去重、去空、过滤过短的名字）。
  static List<String> normalizedTitles({
    String name = '',
    String nameCn = '',
    Iterable<String> alias = const [],
  }) {
    final seen = <String>{};
    final titles = <String>[];
    for (final raw in [nameCn, name, ...alias]) {
      final normalized = normalize(raw);
      if (normalized.length < _kMinTitleNameLength) continue;
      if (seen.add(normalized)) titles.add(normalized);
    }
    return titles;
  }

  /// 关键词与条目名称的相似度（0~1）。
  static double nameSimilarity(String keyword, String name) {
    if (keyword.isEmpty || name.isEmpty) return 0;
    if (keyword == name) return 1.0;
    // 关键词是条目名的一部分：短关键词匹配更完整的长标题。
    if (name.contains(keyword)) return 0.9;
    // 条目名是关键词的一部分：只有片段足够长、占比足够高时才可信。
    // 否则「关于我转生变成史莱姆这档事」会命中条目「史莱姆」。
    if (keyword.contains(name)) {
      if (name.length < _kMinFragmentNameLength) return 0;
      final coverage = name.length / keyword.length;
      if (coverage < _kMinFragmentCoverage) return 0;
      return 0.75 * coverage;
    }
    // 最长公共子串占比兜底：分母取较长串，避免长关键词配短条目时虚高。
    final lcs = longestCommonSubstring(keyword, name);
    if (lcs.length < _kMinLcsLength) return 0;
    final ratio = lcs.length / math.max(keyword.length, name.length);
    return ratio >= _kMinLcsRatio ? ratio * 0.8 : 0;
  }

  /// 最长公共子串：滚动数组实现，避免每个别名都分配 O(n·m) 二维表。
  static String longestCommonSubstring(String a, String b) {
    if (a.isEmpty || b.isEmpty) return '';
    var prev = List<int>.filled(b.length + 1, 0);
    var curr = List<int>.filled(b.length + 1, 0);
    var maxLen = 0;
    var endIndex = 0;
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        if (a[i - 1] == b[j - 1]) {
          curr[j] = prev[j - 1] + 1;
          if (curr[j] > maxLen) {
            maxLen = curr[j];
            endIndex = i;
          }
        } else {
          curr[j] = 0;
        }
      }
      final swap = prev;
      prev = curr;
      curr = swap;
      // 复用行必须清零，否则上一轮的值会残留到下一次遍历。
      for (var j = 0; j < curr.length; j++) {
        curr[j] = 0;
      }
    }
    return maxLen == 0 ? '' : a.substring(endIndex - maxLen, endIndex);
  }

  /// 资源标题与该番剧的相似度（0~1）。
  ///
  /// 磁力资源标题通常是「[字幕组] 番剧名 第01话 [1080p][CHT]」这类长串，
  /// 直接与番剧名做整体相似度会被噪声淹没，因此判定顺序是：
  /// 1. 标题包含候选名（中文名 / 原名 / 别名）→ 强证据；
  /// 2. 标题包含当前搜索词，且搜索词确实指向该番剧 → 中等证据
  ///    （覆盖标题使用罗马音、而 Bangumi 别名未收录的情况）。
  static double scoreTitle(
    String title, {
    String name = '',
    String nameCn = '',
    Iterable<String> alias = const [],
    String? queryHint,
  }) {
    final normalizedTitle = normalize(title);
    if (normalizedTitle.isEmpty) return 0;
    final names = normalizedTitles(name: name, nameCn: nameCn, alias: alias);
    if (names.isEmpty) return 0;

    var best = 0.0;
    for (final candidate in names) {
      if (normalizedTitle == candidate) return 1.0;
      if (!normalizedTitle.contains(candidate)) continue;
      // 名字越短越容易出现在字幕组名、其它番剧标题里：短名的命中只用来
      // 保留归属（不丢信息），但不给到自动入库的置信度，避免搬错文件。
      final double score;
      if (candidate.length >= _kVeryStrongTitleNameLength) {
        score = 0.95;
      } else if (candidate.length >= _kStrongTitleNameLength) {
        score = 0.9;
      } else {
        score = 0.6;
      }
      best = math.max(best, score);
    }
    if (best > 0) return best;

    final hint = normalize(queryHint ?? '');
    if (hint.length >= _kMinTitleNameLength &&
        normalizedTitle.contains(hint) &&
        matchesAnyName(hint, names)) {
      return 0.85;
    }
    return 0;
  }

  /// 搜索词是否仍指向该番剧（用于「换关键词后自动解除关联」的判定）。
  static bool queryMatchesBangumi(String query, BangumiItem item) {
    final normalizedQuery = normalize(query);
    if (normalizedQuery.isEmpty) return true;
    return matchesAnyName(
      normalizedQuery,
      normalizedTitles(
        name: item.name,
        nameCn: item.nameCn,
        alias: item.alias,
      ),
    );
  }

  /// 归一化后的关键词是否与任一候选名匹配。
  static bool matchesAnyName(String normalizedQuery, List<String> names) {
    if (normalizedQuery.isEmpty) return false;
    for (final name in names) {
      if (normalizedQuery == name) return true;
      if (normalizedQuery.contains(name)) return true;
      if (name.contains(normalizedQuery) &&
          normalizedQuery.length >= _kMinFragmentNameLength) {
        return true;
      }
      if (nameSimilarity(normalizedQuery, name) >= matchThreshold) return true;
    }
    return false;
  }

  /// 结合资源标题修正下载归属。
  ///
  /// - 明显不是该番剧（分数低于 [matchThreshold]）：丢弃归属信息，
  ///   由下载完成后的自动搜刮重新识别；
  /// - 可信但不确定：保留归属信息并把分数作为置信度，自动入库的阈值
  ///   判断会自然拦下（默认 0.7），只同步搜刮结果、不移动文件；
  /// - 高置信度：置信度按 1.0 处理，与用户主动关联的语义一致。
  static ({MediaScrapeInfo? info, double confidence}) resolveScrapeInfo({
    required String title,
    required MediaScrapeInfo? info,
    BangumiItem? anime,
    String? queryHint,
  }) {
    if (info == null) return (info: null, confidence: 0);
    // 只有 [anime] 与 [info] 指向同一部番剧时才用它补别名：用户在下载
    // 确认框里改成别的番剧后，两者会不一致，此时必须按新选的番剧评分。
    final resolvedAnime =
        anime != null && info.id > 0 && anime.id == info.id ? anime : null;
    final score = resolvedAnime != null
        ? scoreTitle(
            title,
            name: resolvedAnime.name,
            nameCn: resolvedAnime.nameCn,
            alias: resolvedAnime.alias,
            queryHint: queryHint,
          )
        : scoreTitle(
            title,
            name: info.name,
            nameCn: info.nameCn,
            queryHint: queryHint,
          );
    if (score < matchThreshold) return (info: null, confidence: 0);
    if (score >= highConfidenceThreshold) return (info: info, confidence: 1.0);
    return (info: info, confidence: score);
  }
}
