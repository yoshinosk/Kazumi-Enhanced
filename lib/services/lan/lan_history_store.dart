import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/lan/lan_media_paths.dart';
import 'package:kazumi/services/lan/lan_sync_models.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/history_storage_coordinator.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 局域网同步中的本地媒体历史读写。
///
/// 只处理 `adapterName == local` 的条目：在线播放历史仍由 Bangumi / WebDAV
/// 等既有链路负责，局域网同步不越权修改。
class LanHistoryStore {
  LanHistoryStore(this._repository);

  final IHistoryRepository _repository;

  /// 桌面端：导出全部本地媒体历史（真实路径）。
  List<LanHistoryEntry> exportLocalMediaHistory() {
    return [
      for (final history in _repository.getAllHistories())
        if (isLocalMediaHistory(history)) LanHistoryEntry.fromHistory(history),
    ];
  }

  /// 手机端：只导出属于当前桌面端的远程播放历史，并把伪路径还原为
  /// 桌面端真实路径后再上传。
  List<LanHistoryEntry> exportForServer(String serverId) {
    final result = <LanHistoryEntry>[];
    for (final history in _repository.getAllHistories()) {
      if (!isLocalMediaHistory(history)) continue;
      final path = history.episodePageUrl;
      if (path.isEmpty) continue;
      if (!isLanPathOfServer(path, serverId)) continue;
      final remotePath = lanRemotePathOf(path);
      if (remotePath == null) continue;
      result.add(
        LanHistoryEntry.fromHistory(
          history,
        ).copyWith(episodePageUrl: remotePath),
      );
    }
    return result;
  }

  /// 把远端条目写回本地：同 key 条目逐集合并，不删除本机其他历史
  /// （手机本地视频、其他桌面端的历史保持不变）。
  Future<int> applyEntries(Iterable<LanHistoryEntry> entries) async {
    final incoming = [
      for (final entry in entries)
        if (entry.adapterName == kLocalMediaAdapterName) entry,
    ];
    if (incoming.isEmpty) return 0;

    var written = 0;
    await HistoryStorageCoordinator().run(() async {
      try {
        for (final entry in incoming) {
          final existing = GStorage.histories.get(entry.key);
          final merged = existing == null
              ? entry
              : LanHistoryEntry.fromHistory(existing).merge(entry);
          final next = merged.toHistory();
          if (existing != null && _sameHistory(existing, next)) {
            continue;
          }
          await GStorage.histories.put(entry.key, next);
          written++;
        }
        await GStorage.histories.flush();
      } catch (e, stackTrace) {
        KazumiLogger().w(
          'LanSync: apply history failed',
          error: e,
          stackTrace: stackTrace,
        );
      }
    });
    return written;
  }

  static bool _sameHistory(History a, History b) {
    if (a.lastWatchEpisode != b.lastWatchEpisode ||
        a.lastWatchTime != b.lastWatchTime ||
        a.lastWatchEpisodeName != b.lastWatchEpisodeName ||
        a.episodePageUrl != b.episodePageUrl ||
        a.lastSrc != b.lastSrc ||
        a.entryKind != b.entryKind ||
        a.adapterName != b.adapterName ||
        a.progresses.length != b.progresses.length) {
      return false;
    }
    for (final entry in a.progresses.entries) {
      final other = b.progresses[entry.key];
      if (other == null ||
          other.road != entry.value.road ||
          other.progress != entry.value.progress ||
          other.updatedAtMs != entry.value.updatedAtMs) {
        return false;
      }
    }
    return true;
  }
}
