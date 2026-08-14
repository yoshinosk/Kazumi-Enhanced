import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 本地媒体库播放 → Bangumi 收藏进度联动服务。
///
/// 播完一集后（真·播放完成，排除近结尾续播的伪完成），把 Bangumi 收藏的
/// `ep_status` 更新为该集数。仅当设置项
/// [SettingsKeys.localMediaSyncBangumiProgress] 开启、且番剧已搜刮到真实
/// Bangumi ID 时生效。
class BangumiProgressSyncService {
  BangumiProgressSyncService._();

  static final Map<int, int> _syncedMax = {};
  static final Map<int, Future<void>> _inFlight = {};

  /// 同步失败后的冷却期：期间对同一 (bangumiId, 集数) 的再次请求直接跳过，
  /// 防止外部重复触发（如播放器 completed 持续态）导致重试链堆积。
  static const Duration _failureCooldown = Duration(minutes: 1);
  static final Map<String, DateTime> _lastFailureAt = {};

  static String _syncKey(int bangumiId, int episode) => '$bangumiId:$episode';

  @visibleForTesting
  static int monotonicTarget(int remoteEpisode, int watchedEpisode) =>
      remoteEpisode > watchedEpisode ? remoteEpisode : watchedEpisode;

  /// 标记一集为已看：更新 Bangumi 收藏 EP 进度。失败仅记录日志。
  static Future<void> markEpisodeWatched({
    required int bangumiId,
    required int episode,
  }) async {
    if (!GStorage.getSetting(SettingsKeys.localMediaSyncBangumiProgress)) {
      return;
    }
    if (bangumiId <= 0 || episode <= 0) return;
    final key = _syncKey(bangumiId, episode);
    final lastFailure = _lastFailureAt[key];
    if (lastFailure != null &&
        DateTime.now().difference(lastFailure) < _failureCooldown) {
      return;
    }
    final previous = _inFlight[bangumiId];
    late final Future<void> operation;
    operation = () async {
      if (previous != null) await previous;
      if ((_syncedMax[bangumiId] ?? 0) >= episode) return;
      await _syncWithRetry(bangumiId: bangumiId, episode: episode);
    }();
    _inFlight[bangumiId] = operation;
    try {
      await operation;
    } finally {
      if (identical(_inFlight[bangumiId], operation)) {
        _inFlight.remove(bangumiId);
      }
    }
  }

  static Future<void> _syncWithRetry({
    required int bangumiId,
    required int episode,
  }) async {
    const delays = [Duration.zero, Duration(seconds: 1), Duration(seconds: 5)];
    for (var attempt = 0; attempt < delays.length; attempt++) {
      if (delays[attempt] != Duration.zero) {
        await Future<void>.delayed(delays[attempt]);
      }
      try {
        final remote = await BangumiApi.getBangumiCollectionProgressById(
          bangumiId,
        );
        if (remote == null) continue;
        final target = monotonicTarget(remote, episode);
        if (target == remote ||
            await BangumiApi.updateBangumiById(
              bangumiId,
              {'ep_status': target},
            )) {
          _syncedMax[bangumiId] = target;
          _lastFailureAt.remove(_syncKey(bangumiId, episode));
          KazumiLogger().i(
            'BangumiProgressSync: ep_status -> $target for subject $bangumiId',
          );
          return;
        }
      } catch (e) {
        KazumiLogger().w(
          'BangumiProgressSync: attempt ${attempt + 1} failed',
          error: e,
        );
      }
    }
    _lastFailureAt[_syncKey(bangumiId, episode)] = DateTime.now();
    KazumiLogger().w(
      'BangumiProgressSync: update failed after retries for subject $bangumiId',
    );
  }
}
