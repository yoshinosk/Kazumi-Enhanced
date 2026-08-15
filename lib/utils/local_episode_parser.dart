import 'package:kazumi/utils/chinese_convert.dart';
import 'package:path/path.dart' as p;

/// 本地媒体文件名解析工具。
///
/// 通用的 [extractEpisodeNumber] 取的是字符串中第一个数字，对本地压制组命名
/// 极易误判（`★10月新番★`、`我推的孩子 2 - 01`、`[1080p]`、`86-Eighty Six`、
/// `S01E05` 等都会被解析成错误集数），进而导致弹幕请求到错误分集或空结果。
///
/// 这里改用「噪声剥离 + 优先级正则」的策略：先把分辨率、编码、音轨、年份、
/// 季度、发布月份等干扰片段替换成等长空白（保留位置，避免拼接出假数字），
/// 再按可信度从高到低依次尝试集数模式。

/// 集数的合理上界，超出则判定为误匹配（多半是年份或码率）。
const int _kMaxEpisodeNumber = 2000;

/// 常见字幕组 / 压制组标记，用于标题清洗时排除。
const Set<String> _kKnownReleaseGroups = {
  'ani', 'ani-one', 'anifans', 'airota', 'bangumi', 'baha', 'comicat',
  'dmg', 'dymy', 'kissaten', 'kitauji', 'lilith-raws', 'liliana',
  'moozzi2', 'mabors', 'nekomoe kissaten', 'nc-raws', 'ohys-raws',
  'philosophy-raws', 'pussub', 'sakurato', 'skytree', 'snow-raws',
  'sweetsub', 'uha-wings', 'vcb-studio', 'yumeko', 'yuisub',
  'jsum', 'lolihouse', 'mingy', 'haruhana', 'billion meta lab',
  '喵萌奶茶屋', '桜都字幕组', '澄空学园', '幻樱字幕组', '千夏字幕组',
  '诸神字幕组', '悠哈璃羽字幕社', '爱恋字幕社', '动漫国字幕组', '轻之国度',
  '天使动漫论坛', '风之圣殿', '北宇治字幕组', '漫猫字幕社', '未央阁联盟',
};

/// 规格 / 画质 / 音轨等噪声片段。命中后整体替换为等长空白。
final List<RegExp> _kNoisePatterns = [
  // 分辨率：1080p / 720P / 2160p / 1920x1080
  RegExp(r'\b\d{3,4}\s*[pi]\b', caseSensitive: false),
  RegExp(r'\b\d{3,4}\s*[x×]\s*\d{3,4}\b', caseSensitive: false),
  RegExp(r'\b(?:4k|8k|uhd|fhd|hd)\b', caseSensitive: false),
  // 视频编码
  RegExp(r'\b[xh]\.?26[45]\b', caseSensitive: false),
  RegExp(r'\b(?:hevc|avc|vp9|av1|xvid|divx)\b', caseSensitive: false),
  RegExp(r'\b(?:ma)?10\s*-?\s*bits?\b', caseSensitive: false),
  RegExp(r'\b8\s*-?\s*bits?\b', caseSensitive: false),
  RegExp(r'\b(?:ma10p|hi10p?|yuv420p10)\b', caseSensitive: false),
  // 音频编码与声道
  RegExp(r'\b(?:aac|flac|ac3|eac3|e-ac-3|dts(?:-hd)?|truehd|opus|mp3|ddp?)\b',
      caseSensitive: false),
  RegExp(r'\b\d\.\d\s*(?:ch)?\b', caseSensitive: false),
  // 片源
  RegExp(
      r'\b(?:blu-?ray|bdrip|bdbox|bd|webrip|web-?dl|hdtv|dvdrip|dvd|remux|tvrip)\b',
      caseSensitive: false),
  // 码率 / 帧率
  RegExp(r'\b\d+\s*k?bps\b', caseSensitive: false),
  RegExp(r'\b\d+(?:\.\d+)?\s*fps\b', caseSensitive: false),
  // 容器与字幕语言标记
  RegExp(r'\b(?:mp4|mkv|mka|ass|srt|pgs|sub)\b', caseSensitive: false),
  RegExp(r'\b(?:chs|cht|chi|jpsc|jptc|jpn|gb|big5|sc|tc|cn|jp|eng)\b',
      caseSensitive: false),
  RegExp(r'(?:简体|繁體|繁体|简日|繁日|简繁|日简|日繁|双语|内嵌|外挂|内封|字幕|招募|无修|生肉|熟肉)'),
  // 季度标记（放在 SxxExx 之后处理，不会误伤）
  RegExp(r'\b\d+\s*(?:st|nd|rd|th)\s*season\b', caseSensitive: false),
  RegExp(r'\bseason\s*\d+\b', caseSensitive: false),
  RegExp(r'第\s*[0-9一二三四五六七八九十]+\s*[季期部]'),
  // 发布档期：10月新番 / 4月番
  RegExp(r'\d{1,2}\s*月\s*新?番'),
  // 年份
  RegExp(r'\b(?:19|20)\d{2}\b'),
  // 版本号 v2 / v3。注意 `06v2` 中 v 前是数字，\b 不成立，需用否定后行断言。
  RegExp(r'(?<![a-z])v\d(?![0-9a-z])', caseSensitive: false),
];

