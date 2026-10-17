import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/search/image_search_module.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/apis/trace_api.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/media/video_frame_extractor.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/chinese_convert.dart';
import 'package:path/path.dart' as p;

/// 单个文件夹的搜刮结果。
class FolderScrapeResult {
  const FolderScrapeResult({
    required this.folderPath,
    required this.keyword,
    required this.status,
    this.info,
    this.confidence = 0,
    this.error,
  });

  final String folderPath;

  /// 实际用于搜索的关键词。
  final String keyword;

  final ScrapeStatus status;

  /// 匹配到的番剧信息，未命中时为 null。
  final MediaScrapeInfo? info;

  /// 0~1 之间的匹配置信度。
  final double confidence;

  /// 出错时的错误信息。
  final String? error;
}

/// 一个文件夹的搜刮状态。
enum ScrapeStatus {
  /// 搜刮成功，已匹配。
  matched,

  /// 搜索完成但没有找到符合的结果。
  notFound,

  /// 网络或解析出错。
  error,
}

/// 单次批量搜刮的进度回调。
class ScrapeProgress {
  const ScrapeProgress({
    required this.done,
    required this.total,
    required this.matched,
    required this.failed,
    this.currentFolder,
    this.currentKeyword,
    this.aborted = false,
  });

  final int done;
  final int total;

  /// 已匹配的文件夹数。
  final int matched;

  /// 匹配失败（含未找到或出错）的文件夹数。
  final int failed;

  /// 当前正在搜刮的文件夹名。
  final String? currentFolder;

  /// 当前正在使用的搜索关键词。
  final String? currentKeyword;

  /// 是否因连续网络失败提前中止（未处理的文件夹保持原结果）。
  final bool aborted;
}

/// 媒体搜刮器：将文件夹/文件名清洗为番剧关键词，再查询 Bangumi 获取元数据。
///
/// 参考弹弹 play 媒体库的做法：
/// 1. 解析文件名得到「标题 + 季数」信息；
/// 2. 使用多个候选关键词搜索（清洗后的标题 → 原文件夹名 → 内部文件名）；
/// 3. 对候选结果进行置信度打分，命中率过低时宁可判定为未匹配，也不强行塞一个错误结果。
class MediaScraper {
  MediaScraper();

  /// 单个标题最多派生的候选关键词数，避免一个文件夹打爆搜索接口。
  static const int _kMaxKeywordVariants = 6;

  /// 批量搜刮的文件夹级并发数。过高会放大镜像限流风险，3 已能显著缩短总耗时。
  static const int _kMaxConcurrentFolderScrapes = 3;

  /// 连续多少个文件夹出错后中止本批搜刮（网络中断 / 镜像不可用）。
  static const int _kMaxConsecutiveFailures = 5;

  /// 每批搜刮最多实际请求 trace.moe 的次数。
  ///
  /// 匿名额度约为 10 次/分钟、150 次/天；批量库远超这个量级，必须有硬上限。
  static const int _kMaxImageTracePerBatch = 10;

  /// 每天最多实际请求 trace.moe 的次数（匿名额度约 150/天，留出余量）。
  static const int _kMaxImageTracePerDay = 100;

  /// 图片兜底拿到 AniList 标题后，最多再回搜 Bangumi 的标题数。
  static const int _kMaxAniListTitleCandidates = 6;

  /// 匹配置信度阈值：低于该值视为未命中。
  static const double _kMatchThreshold = 0.4;

  /// 达到该置信度即短路，不再尝试后续候选。
  static const double _kHighConfidenceThreshold = 0.9;

  /// 中低置信度时要求的「最优 - 次优」差距。
  static const double _kSecondBestGap = 0.1;

  /// 子串匹配时，条目名作为片段的最小长度。
  static const int _kMinFragmentNameLength = 4;

  /// 子串匹配时，条目名至少占关键词的比例。
  static const double _kMinFragmentCoverage = 0.5;

  /// LCS 兜底要求的最小公共子串长度与占比。
  static const int _kMinLcsLength = 3;
  static const double _kMinLcsRatio = 0.7;

  /// 搜索缓存：同一个关键词在批量 / 多分组 / 重跑时只请求一次。
  static const int _kSearchCacheMaxEntries = 128;
  static const Duration _kSearchCacheTtl = Duration(minutes: 10);
  static const Duration _kSearchNegativeTtl = Duration(minutes: 3);
  static final Map<String, _SearchCacheEntry> _searchCache = {};
  static final Map<String, Future<List<BangumiItem>?>> _searchInFlight = {};

  /// trace.moe 结果缓存：同一文件（路径 + 大小 + 修改时间）只抽帧识别一次。
  static const int _kTraceCacheMaxEntries = 100;
  static const Duration _kTraceCacheTtl = Duration(hours: 1);
  static final Map<String, _TraceCacheEntry> _traceCache = {};

