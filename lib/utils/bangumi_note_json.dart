/// bangumi-note 追番记录 JSON 编解码。
///
/// bangumi-note（个人追番统计 web 应用）追番记录 JSON 编解码。
///
/// 其导出的 JSON 是 SubjectItem 数组：bgm.tv /v0 条目字段之上，把 `type`
/// 覆盖成了个人收藏状态（1想看/2看过/3在看/4搁置/5抛弃），并额外携带
/// `nice` 推荐标记。Kazumi 的 [CollectType] 数值语义不同
/// （1在看/2想看/3搁置/4看过/5抛弃），编解码时做双向映射；
/// `nice` 在 Kazumi 中没有对应概念，导出时恒为 false。
library;

import 'dart:convert';

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';

/// bangumi-note CollectionType → Kazumi [CollectType].value
const Map<int, int> bangumiNoteTypeToKazumi = {
  1: 2, // 想看
  2: 4, // 看过
  3: 1, // 在看
  4: 3, // 搁置
  5: 5, // 抛弃
};

/// Kazumi [CollectType].value → bangumi-note CollectionType
const Map<int, int> kazumiTypeToBangumiNote = {
  1: 3, // 在看
  2: 1, // 想看
  3: 4, // 搁置
  4: 2, // 看过
  5: 5, // 抛弃
};

class BangumiNoteParseResult {
  const BangumiNoteParseResult({
    required this.collectibles,
    required this.failureCount,
  });

  final List<CollectedBangumi> collectibles;

  /// 因缺少 id、收藏状态未知或字段异常而无法解析的条目数
  final int failureCount;
}

class BangumiNoteJson {
  BangumiNoteJson._();

  /// 解析 bangumi-note 导出的 JSON 文本。
  ///
  /// 条目 subject type 统一按动画（2）处理：该格式里 `type` 已被收藏状态
  /// 覆盖，不还原会把收藏状态写进 [BangumiItem.type]。
  static BangumiNoteParseResult parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('数据格式不正确，应为 JSON 数组');
    }

    final collectibles = <CollectedBangumi>[];
    var failures = 0;
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) {
        failures++;
        continue;
      }
      try {
        final noteType = (entry['type'] as num?)?.toInt();
        final collectValue = bangumiNoteTypeToKazumi[noteType];
        if (collectValue == null) {
          failures++;
          continue;
        }
        final subject = Map<String, dynamic>.of(entry)
          ..['type'] = 2
          // BangumiItem.fromJson 假定 rating/images 必存在，做一次兜底
          ..['rating'] = _normalizeRating(entry['rating'])
          ..['images'] = entry['images'] is Map<String, dynamic>
              ? entry['images']
              : <String, String>{};
        collectibles.add(
          CollectedBangumi(
            BangumiItem.fromJson(subject),
            DateTime.now(),
            collectValue,
          ),
        );
      } catch (_) {
        failures++;
      }
    }
    return BangumiNoteParseResult(
      collectibles: collectibles,
      failureCount: failures,
    );
  }

  /// 导出为 bangumi-note 可导入的 JSON 文本。
  ///
  /// Kazumi 没有存储 eps/volumes/collection 等全站字段，导出时省略；
  /// 别名回填到 infobox「别名」项，保证再次导入时别名不丢。
  static String encode(List<CollectedBangumi> collectibles) {
    final list = [
      for (final collect in collectibles)
        if (kazumiTypeToBangumiNote.containsKey(collect.type))
          _subjectToJson(collect),
    ];
    return jsonEncode(list);
  }

  /// 补齐 fromJson 依赖的字段：rating 必须存在，且 count 为 Map 时
  /// 必须含完整的 1~10 键位（缺失键位补 0，否则强转 int 会崩）。
  static Map<String, dynamic> _normalizeRating(Object? rating) {
    if (rating is! Map<String, dynamic>) {
      return {
        'rank': 0,
        'score': 0,
        'total': 0,
        'count': _fullVoteCount(null),
      };
    }
    final count = rating['count'];
    if (count is List) return rating;
    return {...rating, 'count': _fullVoteCount(count is Map ? count : null)};
  }

  static Map<String, int> _fullVoteCount(Map? count) {
    return {
      for (var i = 1; i <= 10; i++)
        '$i': count == null ? 0 : ((count['$i'] as num?)?.toInt() ?? 0),
    };
  }

  static Map<String, dynamic> _subjectToJson(CollectedBangumi collect) {
    final item = collect.bangumiItem;
    return {
      'id': item.id,
      'type': kazumiTypeToBangumiNote[collect.type],
      'nice': false,
      'name': item.name,
      'name_cn': item.nameCn,
      'summary': item.summary,
      'date': item.airDate,
      'platform': '',
      'images': Map<String, String>.of(item.images),
      'infobox': [
        if (item.alias.isNotEmpty)
          {'key': '别名', 'value': List<String>.of(item.alias)},
      ],
      'tags': [for (final tag in item.tags) tag.toJson()],
      'rating': {
        'rank': item.rank,
        'score': item.ratingScore,
        'total': item.votes,
        'count': {
          for (var i = 0; i < item.votesCount.length && i < 10; i++)
            '${i + 1}': item.votesCount[i],
        },
      },
      'meta_tags': List<String>.of(item.metaTags),
    };
  }
}
