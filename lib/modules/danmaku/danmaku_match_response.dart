/// 弹弹 Play `/api/v2/match` 的响应模型。
///
/// 该接口按「文件名 + 前 16MiB MD5 + 文件大小」精确匹配本地视频对应的分集，
/// 返回的 [DanmakuMatch.episodeId] 可直接用于 `/api/v2/comment/{episodeId}`，
/// 无需再依赖文件名集数解析或 BGM → 弹弹的 ID 映射。
class DanmakuMatch {
  const DanmakuMatch({
    required this.episodeId,
    required this.animeId,
    required this.animeTitle,
    required this.episodeTitle,
    required this.type,
    required this.shift,
  });

  final int episodeId;
  final int animeId;
  final String animeTitle;
  final String episodeTitle;
  final String type;
  final double shift;

  factory DanmakuMatch.fromJson(Map<String, dynamic> json) {
    return DanmakuMatch(
      episodeId: (json['episodeId'] as num?)?.toInt() ?? 0,
      animeId: (json['animeId'] as num?)?.toInt() ?? 0,
      animeTitle: json['animeTitle'] as String? ?? '',
      episodeTitle: json['episodeTitle'] as String? ?? '',
      type: json['type'] as String? ?? '',
      shift: (json['shift'] as num?)?.toDouble() ?? 0,
    );
  }
}

class DanmakuMatchResponse {
  const DanmakuMatchResponse({
    required this.isMatched,
    required this.matches,
    required this.success,
    required this.errorCode,
    required this.errorMessage,
  });

  final bool isMatched;
  final List<DanmakuMatch> matches;
  final bool success;
  final int errorCode;
  final String errorMessage;

  /// 只有唯一命中时才认为可以直接采用，多结果需要用户或上层策略介入。
  bool get hasUniqueMatch => isMatched && matches.length == 1;

  DanmakuMatch? get best => matches.isEmpty ? null : matches.first;

  factory DanmakuMatchResponse.fromJson(Map<String, dynamic> json) {
    final list = json['matches'] as List? ?? const [];
    return DanmakuMatchResponse(
      isMatched: json['isMatched'] as bool? ?? false,
      matches: list
          .whereType<Map>()
          .map((e) => DanmakuMatch.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.episodeId != 0)
          .toList(),
      success: json['success'] as bool? ?? false,
      errorCode: (json['errorCode'] as num?)?.toInt() ?? 0,
      errorMessage: json['errorMessage'] as String? ?? '',
    );
  }

  static const empty = DanmakuMatchResponse(
    isMatched: false,
    matches: [],
    success: false,
    errorCode: -1,
    errorMessage: '',
  );
}
