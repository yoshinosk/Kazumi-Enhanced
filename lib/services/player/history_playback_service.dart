import 'dart:io';

import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/media/local_media_scanner.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:path/path.dart' as p;

sealed class HistoryPlaybackResult {
  const HistoryPlaybackResult();
}

class HistoryPlaybackReady extends HistoryPlaybackResult {
  const HistoryPlaybackReady(this.args);

  final VideoPlaybackArgs args;
}

class HistoryPlaybackUnavailable extends HistoryPlaybackResult {
  const HistoryPlaybackUnavailable(this.reason);

  final String reason;
}

/// Restores a history entry into arguments the player route can take.
///
/// The history page and the my page share this one resolution path; cards
/// carry no source-lookup logic of their own.
class HistoryPlaybackService {
  HistoryPlaybackService(this._pluginsController, this._downloadController);

  final PluginsController _pluginsController;
  final DownloadController _downloadController;

  /// [cancelToken] lets the caller abort the online lookup, e.g. when the
  /// loading dialog it put up is dismissed.
  Future<HistoryPlaybackResult> open(
    History history, {
    RuleCancelToken? cancelToken,
  }) async {
    if (HistoryEntryKind.normalize(history.entryKind) ==
        HistoryEntryKind.offline) {
      // 磁力边下边播条目：流 URL 仅在引擎存活期间有效，恢复前校验可达性。
      if (isStreamHistory(history)) {
        final args = await _streamArgs(history);
        return args == null
            ? const HistoryPlaybackUnavailable(
                '边下边播源已失效，请从下载页重新开始播放')
            : HistoryPlaybackReady(args);
      }
      // 本地媒体库条目：直接按记录的文件路径恢复，不经过下载记录查询。
      if (isLocalMediaHistory(history)) {
        final args = await _localMediaArgs(history);
        return args == null
            ? const HistoryPlaybackUnavailable('本地文件不存在或已被移动')
            : HistoryPlaybackReady(args);
      }
      final args = _offlineArgs(history);
      return args == null
          ? const HistoryPlaybackUnavailable('未找到可用缓存')
          : HistoryPlaybackReady(args);
    }

    final args = await _onlineArgs(history, cancelToken);
    return args == null
        ? const HistoryPlaybackUnavailable('在线源不可用，请重新选择播放源')
        : HistoryPlaybackReady(args);
  }

  /// 恢复磁力边下边播：对历史记录中的流 URL 做一次 HEAD 可达性检查
  /// （超时 2 秒），引擎仍在运行且流地址有效时可直接续播。
  Future<VideoPlaybackArgs?> _streamArgs(History history) async {
    final url = history.episodePageUrl;
    if (url.isEmpty || !url.startsWith('http')) return null;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      try {
        final request = await client.headUrl(Uri.parse(url)).timeout(
              const Duration(seconds: 2),
            );
        final response = await request.close().timeout(
              const Duration(seconds: 2),
            );
        // 仅 2xx 视为可达：流已删除时服务器典型响应 404（或 403），
        // 若放行则恢复后进入必定失败的播放页而非引导从下载页重新开始。
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return null;
    }
    return MagnetStreamVideoPlaybackArgs(
      bangumiItem: history.bangumiItem,
      streamUrl: url,
      fileName: history.lastWatchEpisodeName.isEmpty
          ? '流式播放'
          : history.lastWatchEpisodeName,
    );
  }

  Future<VideoPlaybackArgs?> _onlineArgs(
    History history,
    RuleCancelToken? cancelToken,
  ) async {
    if (history.lastSrc.isEmpty) {
      return null;
    }
    Plugin? targetPlugin;
    for (final plugin in _pluginsController.pluginList) {
      if (plugin.name == history.adapterName) {
        targetPlugin = plugin;
        break;
      }
    }
    if (targetPlugin == null) {
      return null;
    }
    try {
      final roads = await targetPlugin.queryChapterRoads(
        history.lastSrc,
        cancelToken: cancelToken,
      );
      if (roads.isEmpty) {
        return null;
      }
      return OnlineVideoPlaybackArgs(
        bangumiItem: history.bangumiItem,
        plugin: targetPlugin,
        title: history.bangumiItem.nameCn.isEmpty
            ? history.bangumiItem.name
            : history.bangumiItem.nameCn,
        src: history.lastSrc,
        roads: roads,
      );
    } catch (_) {
      KazumiLogger().w("QueryManager: failed to query roads");
      return null;
    }
  }

  /// 恢复本地媒体库播放：以历史记录中的文件绝对路径为准，
  /// 重建选集列表。
  ///
  /// 选集列表与媒体库播放的口径一致——按清洗后的标题特征分组，只取
  /// 目标文件所在分组的文件。否则同目录混放多部番剧时，选集面板会
  /// 混入其它番剧的剧集；分组失败时回退为同目录全部视频文件。
  Future<VideoPlaybackArgs?> _localMediaArgs(History history) async {
    final path = history.episodePageUrl;
    if (path.isEmpty || !File(path).existsSync()) {
      return null;
    }
    final dir = p.dirname(path);
    var files = <LocalMediaFile>[];
    try {
      final folders =
          await LocalMediaScanner().scan(dir, groupByFolder: false);
      for (final folder in folders) {
        if (folder.files.any((f) => f.path == path)) {
          files = List.of(folder.files);
          break;
        }
      }
      if (files.isEmpty) {
        await for (final entity in Directory(dir).list()) {
          if (entity is! File) continue;
          if (!isSupportedVideoFile(entity.path)) continue;
          files.add(await LocalMediaFile.fromFileSystemEntity(entity));
        }
      }
    } catch (e) {
      KazumiLogger().w('HistoryPlaybackService: list local dir failed',
          error: e);
      return null;
    }
    if (files.isEmpty) return null;
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final index = files.indexWhere((f) => f.path == path);
    return LocalMediaVideoPlaybackArgs(
      bangumiItem: history.bangumiItem,
      files: files,
      selectedIndex: index < 0 ? 0 : index,
      pluginName: kLocalMediaAdapterName,
      // 本地看完联动 Bangumi 进度依赖 bangumiSyncId，历史条目必然来自
      // Bangumi 详情，直接带 subject ID。
      bangumiSyncId: history.bangumiItem.id,
    );
  }

  VideoPlaybackArgs? _offlineArgs(History history) {
    final downloadedEpisodes = _downloadController.getCompletedEpisodes(
      history.bangumiItem.id,
      history.adapterName,
    );
    if (downloadedEpisodes.isEmpty) {
      return null;
    }

    // The page url pins the exact episode; the number is the legacy fallback.
    DownloadEpisode? targetEpisode;
    DownloadEpisode? numberMatch;
    for (final episode in downloadedEpisodes) {
      if (history.episodePageUrl.isNotEmpty &&
          episode.episodePageUrl == history.episodePageUrl) {
        targetEpisode = episode;
        break;
      }
      if (episode.episodeNumber == history.lastWatchEpisode) {
        numberMatch ??= episode;
      }
    }
    targetEpisode ??= numberMatch;
    if (targetEpisode == null) {
      return null;
    }

    final localPath = _downloadController.getLocalVideoPath(
      history.bangumiItem.id,
      history.adapterName,
      targetEpisode.episodeNumber,
    );
    if (localPath == null) {
      return null;
    }

    return OfflineVideoPlaybackArgs(
      bangumiItem: history.bangumiItem,
      pluginName: history.adapterName,
      episodeNumber: targetEpisode.episodeNumber,
      road: targetEpisode.road,
      downloadedEpisodes: downloadedEpisodes,
    );
  }
}