  /// 常见「无意义占位标题」：测试/下载/临时目录等。
  ///
  /// 这类名称几乎不可能是番剧名，直接拿它们搜索 Bangumi 只会浪费请求，
  /// 还可能误匹配到无关条目（如把 `test` 目录匹配成某部名字含 test 的番）。
  /// 搜刮时对自动派生的候选做拦截，用户手动指定的关键词不受影响。
  static const Set<String> _kGenericTitles = {
    'test', 'tests', 'testing',
    'sample', 'samples',
    'demo', 'trial',
    'temp', 'tmp',
    'download', 'downloads',
    'untitled', 'misc', 'miscellaneous',
    'other', 'others', 'various', 'stuff',
    'backup', 'backups', 'copy', 'copies',
    'new folder', 'untitled folder',
    '测试', '测试视频', '示例', '样例', '试用',
    '下载', '临时', '临时文件',
    '新建文件夹', '未命名', '未命名文件夹',
    '其他', '杂项', '备份',
  };

  /// 判定清洗后的标题是否是「无意义的占位标题」（如 test、新建文件夹）。
  ///
  /// 大小写不敏感；容忍数字/括号后缀变体（`test1`、`测试2`、`新建文件夹(3)`）。
  /// 纯数字正名（如《86》）剥掉后缀后为空，不会误伤。
  bool isGenericTitle(String title) {
    var t = title.trim().toLowerCase();
    if (t.isEmpty) return true;
    if (_kGenericTitles.contains(t)) return true;
    // 数字后缀变体：先剥括号数字，再剥尾部的数字/分隔符。
    // 命中名单才是最终判据，「86」剥空后落不进名单。
    t = t
        .replaceFirst(RegExp(r'\s*\(\d+\)\s*$'), '')
        .replaceFirst(RegExp(r'[\d\s_\-.]*$'), '');
    return t.length >= 2 && _kGenericTitles.contains(t);
  }

  /// 取出「basename」，仅在末尾是真正的视频扩展名时去掉扩展名。
  ///
  /// 不能用 `p.basenameWithoutExtension`：文件夹名里如果自带点号
  /// （如 `[Sakurato.sub]...` / `Tomb.Raider.King...`）会被拦腰截断。
  String _baseName(String raw) {
    var base = p.basename(raw);
    final lower = base.toLowerCase();
    for (final ext in kLocalMediaExtensions) {
      if (lower.endsWith(ext)) {
        base = base.substring(0, base.length - ext.length);
        break;
      }
    }
    return base;
  }

  /// 清洗文件夹或文件名，提取可能的番剧标题。
  ///
  /// 移除常见的发布组标签、分辨率、编码、集数等噪音。
  /// 会尽可能保留「季数」「年份」信息，供后续匹配使用（见 [parseSeason]）。
  String cleanName(String raw) {
    var name = _process(name: _baseName(raw));
    // 方括号里藏着番剧名的情况（如 `[Sakurato.sub][Lonely...`）：
    // 兜底取「最长的、清洗后可读」的那个括号内容当作标题。
    if (name.isEmpty) {
      name = _longestBracketTitle(raw);
    }
    return name;
  }

  /// 从方括号里挑出一个最可能是番剧标题的内容。
  String _longestBracketTitle(String raw) {
    final matches = RegExp(r'\[([^\]]+)\]').allMatches(raw).toList();
    String best = '';
    for (final m in matches) {
      final cleaned = _process(name: m.group(1)!);
      if (cleaned.length > best.length) {
        best = cleaned;
      }
    }
    return best;
  }

  /// 核心清洗流程。
  String _process({required String name}) {

    // 移除方括号内容 [xxx] —— 通常是发布组/分辨率
    name = name.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    // 移除圆括号内容 (xxx)
    name = name.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    // 移除全角圆括号 （xxx） —— 台配源常用，如 `（僅限港澳台）`
    name = name.replaceAll(RegExp(r'（[^）]*）'), ' ');
    // 移除【xxx】
    name = name.replaceAll(RegExp(r'【[^】]*】'), ' ');
    // 移除花括号 {xxx}
    name = name.replaceAll(RegExp(r'\{[^}]*\}'), ' ');

    // 移除播出地区/语言限定标记（未被括号包住时的兜底）
    name = name.replaceAll(
      RegExp(r'(僅限|仅限)?(港澳台|台澎金馬|台澎金马|臺灣|台灣|台湾)(地區|地区)?'),
      ' ',
    );

    // 移除分辨率/编码标签
    name = name.replaceAll(
      RegExp(
        r'\b(1080[pi]|720p|480p|2160p|4k|8k|av1|h\.?26[45]|x\.?26[45]|hevc|aac|flac|mp3|10bit|hi10)\b',
        caseSensitive: false,
      ),
      ' ',
    );

    // 移除集数标记：EP01, 第01话, 第01集, - 01, _01, .01, [01], 01v2, S01E01(-E02)
    name = name.replaceAll(RegExp(r'\bEP?\s*\d+\b', caseSensitive: false), ' ');
    name = name.replaceAll(RegExp(r'第\s*\d+\s*[话話集]'), ' ');
    name = name.replaceAll(RegExp(r'\bS\d+E\d+(?:\s*-\s*E\s*\d+)?\b', caseSensitive: false), ' ');
    // 点号分隔的集数必须在 `.`→空格 之前处理，否则 `Show.Name.-.01`
    // 里的 `-` 与 `01` 隔着点号，匹配不到而残留成关键词。
    name = name.replaceAll(RegExp(r'[.\-_]\s*\d{1,3}\s*(v\d+)?\s*$'), '');
    name = name.replaceAll(RegExp(r'\b\d{1,3}\s*v\d+\b'), ' ');

    // 移除 BD/DVD/WEB/Remux 等来源标记
    name = name.replaceAll(
      RegExp(r'(?<![A-Za-z0-9])(bd|dvd|web|remux|rip|cam|ts)(?![A-Za-z0-9])',
          caseSensitive: false),
      ' ',
    );

    // 移除地区/语言/版本标记（JPN、CHS、GB、Pre-release 等）
    name = name.replaceAll(
      RegExp(r'(?<![A-Za-z0-9])(ja|jpn|jp|chs|sc|gb|cht|tc|pre[-\s]?release|release|v\d+)(?![A-Za-z0-9])',
          caseSensitive: false),
      ' ',
    );

    // 全角标点归一为半角：`Re：從零開始…` 与条目名 `Re:从零开始…` 只差一个冒号，
    // 不归一会白白丢掉召回。
    name = name
        .replaceAll('：', ':')
        .replaceAll('！', '!')
        .replaceAll('？', '?')
        .replaceAll('，', ',')
        .replaceAll('　', ' ');

    // 点号分隔转空格
    name = name.replaceAll('.', ' ');

    // 合并多余空白
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 移除首尾的连字符/下划线/点
    name = name.replaceAll(RegExp(r'^[-_.\s]+|[-_.\s]+$'), '');

    return name;
  }

