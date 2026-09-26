import 'dart:convert';

import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 弹幕时间轴偏移的作用域读写。
///
/// 弹幕轴自动检测推荐的偏移按「bangumiID:episodeId」作用域存储：单集的
/// 检测结果不再永久作用于之后所有剧集，其他番剧 / 分集仍会自动触发检测。
/// 未命中作用域时回退到全局 [SettingsKeys.danmakuTimeOffset]（用户手动
/// 调整的全局偏移）。episodeId 未知（自动加载弹幕）时为 0，同番剧共享
/// 该番剧作用域。
class DanmakuTimeOffsetStore {
  DanmakuTimeOffsetStore._();

  static const int _bangumiOnlyEpisodeId = 0;

  /// 偏移量合法范围（秒），与手动调整 UI 保持一致。
  static const double _maxOffsetSeconds = 180;

  static String _scopeKey(int bangumiID, int episodeId) =>
      '$bangumiID:$episodeId';

  /// 标准化偏移量：四舍五入并限制在 ±180 秒。
  static double normalize(double offset) {
    return offset
        .round()
        .clamp(-_maxOffsetSeconds, _maxOffsetSeconds)
        .toDouble();
  }

  /// 读取当前作用域的偏移：精确分集 → 同番剧（episodeId=0）→ 全局。
  static double effectiveOffset(int bangumiID, int episodeId) {
    final scoped = _readScoped();
    final exact = scoped[_scopeKey(bangumiID, episodeId)];
    if (exact != null) return exact;
    final bangumi = scoped[_scopeKey(bangumiID, _bangumiOnlyEpisodeId)];
    if (bangumi != null) return bangumi;
    return GStorage.getSetting<double>(SettingsKeys.danmakuTimeOffset);
  }

  /// 写入作用域偏移。
  ///
  /// 0 也会显式存储：作用域内「明确无偏移」必须能遮蔽番剧级作用域与
  /// 全局偏移，否则「恢复无偏移」在有作用域偏移时不生效。
  static Future<void> setScopedOffset(
    int bangumiID,
    int episodeId,
    double offset,
  ) async {
    final scoped = _readScoped();
    scoped[_scopeKey(bangumiID, episodeId)] = normalize(offset);
    await GStorage.putSetting<String>(
      SettingsKeys.danmakuTimeOffsetByEpisode,
      jsonEncode(scoped),
    );
  }

  /// 一次性迁移：清除历史番剧级（`bangumiID:0`）作用域偏移。
  ///
  /// 旧版弹幕轴自动检测在 episodeId 未知时把推荐偏移写成了番剧级作用域，
  /// 单集的检测结果会污染同番剧所有分集，且遮蔽用户的全局手动调整，
  /// 这里统一清除（检测会按新的分集级作用域重新触发）。
  static Future<void> migrateLegacyBangumiScopes() async {
    if (GStorage.getSetting<bool>(SettingsKeys.danmakuTimeOffsetScopeMigrated)) {
      return;
    }
    final scoped = _readScoped();
    scoped.removeWhere((key, _) => key.endsWith(':$_bangumiOnlyEpisodeId'));
    await GStorage.putSetting<String>(
      SettingsKeys.danmakuTimeOffsetByEpisode,
      jsonEncode(scoped),
    );
    await GStorage.putSetting<bool>(
      SettingsKeys.danmakuTimeOffsetScopeMigrated,
      true,
    );
  }

  /// 一次性迁移：清零遗留的全局弹幕轴偏移 [SettingsKeys.danmakuTimeOffset]。
  ///
  /// 更早版本的手动调整（快速菜单 / 详细调整面板 / 自动检测「应用推荐偏移」）
  /// 全部直接写入全局设置，且当时会被已存在的番剧级作用域偏移遮蔽「看似无效」，
  /// 用户反复点击后全局累积出从未生效的偏移（如 -82 秒）。偏移作用域化后，
  /// 该遗留值作为 `effectiveOffset` 的兜底作用于所有未命中作用域的视频，
  /// 表现为「所有视频弹幕提前 / 延后固定时长」。迁移统一清零；
  /// 此后用户重新调整的全局偏移（弹幕未绑定番剧时写入）不再清除。
  static Future<void> migrateLegacyGlobalOffset() async {
    if (GStorage
        .getSetting<bool>(SettingsKeys.danmakuTimeOffsetGlobalMigrated)) {
      return;
    }
    final legacy = GStorage.getSetting<double>(SettingsKeys.danmakuTimeOffset);
    if (legacy != 0) {
      await GStorage.putSetting<double>(SettingsKeys.danmakuTimeOffset, 0.0);
      KazumiLogger().i(
          'DanmakuTimeOffsetStore: cleared legacy global offset ${legacy}s',
          forceLog: true);
    }
    await GStorage.putSetting<bool>(
        SettingsKeys.danmakuTimeOffsetGlobalMigrated, true);
  }

  static Map<String, double> _readScoped() {
    final raw =
        GStorage.getSetting<String>(SettingsKeys.danmakuTimeOffsetByEpisode);
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(
            key.toString(),
            value is num ? value.toDouble() : 0.0,
          ),
        );
      }
    } catch (e) {
      KazumiLogger()
          .w('DanmakuTimeOffsetStore: read scoped offset failed', error: e);
    }
    return {};
  }
}
