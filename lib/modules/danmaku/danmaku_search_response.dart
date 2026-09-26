/// Response of `/api/v2/search/episodes`.
///
/// Entries carry no cover, rating or air date, unlike `/api/v2/search/anime`.
class DanmakuSearchAnime {
  final int animeId;
  final String animeTitle;
  final String typeDescription;

  const DanmakuSearchAnime({
    required this.animeId,
    required this.animeTitle,
    required this.typeDescription,
  });

  factory DanmakuSearchAnime.fromJson(Map<String, dynamic> json) {
    return DanmakuSearchAnime(
      animeId: json['animeId'],
      animeTitle: json['animeTitle'],
      typeDescription: json['typeDescription'] ?? '',
    );
  }
}

class DanmakuSearchResponse {
  final List<DanmakuSearchAnime> animes;

  /// Result set was truncated; the user should narrow the keyword.
  final bool hasMore;

  /// Legacy `/api/v2/search/anime` fields, absent from `/api/v2/search/episodes`.
  final int? errorCode;
  final bool? success;
  final String? errorMessage;

  const DanmakuSearchResponse({
    required this.animes,
    required this.hasMore,
    this.errorCode,
    this.success,
    this.errorMessage,
  });

  factory DanmakuSearchResponse.fromJson(Map<String, dynamic> json) {
    var list = json['animes'] as List;
    return DanmakuSearchResponse(
      animes: list.map((i) => DanmakuSearchAnime.fromJson(i)).toList(),
      hasMore: json['hasMore'] ?? false,
      errorCode: json['errorCode'] as int?,
      success: json['success'] as bool?,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}