  /// 从文件夹名/文件名解析季数（S02、Season 2、第二季、二期……）。
  ///
  /// 返回 null 表示未检测到季数。
  int? parseSeason(String raw) {
    final base = _baseName(raw);
    final lower = base.toLowerCase();

    // S2 / Season 2
    final en = RegExp(r'(?:^|[^a-z])(?:s|season)\s*(\d{1,2})(?:[^a-z0-9]|$)',
        caseSensitive: false).firstMatch(lower);
    if (en != null) {
      return _clampSeason(en.group(1));
    }

    // 1st Season / 2nd Season
    final ordinal = RegExp(
      r'(?:^|[^a-z])(\d{1,2})(?:st|nd|rd|th)\s+season\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (ordinal != null) {
      return _clampSeason(ordinal.group(1));
    }

    // 第二季 / 第二期 / 第二部 / 【2季】
    final cnMatch =
        RegExp(r'第\s*([一二三四五六七八九十1-9１-９0-9]+)\s*[季期部]').firstMatch(base);
    if (cnMatch != null) {
      return _toArabicSeason(cnMatch.group(1)!);
    }

    // 2期：不能依赖 `\b`——Dart 的单词边界是 ASCII 语义，`期` 不是单词字符，
    // 尾部 `\b` 永远不成立。
    final suffix = RegExp(r'(?:^|[^0-9０-９])([1-9１-９])\s*期').firstMatch(base);
    if (suffix != null) {
      final n = _toArabicSeason(suffix.group(1)!);
      if (n != null && n > 1) return n;
    }
    return null;
  }

  /// 从文件夹/视频名中提取「年」标记，如 (2021)/[2021]。
  int? parseYear(String raw) {
    final m = RegExp(r'((?:19|20)\d{2})').firstMatch(raw);
    if (m == null) return null;
    final year = int.tryParse(m.group(1)!);
    if (year == null) return null;
    final now = DateTime.now().year;
    return (year >= 1990 && year <= now + 1) ? year : null;
  }

  int? _clampSeason(dynamic raw) {
    final season = int.tryParse(raw.toString());
    if (season == null || season < 1 || season > 99) return null;
    return season;
  }

  int? _toArabicSeason(String value) {
    const map = {
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
      '六': 6, '七': 7, '八': 8, '九': 9, '1': 1, '2': 2,
      '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9,
    };
    // 全角数字归一，`２期` 与 `2期` 等价。
    final v = value.trim().replaceAllMapped(
          RegExp(r'[０-９]'),
          (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFF10 + 0x30),
        );
    if (v == '十') return 10;
    if (v.length >= 2 && v.startsWith('十')) {
      return 10 + map[v.substring(1)]!;
    }
    return map[v];
  }

  /// 归一化用于比较的字符串：转小写 + 去装饰符号 + **繁体转简体**。
  ///
  /// 繁简归一是关键：台配源（[ANi]/[Baha]）标题是繁体，而 Bangumi
  /// 条目名基本是简体或日文原名，不归一就永远打不上分。
  String _normalize(String s) {
    return toSimplifiedChinese(s)
        .toLowerCase()
        // `×` 是乘号，`x` 是字母：统一成 `x`。既保留 `HUNTER×HUNTER` /
        // `xxxHOLiC` 与普通短名的区分度，又让 `Hunter x Hunter` 仍能匹配。
        .replaceAll('×', 'x')
        .replaceAll(
            RegExp(r'''[\s\-_·・.。:：（）()\[\]【】{}「」『』"'~～+*]'''), '');
  }