/// CRC32 校验后缀，如 `[1A2B3C4D]`。
final RegExp _kCrc32Pattern =
    RegExp(r'[\[\(]\s*[0-9a-f]{8}\s*[\]\)]', caseSensitive: false);

/// 用等长空白替换匹配片段，保持原字符串长度与其余片段的相对位置。
String _blankOut(String input, RegExp pattern) {
  return input.replaceAllMapped(pattern, (m) => ' ' * m.group(0)!.length);
}

/// 去掉扩展名与 CRC32 校验码。
String _stripContainer(String fileName) {
  var name = fileName;
  final ext = p.extension(name);
  if (ext.isNotEmpty && ext.length <= 6) {
    name = name.substring(0, name.length - ext.length);
  }
  return _blankOut(name, _kCrc32Pattern);
}

/// 剥离全部规格类噪声。
String _denoise(String input) {
  var result = input;
  for (final pattern in _kNoisePatterns) {
    result = _blankOut(result, pattern);
  }
  return result;
}

bool _isPlausibleEpisode(int value) =>
    value > 0 && value <= _kMaxEpisodeNumber;

int? _firstGroupAsEpisode(RegExpMatch? match, [int group = 1]) {
  if (match == null) return null;
  final raw = match.group(group);
  if (raw == null) return null;
  final value = int.tryParse(raw);
  if (value == null || !_isPlausibleEpisode(value)) return null;
  return value;
}

/// 从本地视频文件名解析集数，解析失败返回 0。
///
/// 按可信度依次尝试：
/// 1. `S01E05` / `S1E5`
/// 2. `第 01 话` / `第01集`
/// 3. `EP01` / `E01`
/// 4. 独立方括号内的纯数字 `[01]`（噪声剥离后 `[1080p]` 已被清空）
/// 5. 分隔符后的数字 `- 01`
/// 6. 兜底：净化串中最后一个独立数字
int parseLocalEpisodeNumber(String fileName) {
  if (fileName.trim().isEmpty) return 0;
  final base = _stripContainer(fileName);

  // 1. SxxExx 必须在噪声剥离前匹配，否则会被季度规则吃掉。
  final seasonEpisode = _firstGroupAsEpisode(
    RegExp(r'\bS\d{1,2}\s*E(\d{1,4})\b', caseSensitive: false).firstMatch(base),
  );
  if (seasonEpisode != null) return seasonEpisode;

  final cleaned = _denoise(base);

  // 2. 中文集数标记。
  final chinese = _firstGroupAsEpisode(
    RegExp(r'第\s*(\d{1,4})\s*[话話集回]').firstMatch(cleaned),
  );
  if (chinese != null) return chinese;

  // 3. EP01 / E01（要求 E 前是边界，避免吃掉单词中的字母）。
  final epMarker = _firstGroupAsEpisode(
    RegExp(r'(?:^|[^a-z0-9])ep?\s*[._\-]?\s*(\d{1,4})(?![0-9])',
            caseSensitive: false)
        .firstMatch(cleaned),
  );
  if (epMarker != null) return epMarker;

  // 4. 独立方括号中的纯数字，取最后一个（番名带数字时通常在更靠前的块）。
  final bracketMatches =
      RegExp(r'[\[\(【]\s*(\d{1,4})\s*(?:v\d)?\s*[\]\)】]', caseSensitive: false)
          .allMatches(cleaned)
          .toList();
  for (final match in bracketMatches.reversed) {
    final value = _firstGroupAsEpisode(match);
    if (value != null) return value;
  }

  // 5. 分隔符后的数字：`- 01`、`_01`、`– 01`。
  final dashMatches =
      RegExp(r'[-–—_]\s*(\d{1,4})(?=\s|$|[\[\(【])').allMatches(cleaned).toList();
  for (final match in dashMatches.reversed) {
    final value = _firstGroupAsEpisode(match);
    if (value != null) return value;
  }

  // 6. 兜底：最后一个独立数字。
  final loose =
      RegExp(r'(?<![0-9a-z])(\d{1,4})(?![0-9a-z])', caseSensitive: false)
          .allMatches(cleaned)
          .toList();
  for (final match in loose.reversed) {
    final value = _firstGroupAsEpisode(match);
    if (value != null) return value;
  }

  return 0;
}

/// 判断一个括号块是否是无意义的标签（字幕组、纯数字、规格）。
bool _isTaggishBlock(String block) {
  final trimmed = block.trim();
  if (trimmed.isEmpty) return true;
  if (RegExp(r'^\d+$').hasMatch(trimmed)) return true;
  final lower = trimmed.toLowerCase();
  if (_kKnownReleaseGroups.contains(lower)) return true;
  // 剥离噪声后基本为空，说明整块都是规格标记。
  if (_denoise(trimmed).trim().isEmpty) return true;
  // 含有 raws / sub / fansub 等字样的一律视为组名。
  if (RegExp(r'(raws?|fansub|subs?|字幕|压制|工作室|studio)', caseSensitive: false)
      .hasMatch(trimmed)) {
    return true;
  }
  return false;
}

