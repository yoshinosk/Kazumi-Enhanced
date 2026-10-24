import 'dart:io';

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

  /// 上一次「导出时被跳过」的条目签名，用于只在差异变化时写日志。
  static String _lastSkippedSignature = '';

  /// 历史盒子变更流（播放中每秒都会触发，订阅方需自行去抖）。
  Stream<void> get changes => _repository.changes;

  /// 桌面端：导出全部可同步历史（本地媒体库 + 在线观看）。
  ///
  /// 在线条目的路径是插件分集地址、与设备无关，原样带给手机端；本地媒体库
  /// 条目带真实路径，手机端会映射成局域网伪路径。
  List<LanHistoryEntry> exportHistoryForPeer() {
    return [
      for (final history in _repository.getAllHistories())
        if (isLanSyncableHistory(
          adapterName: history.adapterName,
          entryKind: history.entryKind,
        ))
          LanHistoryEntry.fromHistory(history),
    ];
  }

  /// 手机端：导出属于当前桌面端的远程播放历史，并把伪路径还原为
  /// 桌面端真实路径后再上传。
  ///
  /// 在线观看条目直接原样上传（插件分集地址与设备无关）；本地媒体库条目
  /// 按路径归属过滤，被跳过的条目会写入日志——条目路径不属于该桌面端时
  /// 它无法上传，是「电脑端看不到手机端进度」的直接原因，必须可排查。
  List<LanHistoryEntry> exportForServer(String serverId) {
    final result = <LanHistoryEntry>[];
    final skipped = <String>[];
    var candidates = 0;
    for (final history in _repository.getAllHistories()) {
      if (!isLanSyncableHistory(
        adapterName: history.adapterName,
        entryKind: history.entryKind,
      )) {
        continue;
      }
      if (history.adapterName != kLocalMediaAdapterName) {
        // 在线观看：路径是插件分集地址，两端通用。
        result.add(LanHistoryEntry.fromHistory(history));
        continue;
      }
      candidates++;
      final path = history.episodePageUrl;
      if (path.isEmpty) {
        skipped.add('${history.key}=no-path');
        continue;
      }
      if (!isLanPathOfServer(path, serverId)) {
        skipped.add('${history.key}=path-of-${lanServerIdOf(path) ?? 'local'}');
        continue;
      }
      final remotePath = lanRemotePathOf(path);
      if (remotePath == null) {
        skipped.add('${history.key}=bad-path');
        continue;
      }
      result.add(
        LanHistoryEntry.fromHistory(
          history,
        ).copyWith(episodePageUrl: remotePath),
      );
    }
    if (skipped.isNotEmpty) {
      // 每次同步都会走到这里：只在被跳过集合发生变化时记录，避免日志刷屏。
      final signature = skipped.join('|');
      if (signature != _lastSkippedSignature) {
        _lastSkippedSignature = signature;
        KazumiLogger().i(
          'LanSync: exported ${result.length}/$candidates local history '
          '(skipped ${skipped.length}: ${skipped.take(12).join(", ")}'
          '${skipped.length > 12 ? " …" : ""})',
          forceLog: true,
        );
      }
    } else {
      _lastSkippedSignature = '';
    }
    return result;
  }

  /// 把远端条目写回本地：同 key 条目逐集合并，不删除本机其他历史
  /// （手机本地视频、下载缓存、其他桌面端的历史保持不变）。
  Future<int> applyEntries(Iterable<LanHistoryEntry> entries) async {
    final incoming = [
      for (final entry in entries)
        if (isLanSyncableHistory(
          adapterName: entry.adapterName,
          entryKind: entry.entryKind,
        ))
          entry,
    ];
    if (incoming.isEmpty) return 0;

    var written = 0;
    var failed = 0;
    var repaired = 0;
    await HistoryStorageCoordinator().run(() async {
      for (final entry in incoming) {
        // 单条写失败不能中断整批：否则一条脏数据会让本次同步的所有
        // 历史都丢弃，表现为「已连接但没有同步任何进度」。
        try {
          final existing = GStorage.histories.get(entry.key);
          final merged = existing == null
              ? entry
              : LanHistoryEntry.fromHistory(existing).merge(entry);
          final next = merged.toHistory();
          // 远端条目带回的是本服务器的局域网伪路径：若本地同 key 条目的
          // 路径已经失效（空、属于其它桌面端、或指向本机不存在的文件），
          // 以远端路径为准。否则该条目会永久不再上传（导出按路径判定
          // 归属），两端进度从此各自为政。
          final repairedPath = _repairedPath(existing, entry.episodePageUrl);
          if (repairedPath != null) {
            next.episodePageUrl = repairedPath;
            repaired++;
          }
          if (existing != null && _sameHistory(existing, next)) {
            continue;
          }
          await GStorage.histories.put(entry.key, next);
          written++;
        } catch (e, stackTrace) {
          failed++;
          KazumiLogger().w(
            'LanSync: apply history entry failed (${entry.key})',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }
      try {
        await GStorage.histories.flush();
      } catch (e, stackTrace) {
        KazumiLogger().w(
          'LanSync: flush histories failed',
          error: e,
          stackTrace: stackTrace,
        );
      }
    });
    if (failed > 0) {
      KazumiLogger().w('LanSync: $failed history entries failed to apply');
    }
    if (repaired > 0) {
      KazumiLogger().i(
        'LanSync: repaired $repaired history path(s) from remote library',
        forceLog: true,
      );
    }
    return written;
  }

  /// 判断远端伪路径是否应当覆盖本地条目的路径。
  ///
  /// 只在本地路径已经失效时返回远端路径：
  /// - 空路径：条目从未记录文件；
  /// - 属于其它桌面端：配对信息变化后遗留的旧伪路径；
  /// - 本机不存在的真实路径：旧版本写入的桌面端真实路径或被覆盖的路径。
  ///
  /// 本机真实存在的文件属于本机媒体库，不能被改写成桌面端路径；已经属于
  /// 当前桌面端的伪路径同样保持原样（可能指向另一集的文件）。
  static String? _repairedPath(History? existing, String incomingPath) {
    if (incomingPath.isEmpty || !isLanMediaPath(incomingPath)) return null;
    final localPath = existing?.episodePageUrl ?? '';
    if (localPath == incomingPath) return null;
    if (isLanMediaPath(localPath)) {
      final incomingServerId = lanServerIdOf(incomingPath) ?? '';
      return isLanPathOfServer(localPath, incomingServerId)
          ? null
          : incomingPath;
    }
    if (localPath.isEmpty) return incomingPath;
    try {
      if (File(localPath).existsSync()) return null;
    } catch (_) {
      // 路径非法（含平台不支持的字符等）一律视为失效。
    }
    return incomingPath;
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