  /// 去掉标题里的「季数标记及其之后的一切」，得到主标题。
  ///
  /// 台配标题常把季数和分篇一起堆在后面，整段丢弃才能拿到可搜索的主名：
  /// - `歡迎來到實力至上主義的教室 第四季 2年級篇 第一學期` → `歡迎來到實力至上主義的教室`
  /// - `杖與劍的魔劍譚 Season 2` → `杖與劍的魔劍譚`
  String stripSeasonSuffix(String title) {
    var out = title;
    // 中文：第X季 / 第X期 / 第X部（连同其后的副标题一并丢弃）
    out = out.replaceFirst(
        RegExp(r'\s*第\s*[一二三四五六七八九十\d１-９]+\s*[季期部].*$'), '');
    // 英文：Season 2 / S2 / 2nd Season / Final Season（必须在结尾且前有分隔）
    out = out.replaceFirst(
      RegExp(
        r'\s+(?:season\s*\d{1,2}|s\d{1,2}|\d{1,2}(?:st|nd|rd|th)\s+season|final\s+season)\s*$',
        caseSensitive: false,
      ),
      '',
    );
    return out.trim();
  }

  /// 去掉「～副标题～」「 -Sub Title- 」这类装饰性副标题。
  ///
  /// - `無職轉生～到了異世界就拿出真本事～` → `無職轉生`
  /// - `ATRI -My Dear Moments-` → `ATRI`
  ///
  /// 不处理冒号副标题：`Re:從零開始的異世界生活` 砍掉冒号后只剩 `Re`，得不偿失。
  String stripSubtitle(String title) {
    var out = title;
    // 全角波浪号副标题：从第一个波浪号起整段丢弃
    out = out.replaceFirst(RegExp(r'\s*[～〜].*$'), '');
    // 破折号引导的英文副标题：`ATRI -My Dear Moments-` → `ATRI`。
    // 要求破折号前有空格，避免误伤 `86-Eighty Six` 这类连字正名；
    // 收尾破折号可选，因为 _process 会把结尾的连字符先行剥掉。
    out = out.replaceFirst(RegExp(r'\s+-\s*[^-]{2,}-?\s*$'), '');
    return out.trim();
  }

  /// 由一个清洗后的标题派生出多个搜索候选关键词，按「命中概率」降序排列。
  ///
  /// 逐层剥离（原标题 → 去季数 → 去副标题），每层都产出简体与原文两版；
  /// **简体版全部排在前面**，因为 Bangumi 条目名以简体/日文原名为主，
  /// 繁体关键词几乎必然是 0 结果，排后面可以少发无谓请求。
  List<String> expandKeyword(String title) {
    final bases = <String>[title];
    void addBase(String value) {
      final v = value.trim();
      if (v.length < 2 || bases.contains(v)) return;
      bases.add(v);
    }

    addBase(stripSeasonSuffix(title));
    for (final b in List<String>.from(bases)) {
      addBase(stripSubtitle(b));
    }

    final simplified = <String>[];
    final originals = <String>[];
    for (final b in bases) {
      final s = toSimplifiedChinese(b);
      simplified.add(s);
      if (s != b) originals.add(b);
    }

    final ordered = <String>[];
    for (final v in [...simplified, ...originals]) {
      final t = v.trim();
      if (t.length < 2 || ordered.contains(t)) continue;
      ordered.add(t);
    }
    return ordered.length <= _kMaxKeywordVariants
        ? ordered
        : ordered.sublist(0, _kMaxKeywordVariants);
  }

  /// 搜索单个文件夹，返回结果（可能未命中）。
  ///
  /// [keyword] 非空时使用指定关键词；否则自动尝试多个候选关键词。
  /// 全部失败时，若开启了图片识别兜底，会用视频抽帧走 trace.moe 以图搜番。
  ///
  /// [isCancelled] 在候选之间检查，取消后立即停止当前文件夹；
  /// [reserveTrace] 由批量搜刮注入，用于限制每批 trace.moe 调用次数。
  Future<FolderScrapeResult> scrapeFolder({
    required LocalMediaFolder folder,
    String? keyword,
    bool Function()? isCancelled,
    bool Function()? reserveTrace,
  }) async {
    try {
      _throwIfCancelled(isCancelled);
      final candidates = _buildCandidates(
        folder,
        keyword: keyword,
      );

      // 不在第一个命中处直接返回：低置信度结果可能只是短名误配，
      // 继续尝试后续候选，只有 ≥0.9 才短路。
      _Match? bestAcrossCandidates;
      String? bestKeyword;
      for (final candidate in candidates) {
        _throwIfCancelled(isCancelled);
        if (candidate.keyword.isEmpty) continue;
        final items = await _search(candidate.keyword);
        if (items == null) {
          // 搜索失败（网络 / 解析）不能当成「没找到」，否则会白跑图片兜底。
          throw _SearchFailedException(candidate.keyword);
        }
        if (items.isEmpty) continue;

        final best = _bestMatch(
          candidate.keyword,
          items,
          season: candidate.season,
          year: candidate.year,
        );
        if (best == null) continue;
        if (best.confidence >= _kHighConfidenceThreshold) {
          return _matched(folder, candidate.keyword, best);
        }
        if (bestAcrossCandidates == null ||
            best.confidence > bestAcrossCandidates.confidence) {
          bestAcrossCandidates = best;
          bestKeyword = candidate.keyword;
        }
      }

      if (bestAcrossCandidates != null && bestKeyword != null) {
        return _matched(folder, bestKeyword, bestAcrossCandidates);
      }

      _throwIfCancelled(isCancelled);
      // 文件名文本匹配全部失败 → 图片识别兜底，尽快中止后续无谓请求
      final imageResult = await _scrapeByImageTrace(
        folder,
        isCancelled: isCancelled,
        reserveTrace: reserveTrace,
      );
      if (imageResult != null) {
        return imageResult;
      }

      return FolderScrapeResult(
        folderPath: folder.path,
        keyword: keyword ?? cleanName(folder.name),
        status: ScrapeStatus.notFound,
      );
    } on _ScrapeCancelled {
      rethrow;
    } catch (e) {
      KazumiLogger().w('MediaScraper: search failed for "${folder.name}"',
          error: e);
      return FolderScrapeResult(
        folderPath: folder.path,
        keyword: keyword ?? cleanName(folder.name),
        status: ScrapeStatus.error,
        error: '$e',
      );
    }
  }

