class DanmakuEpisode {
  int episodeId;
  String episodeTitle;

  DanmakuEpisode({
    required this.episodeId,
    required this.episodeTitle,
  });

  factory DanmakuEpisode.fromJson(Map<String, dynamic> json) {
    return DanmakuEpisode(
      episodeId: json['episodeId'],
      episodeTitle: json['episodeTitle'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'episodeId': episodeId,
      'episodeTitle': episodeTitle,
    };
  }
}

class DanmakuEpisodeResponse {
  int bangumiId;
  List<DanmakuEpisode> episodes;
  int errorCode;
  bool success;
  String errorMessage;

  DanmakuEpisodeResponse({
    required this.bangumiId,
    required this.episodes,
    required this.errorCode,
    required this.success,
    required this.errorMessage,
  });

  factory DanmakuEpisodeResponse.fromJson(Map<String, dynamic> json) {
    final bangumi = json['bangumi'];
    final rawEpisodes =
        (bangumi is Map<String, dynamic>) ? bangumi['episodes'] : null;
    final List<DanmakuEpisode> episodeList =
        (rawEpisodes is List)
            ? rawEpisodes
                .whereType<Map>()
                .map((i) =>
                    DanmakuEpisode.fromJson(Map<String, dynamic>.from(i)))
                .toList()
            : <DanmakuEpisode>[];

    return DanmakuEpisodeResponse(
      bangumiId: (bangumi is Map<String, dynamic>)
          ? ((bangumi['animeId'] as num?)?.toInt() ?? 0)
          : 0,
      episodes: episodeList,
      errorCode: ((json['errorCode'] as num?)?.toInt()) ?? 0,
      success: json['success'] == true,
      errorMessage: (json['errorMessage'] as String?) ?? '',
    );
  }

  factory DanmakuEpisodeResponse.fromTemplate() {
    return DanmakuEpisodeResponse(
      bangumiId: 0,
      episodes: [],
      errorCode: 0,
      success: false,
      errorMessage: '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bangumi': episodes.map((episode) => episode.toJson()).toList(),
      'errorCode': errorCode,
      'success': success,
      'errorMessage': errorMessage,
    };
  }
}