/// 移除文件名中的集数标记，避免污染搜索关键词。
String _stripEpisodeMarkers(String input) {
  var result = input;
  result = _blankOut(result, RegExp(r'\bS\d{1,2}\s*E\d{1,4}\b', caseSensitive: false));
  result = _blankOut(result, RegExp(r'第\s*\d{1,4}\s*[话話集回]'));
  result = _blankOut(
      result, RegExp(r'(?:^|[^a-z0-9])ep\s*[._\-]?\s*\d{1,4}\b', caseSensitive: false));
  result = _blankOut(result, RegExp(r'[-–—]\s*\d{1,4}\s*(?=$|[\[\(【])'));
  // 结尾的两位以上数字通常是集数（`... Densetsu 04`）。
  // 只剥离 >=2 位，避免误伤季度标记（`我推的孩子 2`）。
  result = _blankOut(result, RegExp(r'(?<![0-9a-z])\d{2,4}\s*$'));
  return result;
}

/// 从本地视频文件名推断出可用于弹弹 Play 标题检索的番剧名。
///
/// 优先取括号外的正文；若正文为空（`[组名][番名][01][1080p]` 这类命名），
/// 则回退到「跳过首个块后、最长的非标签块」。返回空串表示无法推断。
String sanitizeAnimeTitle(String fileName) {
  if (fileName.trim().isEmpty) return '';
  final base = _stripContainer(fileName);

  final blockPattern = RegExp(r'[\[\(【]([^\[\]\(\)【】]*)[\]\)】]');
  final blocks =
      blockPattern.allMatches(base).map((m) => m.group(1) ?? '').toList();

  // 括号外正文
  var outside = _blankOut(base, blockPattern);
  outside = _denoise(_stripEpisodeMarkers(outside));
  outside = outside
      .replaceAll(RegExp(r'[★☆✿◆●▲■_~]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s\-–—.]+|[\s\-–—.]+$'), '')
      .trim();
  if (outside.length >= 2) {
    return outside;
  }

  // 回退到括号块：跳过首块（通常是字幕组），选最长的非标签块。
  final candidates = <String>[];
  for (var i = 0; i < blocks.length; i++) {
    if (i == 0 && blocks.length > 1) continue;
    final block = blocks[i];
    if (_isTaggishBlock(block)) continue;
    final normalized = _denoise(_stripEpisodeMarkers(block))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.length >= 2) {
      candidates.add(normalized);
    }
  }
  if (candidates.isEmpty) return '';
  candidates.sort((a, b) => b.length.compareTo(a.length));
  return candidates.first;
}

/// 本地文件分类：正片 / 特别篇（SP/OVA/OAD 等）/ 剧场版 / 特典。
enum LocalEpisodeKind {
  normal,
  special,
  movie,
  extra,
}

/// 判断本地视频文件属于哪一类（用于展示「SP」「剧场版」等标记，
/// 并把非正片内容排到列表末尾）。
LocalEpisodeKind classifyLocalEpisode(String fileName) {
  final lower = fileName.toLowerCase();
  if (RegExp(r'(剧场版|电影|剧场|movie\b|theatrical)', caseSensitive: false)
      .hasMatch(lower)) {
    return LocalEpisodeKind.movie;
  }
  if (RegExp(r'(特典|pv\b|cm\b|promotion|preview|预告|映像特典)',
          caseSensitive: false)
      .hasMatch(lower)) {
    return LocalEpisodeKind.extra;
  }
  if (RegExp(r'(sp\b|special|ova\b|oad\b|特别篇|特别编|番外|sp\s*\d)',
          caseSensitive: false)
      .hasMatch(lower)) {
    return LocalEpisodeKind.special;
  }
  return LocalEpisodeKind.normal;
}

/// 分类的中文标记（空串表示正片）。
String localEpisodeKindLabel(LocalEpisodeKind kind) {
  switch (kind) {
    case LocalEpisodeKind.normal:
      return '';
    case LocalEpisodeKind.special:
      return 'SP';
    case LocalEpisodeKind.movie:
      return '剧场版';
    case LocalEpisodeKind.extra:
      return '特典';
  }
}

/// 生成弹幕侧车文件的作用域标识。
///
/// 同一目录混放多部番剧（扫描器按标题拆分组）时，仅按集数命名的
/// `danmaku_<ep>.json` 会被两部番剧的「第 1 集」共用，导致弹幕串剧。
/// 用番剧名（繁转简归一）的稳定哈希作为作用域后缀区分。
String danmakuSidecarScope(String title) {
  final normalized = toSimplifiedChinese(title).trim();
  if (normalized.isEmpty) return '';
  var h = 0;
  for (final code in normalized.codeUnits) {
    h = (h * 31 + code) & 0x7FFFFFFF;
  }
  return h.toRadixString(16);
}