  FolderScrapeResult _matched(
    LocalMediaFolder folder,
    String keyword,
    _Match match,
  ) =>
      FolderScrapeResult(
        folderPath: folder.path,
        keyword: keyword,
        status: ScrapeStatus.matched,
        info: match.info,
        confidence: match.confidence,
      );

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() == true) throw const _ScrapeCancelled();
  }

  /// 带 LRU + TTL 的 Bangumi 搜索。
  ///
  /// 返回 null 表示请求失败（不缓存，交给调用方判 error）；
  /// 返回空列表表示搜索成功但没有结果（负缓存，短时间内不重复请求）。
  /// 同一关键词的并发请求会共享同一个 Future，避免多季文件夹同时开搜时重复发请求。
  Future<List<BangumiItem>?> _search(String keyword) async {
    final key = keyword.trim().toLowerCase();
    final cached = _searchCache[key];
    if (cached != null) {
      if (DateTime.now().isBefore(cached.expiresAt)) {
        // LRU touch：重新插入到队尾。
        _searchCache.remove(key);
        _searchCache[key] = cached;
        return cached.items;
      }
      _searchCache.remove(key);
    }

    final inFlight = _searchInFlight[key];
    if (inFlight != null) return inFlight;

    final future = _fetchSearch(keyword, key);
    _searchInFlight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_searchInFlight[key], future)) {
        _searchInFlight.remove(key);
      }
    }
  }

  Future<List<BangumiItem>?> _fetchSearch(String keyword, String key) async {
    // 搜刮要的是「文本最像」，不是「最热门」；match 是 Bangumi 的相关度排序。
    var page =
        await BangumiApi.bangumiSearch(keyword, limit: 20, sort: 'match');
    // 镜像 / 旧接口不认识 match 时回退 heat，避免整个搜刮链路失效。
    page ??= await BangumiApi.bangumiSearch(keyword, limit: 20);
    if (page == null) return null;

    final items = page.items;
    final ttl = items.isEmpty ? _kSearchNegativeTtl : _kSearchCacheTtl;
    _searchCache[key] = _SearchCacheEntry(items, DateTime.now().add(ttl));
    while (_searchCache.length > _kSearchCacheMaxEntries) {
      _searchCache.remove(_searchCache.keys.first);
    }
    return items;
  }

  /// 图片识别兜底：取文件夹内首个视频抽帧 → trace.moe 识别番剧 → Bangumi 标题匹配。
  ///
  /// 成功时返回匹配结果；不可用 / 识别失败 / 相似度过低时返回 null。
  /// 同一文件（路径 + 大小 + 修改时间）的识别结果会在进程内缓存，
  /// 重复搜刮不再抽帧、不再请求 trace.moe。
  Future<FolderScrapeResult?> _scrapeByImageTrace(
    LocalMediaFolder folder, {
    bool Function()? isCancelled,
    bool Function()? reserveTrace,
  }) async {
    bool enabled;
    try {
      enabled =
          GStorage.getSetting(SettingsKeys.localMediaTraceFallback);
    } catch (_) {
      enabled = false;
    }
    if (!enabled) return null;

    // 测试环境无 ffmpeg 时也应快速跳过。
    if (!VideoFrameExtractor.instance.isAvailable) {
      KazumiLogger().d(
          'MediaScraper: trace fallback skipped, ffmpeg unavailable');
      return null;
    }

    // 优先用体积最大的视频文件（通常为正片本体而非片头预告/特典）
    LocalMediaFile? pick;
    for (final f in folder.files) {
      if (pick == null || f.size > pick.size) {
        pick = f;
      }
    }
    if (pick == null) return null;

    final cacheKey = _traceCacheKey(pick);
    final now = DateTime.now();
    Anilist? anilist;
    double similarity = 0;

    final cached = _traceCache[cacheKey];
    if (cached != null && now.isBefore(cached.expiresAt)) {
      anilist = cached.anilist;
      similarity = cached.similarity;
      _traceCache.remove(cacheKey);
      _traceCache[cacheKey] = cached;
    } else {
      if (cached != null) _traceCache.remove(cacheKey);
      // 预留名额：并发 worker 里 check-then-decrement 会互相越界，
      // 这里把「检查 + 扣减」合成一次同步调用。
      if (reserveTrace?.call() == false) return null;
      if (!await _consumeTraceQuota()) {
        KazumiLogger().i('MediaScraper: daily trace quota exhausted');
        return null;
      }

      final frame = await VideoFrameExtractor.instance.extractFrame(pick.path);
      if (frame == null) return null;

      try {
        final search = await TraceApi.searchAnimeByImageFile(
          frame,
          anilistInfo: 2,
        );
        final results = (search.result ?? const <ResultItem>[])
          ..sort((a, b) => (b.similarity ?? 0).compareTo(a.similarity ?? 0));
        if (results.isEmpty) return null;
        final best = results.first;
        final rawSimilarity = best.similarity ?? 0;
        final found = best.anilist;
        if (found == null || found.title == null) return null;
        // trace.moe 官方建议：>0.87 视为强匹配，这里给一个下限兜底。
        if (rawSimilarity < 0.8) return null;
        anilist = found;
        similarity = rawSimilarity.clamp(0.0, 1.0).toDouble();
        _traceCache[cacheKey] = _TraceCacheEntry(
          anilist,
          similarity,
          now.add(_kTraceCacheTtl),
        );
        while (_traceCache.length > _kTraceCacheMaxEntries) {
          _traceCache.remove(_traceCache.keys.first);
        }
      } catch (e) {
        KazumiLogger().w(
            'MediaScraper: image trace failed for "${folder.name}"',
            error: e);
        return null;
      } finally {
        try {
          if (await frame.exists()) {
            await frame.delete();
          }
        } catch (_) {}
      }
    }

    final title = anilist.title;
    if (title == null) return null;
    final candidateTitles = <String>{
      if (title.chinese != null && title.chinese!.trim().isNotEmpty)
        title.chinese!.trim(),
      if (title.romaji != null && title.romaji!.trim().isNotEmpty)
        title.romaji!.trim(),
      if (title.english != null && title.english!.trim().isNotEmpty)
        title.english!.trim(),
      if (title.native != null && title.native!.trim().isNotEmpty)
        title.native!.trim(),
      ...?anilist.synonyms,
      ...?anilist.synonymsChinese,
    };
    candidateTitles.removeWhere((s) => s.trim().isEmpty);

    final season = parseSeason(folder.name);
    final year = parseYear(folder.name);

    // 标题去重后限量：AniList 的 synonyms 可能十几条，全查一遍成本太高。
    for (final candidate
        in candidateTitles.take(_kMaxAniListTitleCandidates)) {
      _throwIfCancelled(isCancelled);
      final items = await _search(candidate);
      if (items == null) {
        // 网络失败：保留已拿到的 AniList 信息，直接走下面的兜底展示。
        break;
      }
      if (items.isEmpty) continue;
      final bestMatch = _bestMatch(
        candidate,
        items,
        season: season,
        year: year,
      );
      if (bestMatch != null) {
        return _matched(folder, candidate, bestMatch);
      }
    }

    // Bangumi 未命中时，退而用 AniList 信息直接展示（置信度=图片相似度）。
    final displayName =
        title.chinese ?? title.romaji ?? title.english ?? title.native ?? '';
    return FolderScrapeResult(
      folderPath: folder.path,
      keyword: displayName,
      status: ScrapeStatus.matched,
      info: MediaScrapeInfo.fromAniList(anilist),
      confidence: similarity,
    );
  }

  static String _traceCacheKey(LocalMediaFile file) =>
      '${localMediaPathKey(file.path)}|${file.size}|'
      '${file.modifiedAt.millisecondsSinceEpoch}';

  /// 每日 trace.moe 配额：跨进程持久化，按自然日重置。
  Future<bool> _consumeTraceQuota() async {
    try {
      final now = DateTime.now();
      final dateKey = '${now.year}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      var date = GStorage.getSetting(SettingsKeys.localMediaTraceDailyDate);
      var count =
          GStorage.getSetting(SettingsKeys.localMediaTraceDailyCount);
      if (date != dateKey) {
        date = dateKey;
        count = 0;
      }
      if (count >= _kMaxImageTracePerDay) return false;
      await GStorage.putSetting(
          SettingsKeys.localMediaTraceDailyDate, date);
      await GStorage.putSetting(
          SettingsKeys.localMediaTraceDailyCount, count + 1);
      return true;
    } catch (_) {
      // 存储未初始化（测试环境）时不阻断兜底。
      return true;
    }
  }

  /// 生成多个候选关键词（清洗名 → 原文 → 首个文件名），每个附带季数/年份提示。
  List<_KeywordCandidate> _buildCandidates(
    LocalMediaFolder folder, {
    String? keyword,
  }) {
    final candidates = <_KeywordCandidate>[];
    void add(String value, {int? season, int? year}) {
      final v = value.trim();
      if (v.isEmpty) return;
      if (candidates.any((c) => c.keyword == v)) return;
      candidates.add(_KeywordCandidate(v, season: season, year: year));
    }

    /// 把一个标题展开成「原文 + 简体 + 去季数 + 去副标题」等多个候选。
    void addExpanded(String title, {int? season, int? year}) {
      for (final kw in expandKeyword(title)) {
        add(kw, season: season, year: year);
      }
    }

    if (keyword != null && keyword.trim().isNotEmpty) {
      final manual = keyword.trim();
      final season = parseSeason(manual);
      // 手动指定的关键词原样优先，再补上派生candidates（用户可能输的是繁体）
      add(manual, season: season);
      addExpanded(manual, season: season);
      return candidates;
    }

    final base = folder.name;
    final cleaned = cleanName(base);
    final trimmed = cleaned.isNotEmpty ? cleaned : base.trim();

    final season = parseSeason(base);
    final year = parseYear(base);

    final generic = isGenericTitle(trimmed);
    // 无意义占位标题（test / 新建文件夹 等）不直接作为搜索词，转用文件候选。
    if (!generic) {
      addExpanded(trimmed, season: season, year: year);
    }

    // 清洗后信息太短或是占位标题时，尝试内部视频文件的首个文件名
    // 与去发布组前缀的原始名（如 `test/` 目录里放着真实番剧文件）。
    if (trimmed.length <= 4 || generic) {
      LocalMediaFile? firstFile;
      for (final f in folder.files) {
        if (f.name.isNotEmpty) {
          firstFile = f;
          break;
        }
      }
      if (firstFile != null) {
        final fileClean = cleanName(firstFile.name);
        if (fileClean.isNotEmpty &&
            fileClean != trimmed &&
            !isGenericTitle(fileClean)) {
          addExpanded(
            fileClean,
            season: parseSeason(firstFile.name),
            year: parseYear(firstFile.name),
          );
        }
      }
      final noBrackets =
          base.replaceAll(RegExp(r'\[[^\]]*\]'), ' ').trim();
      if (noBrackets.isNotEmpty &&
          noBrackets != base &&
          noBrackets != trimmed &&
          !isGenericTitle(noBrackets)) {
        add(noBrackets, year: year);
      }
    }
    return candidates;
  }

  /// 从搜索结果中挑选最匹配的条目，返回置信度，过低返回 null（视为未命中）。
  ///
  /// 除绝对阈值外，中低置信度还要求「最优 - 次优」有足够差距，避免在两个
  /// 分数接近的条目里随便选一个。
  _Match? _bestMatch(
    String keyword,
    List<BangumiItem> items, {
    int? season,
    int? year,
  }) {
    if (items.isEmpty) return null;
    final normalizedKeyword = _normalize(keyword);

    _Match? best;
    double second = 0;
    for (final item in items) {
      final score = _scoreItem(
        item,
        normalizedKeyword,
        season: season,
        year: year,
      );
      if (score <= 0) continue;
      if (best == null || score > best.confidence) {
        second = best?.confidence ?? 0;
        best = _Match(
          MediaScrapeInfo.fromBangumiItem(item),
          score,
        );
      } else if (score > second) {
        second = score;
      }
    }
    if (best == null || best.confidence < _kMatchThreshold) return null;
    // 高置信度（精确名 / 包含关系）不再要求差距：同名的关联条目、重复条目
    // 常常同分，强行要求差距会把正确结果也丢掉。
    if (best.confidence < _kHighConfidenceThreshold &&
        best.confidence - second < _kSecondBestGap) {
      return null;
    }
    return best;
  }

  /// 对单个条目打分。
  double _scoreItem(
    BangumiItem item,
    String normalizedKeyword, {
    int? season,
    int? year,
  }) {
    final names = <String>[
      if (item.nameCn.isNotEmpty) _normalize(item.nameCn),
      if (item.name.isNotEmpty) _normalize(item.name),
      ...item.alias.map(_normalize),
    ];

    double bestNameScore = 0;
    for (final name in names) {
      if (name.isEmpty) continue;
      final score = _nameSimilarity(normalizedKeyword, name);
      if (score > bestNameScore) bestNameScore = score;
    }
    if (bestNameScore <= 0) return 0;

    double bonus = 0;
    if (season != null) {
      // nameCn 常常不带季数标记，两个名字都试一遍再判断。
      // 第一季同样要校验：否则 S1 文件夹会毫无阻力地匹配到第三季条目。
      final itemSeason =
          parseSeason(item.nameCn) ?? parseSeason(item.name);
      if (itemSeason == season) {
        bonus += 0.18;
      } else if (itemSeason != null) {
        // 季数写明了但对不上（找第三季却给第二季），明确降权
        bonus -= 0.12;
      } else {
        // 条目没有季数标记，多半是第一季，轻微降权
        bonus -= 0.06;
      }
    }
    if (year != null) {
      final y = item.airDate.length >= 4
          ? int.tryParse(item.airDate.substring(0, 4))
          : null;
      if (y == year) bonus += 0.08;
    }
    final score = bestNameScore + bonus;
    if (score <= 0) return 0;
    // 置信度对外约定为 0~1，季数/年份加分不能把它推过 100%。
    return score > 1 ? 1 : score;
  }

  /// 关键词与条目名称的相似度（0~1）。
  double _nameSimilarity(String keyword, String name) {
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
    final lcs = _longestCommonSubstring(keyword, name);
    if (lcs.length < _kMinLcsLength) return 0;
    final ratio = lcs.length / math.max(keyword.length, name.length);
    return ratio >= _kMinLcsRatio ? ratio * 0.8 : 0;
  }

  /// 最长公共子串：滚动数组实现，避免每个别名都分配 O(n·m) 二维表。
  String _longestCommonSubstring(String a, String b) {
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

  /// 测试用：直接验证打分逻辑，不依赖网络。
  @visibleForTesting
  ({double confidence, MediaScrapeInfo info})? bestMatchForTest(
    String keyword,
    List<BangumiItem> items, {
    int? season,
    int? year,
  }) {
    final match = _bestMatch(keyword, items, season: season, year: year);
    if (match == null) return null;
    return (confidence: match.confidence, info: match.info);
  }

  /// 测试用：验证归一化后的名称相似度。
  @visibleForTesting
  double nameSimilarityForTest(String keyword, String name) =>
      _nameSimilarity(_normalize(keyword), _normalize(name));

  /// 测试用：清空进程内搜索 / 图片识别缓存。
  @visibleForTesting
  static void clearCachesForTest() {
    _searchCache.clear();
    _searchInFlight.clear();
    _traceCache.clear();
  }

  /// 批量搜刮文件夹列表。
  ///
  /// [onProgress] 每处理完一个文件夹回调一次；
  /// [isCancelled] 返回 true 时停止领取新文件夹，并在当前候选之间立即生效；
  /// [concurrency] 文件夹级并发数，默认 [3]。
  ///
  /// 连续 [5] 个文件夹因网络 / 解析出错时提前中止本批，
  /// 未处理的文件夹不会产生结果（调用方保留其旧匹配）。
  Future<List<FolderScrapeResult>> scrapeAll(
    List<LocalMediaFolder> folders, {
    void Function(ScrapeProgress progress)? onProgress,
    bool Function()? isCancelled,
    int concurrency = _kMaxConcurrentFolderScrapes,
  }) async {
    final total = folders.length;
    if (total == 0) return const [];

    final results = <FolderScrapeResult>[];
    var nextIndex = 0;
    var matched = 0;
    var failed = 0;
    var consecutiveErrors = 0;
    var circuitOpen = false;
    var traceBudget = _kMaxImageTracePerBatch;
    final workerCount = concurrency < 1
        ? 1
        : (concurrency > total ? total : concurrency);

    Future<void> worker() async {
      while (true) {
        if (circuitOpen || isCancelled?.call() == true) return;
        final index = nextIndex++;
        if (index >= total) return;
        final folder = folders[index];

        FolderScrapeResult result;
        try {
          result = await scrapeFolder(
            folder: folder,
            isCancelled: isCancelled,
            reserveTrace: () {
              if (traceBudget <= 0) return false;
              traceBudget--;
              return true;
            },
          );
        } on _ScrapeCancelled {
          return;
        }

        results.add(result);
        if (result.status == ScrapeStatus.matched) {
          matched++;
          consecutiveErrors = 0;
        } else {
          failed++;
          if (result.status == ScrapeStatus.error) {
            consecutiveErrors++;
            if (consecutiveErrors >= _kMaxConsecutiveFailures) {
              circuitOpen = true;
              KazumiLogger().w(
                'MediaScraper: $_kMaxConsecutiveFailures consecutive failures, '
                'stopping batch at ${results.length}/$total',
              );
            }
          } else {
            consecutiveErrors = 0;
          }
        }
        onProgress?.call(ScrapeProgress(
          done: results.length,
          total: total,
          matched: matched,
          failed: failed,
          currentFolder: p.basename(folder.path),
          currentKeyword: result.keyword,
          aborted: circuitOpen,
        ));
      }
    }

    await Future.wait([
      for (var i = 0; i < workerCount; i++) worker(),
    ]);
    return results;
  }
}

class _Match {
  const _Match(this.info, this.confidence);

  final MediaScrapeInfo info;
  final double confidence;
}

class _KeywordCandidate {
  _KeywordCandidate(this.keyword, {this.season, this.year});

  final String keyword;
  final int? season;
  final int? year;
}

/// 用户取消批量搜刮：不产生结果，直接退出当前 worker。
class _ScrapeCancelled implements Exception {
  const _ScrapeCancelled();
}

/// 搜索请求失败（网络 / 解析），用于把「没搜到」与「没搜成」区分开。
class _SearchFailedException implements Exception {
  const _SearchFailedException(this.keyword);

  final String keyword;

  @override
  String toString() => 'bangumi search failed: $keyword';
}

class _SearchCacheEntry {
  const _SearchCacheEntry(this.items, this.expiresAt);

  final List<BangumiItem> items;
  final DateTime expiresAt;
}

class _TraceCacheEntry {
  const _TraceCacheEntry(this.anilist, this.similarity, this.expiresAt);

  final Anilist anilist;
  final double similarity;
  final DateTime expiresAt;
}