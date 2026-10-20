import 'package:kazumi/modules/collect/collect_change_module.dart';
import 'package:kazumi/services/lan/lan_sync_models.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 局域网收藏状态的导出与落盘。
///
/// 删除使用 `collectChanges` 中最近的 action=3 作为墓碑，这样一端删除收藏
/// 后不会被另一端的旧数据直接复活；后续重新收藏会以更新的时间覆盖墓碑。
class LanCollectStore {
  List<LanCollectibleEntry> exportCollectibles() {
    return [
      for (final collectible in GStorage.collectibles.values)
        if (collectible.bangumiItem.id > 0)
          LanCollectibleEntry.fromCollected(collectible),
    ];
  }

  /// 每个番剧只取最后一条变更；最后一条是删除时导出墓碑。
  List<LanCollectTombstone> exportTombstones() {
    final latest = <int, CollectedBangumiChange>{};
    for (final change in GStorage.collectChanges.values) {
      if (change.bangumiID <= 0) continue;
      final existing = latest[change.bangumiID];
      if (existing == null ||
          change.timestamp > existing.timestamp ||
          (change.timestamp == existing.timestamp && change.id > existing.id)) {
        latest[change.bangumiID] = change;
      }
    }
    return [
      for (final change in latest.values)
        if (change.action == 3)
          LanCollectTombstone(
            bangumiId: change.bangumiID,
            updatedAtMs: change.timestamp * 1000,
          ),
    ];
  }

  /// 应用合并结果；仅写入真正变化的条目。
  Future<int> applyMerged(LanCollectMergeResult result) async {
    var applied = 0;
    final liveById = {
      for (final entry in result.collectibles) entry.bangumiId: entry,
    };
    final tombstoneById = {
      for (final entry in result.tombstones) entry.bangumiId: entry,
    };
    // 应用期间本地可能又删除过收藏；这种情况下不要用较旧的合并结果复活它。
    final latestLocalTombstones = {
      for (final entry in exportTombstones()) entry.bangumiId: entry,
    };

    try {
      // 删除：只处理合并结果明确带有墓碑的本机条目。
      for (final collectible in GStorage.collectibles.values.toList()) {
        final id = collectible.bangumiItem.id;
        if (id <= 0 || liveById.containsKey(id)) continue;
        final tombstone = tombstoneById[id];
        if (tombstone == null) continue;
        // 合并快照生成后本地又改了状态：以更新的本地状态为准。
        if (collectible.time.millisecondsSinceEpoch >= tombstone.updatedAtMs) {
          continue;
        }
        await GStorage.deleteCollectible(id);
        await GStorage.appendCollectChange(
          bangumiId: id,
          action: 3,
          type: 5,
          timestamp: tombstone.updatedAtMs ~/ 1000,
        );
        applied++;
      }

      for (final entry in result.collectibles) {
        final existing = GStorage.collectibles.get(entry.bangumiId);
        if (existing != null) {
          final existingEntry = LanCollectibleEntry.fromCollected(existing);
          final existingWins =
              existingEntry.timeMs > entry.timeMs ||
              (existingEntry.timeMs == entry.timeMs &&
                  collectTypePriority(existingEntry.type) >
                      collectTypePriority(entry.type));
          if (existingWins) continue;
          if (existingEntry.type == entry.type &&
              existingEntry.timeMs == entry.timeMs) {
            continue;
          }
        }
        final localTombstone = latestLocalTombstones[entry.bangumiId];
        if (localTombstone != null &&
            localTombstone.updatedAtMs > entry.timeMs) {
          continue;
        }
        final isNew = existing == null;
        final typeChanged = existing != null && existing.type != entry.type;
        await GStorage.putCollectible(entry.toCollected());
        // 只有新增 / 状态变化需要写入 WebDAV 增量日志；单纯时间推进
        // 不产生看似“重新收藏”的变更。
        if (isNew || typeChanged) {
          await GStorage.appendCollectChange(
            bangumiId: entry.bangumiId,
            action: isNew ? 1 : 2,
            type: entry.type,
            timestamp: entry.timeMs ~/ 1000,
          );
        }
        applied++;
      }
    } catch (e, stackTrace) {
      KazumiLogger().w(
        'LanSync: apply collectibles failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
    return applied;
  }
}
