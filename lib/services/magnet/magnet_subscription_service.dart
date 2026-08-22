import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/magnet/animes_garden_service.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/magnet/mikan_search_service.dart';
import 'package:kazumi/services/storage/storage.dart';

/// RSS / 资源订阅轮询服务。
///
/// 支持两种订阅源：
/// - [SubscriptionKind.mikan]：走 RSS XML，复用 [MikanSearchService.fetchFeed]，
///   按 `lastGuid` 判断新条目。
/// - [SubscriptionKind.animesGarden]：走 [AnimesGardenService] JSON API，
///   `feedUrl` 用作搜索关键词，叠加字幕组 / 关键字 / 日期 / 体积等客户端筛选，
///   按 `lastGuid`（最新条目的 magnetLink）判断新条目。
class MagnetSubscriptionService {
  MagnetSubscriptionService({
    Future<List<MagnetSearchItem>> Function(MagnetSubscription)? fetchFeed,
    Future<void> Function(List<MagnetSubscription>)? saveSubscriptions,
  })  : _fetchFeedOverride = fetchFeed,
        _saveSubscriptions = saveSubscriptions ?? MagnetSubscriptionStore.save,
        _search = MikanSearchService(),
        _animesGarden = AnimesGardenService();

  final Future<List<MagnetSearchItem>> Function(MagnetSubscription)?
      _fetchFeedOverride;
  final Future<void> Function(List<MagnetSubscription>) _saveSubscriptions;
  final MikanSearchService _search;
  final AnimesGardenService _animesGarden;
  Timer? _pollTimer;

  /// 订阅自动检查间隔，读取设置中的分钟数（默认 1 小时）。
  Duration get _pollInterval => Duration(
      minutes: GStorage.getSetting(
          SettingsKeys.magnetSubscriptionCheckIntervalMinutes));

  List<MagnetSubscription> _subscriptions = const [];
  List<MagnetSubscription> get subscriptions =>
      List.unmodifiable(_subscriptions);

  /// 发现新条目时回调。返回 true 表示条目已处理，可以推进订阅游标。
  Future<bool> Function(MagnetSubscription, List<MagnetSearchItem>)? onNewItems;

  /// 订阅列表变化时回调，供 Controller 持久化状态展示。
  void Function(List<MagnetSubscription>)? onSubscriptionsChanged;

  bool _initialized = false;
  bool _checking = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _subscriptions = MagnetSubscriptionStore.load();
    onSubscriptionsChanged?.call(_subscriptions);
    _startPolling();
    // 打开软件时立即检查一次更新（引擎就绪后由 onNewItems 自动下载）。
    unawaited(checkAll());
  }

  Future<void> dispose() async {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => checkAll());
  }

  /// 重新读取设置中的检查间隔并重启定时器（设置页调整间隔后调用）。
  Future<void> applySettings() async {
    _startPolling();
  }

  /// 添加订阅，立即拉取并上报当前 feed 条目（视为新内容）触发自动下载，
  /// 成功后游标推进到最新条目；失败（引擎未启用等）不推进游标，下次检查重试。
  Future<MagnetSubscription?> add(MagnetSubscription subscription) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final base = MagnetSubscription(
      id: id,
      name: subscription.name.trim().isEmpty
          ? subscription.feedUrl
          : subscription.name.trim(),
      feedUrl: subscription.feedUrl.trim(),
      createdAt: DateTime.now(),
      kind: subscription.kind,
      fansub: subscription.fansub,
      keywords: subscription.keywords,
      since: subscription.since,
      minSizeMb: subscription.minSizeMb,
      maxSizeMb: subscription.maxSizeMb,
      downloadPath: subscription.downloadPath,
      autoDownload: subscription.autoDownload,
      coverUrl: subscription.coverUrl,
    );
    final items = await _fetchFeed(base);
    // 添加订阅立即上报当前 feed 条目（视为新内容），按 autoDownload 决定
    // 是否自动下载；引擎未启用等失败时不推进游标，下次定时检查重试。
    var acknowledged = true;
    if (items.isNotEmpty && onNewItems != null) {
      acknowledged = await onNewItems!(base, items);
    }
    final newSub = base.copyWith(
      lastGuid: items.isEmpty || !acknowledged ? null : _itemGuid(items.first),
      lastCheckedAt: DateTime.now(),
    );
    _subscriptions = [..._subscriptions, newSub];
    await _saveSubscriptions(_subscriptions);
    onSubscriptionsChanged?.call(_subscriptions);
    return newSub;
  }

  /// 切换订阅的自动下载开关（保留 lastGuid / lastCheckedAt）。
  Future<void> setAutoDownload(String id, bool value) async {
    var found = false;
    _subscriptions = _subscriptions.map((s) {
      if (s.id == id) {
        found = true;
        return s.copyWith(autoDownload: value);
      }
      return s;
    }).toList();
    if (!found) return;
    await _saveSubscriptions(_subscriptions);
    onSubscriptionsChanged?.call(_subscriptions);
  }

  /// 更新已有订阅的筛选条件（保留 lastGuid / lastCheckedAt）。
  Future<void> update(MagnetSubscription updated) async {
    var found = false;
    _subscriptions = _subscriptions.map((s) {
      if (s.id == updated.id) {
        found = true;
        return MagnetSubscription(
          id: s.id,
          name: updated.name.trim().isEmpty ? s.name : updated.name.trim(),
          feedUrl: updated.feedUrl.trim(),
          createdAt: s.createdAt,
          lastGuid: s.lastGuid,
          lastCheckedAt: s.lastCheckedAt,
          kind: updated.kind,
          fansub: updated.fansub,
          keywords: updated.keywords,
          since: updated.since,
          minSizeMb: updated.minSizeMb,
          maxSizeMb: updated.maxSizeMb,
          downloadPath: updated.downloadPath,
          autoDownload: updated.autoDownload,
          coverUrl: updated.coverUrl,
        );
      }
      return s;
    }).toList();
    if (!found) return;
    await _saveSubscriptions(_subscriptions);
    onSubscriptionsChanged?.call(_subscriptions);
  }

  Future<void> remove(String id) async {
    _subscriptions = _subscriptions.where((s) => s.id != id).toList();
    await _saveSubscriptions(_subscriptions);
    onSubscriptionsChanged?.call(_subscriptions);
  }

  /// 检查所有订阅。出错时跳过该订阅，不影响其他订阅。
  ///
  /// 通过 [_checking] 互斥：定时轮询与手动「检查更新」可能重叠执行，
  /// 重叠会导致同一批新条目被重复上报、重复创建下载任务。
  Future<void> checkAll() async {
    if (_checking || _subscriptions.isEmpty) return;
    _checking = true;
    try {
      for (final sub in _subscriptions) {
        try {
          await _checkOne(sub);
        } catch (e) {
          KazumiLogger().w(
            'MagnetSubscriptionService: check failed for ${sub.name}',
            error: e,
          );
        }
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _checkOne(MagnetSubscription sub) async {
    final items = await _fetchFeed(sub);
    if (items.isEmpty) return;
    final firstGuid = _itemGuid(items.first);
    // 条目既无磁力链也无种子直链时无法定位去重键，放弃本轮检测，
    // 避免把所有条目误报为新条目反复触发自动下载。
    if (firstGuid.isEmpty) return;
    // 游标未初始化（添加订阅时首拉为空 / 添加时下载失败未推进游标）：
    // 整个 feed 视为新条目上报；命中自动下载则推进游标，否则下一轮重试。
    final lastGuid = sub.lastGuid;
    final newItems = (lastGuid == null || lastGuid.isEmpty)
        ? items
        : _itemsSince(items, lastGuid);
    var acknowledged = true;
    if (newItems.isNotEmpty && onNewItems != null) {
      acknowledged = await onNewItems!(sub, newItems);
    }
    final updated = sub.copyWith(
      lastGuid: acknowledged ? firstGuid : sub.lastGuid,
      lastCheckedAt: DateTime.now(),
    );
    _subscriptions =
        _subscriptions.map((s) => s.id == sub.id ? updated : s).toList();
    await _saveSubscriptions(_subscriptions);
    onSubscriptionsChanged?.call(_subscriptions);
  }

  /// 返回游标之后的条目（游标不在列表中时整份列表都视为新条目）。
  static List<MagnetSearchItem> _itemsSince(
      List<MagnetSearchItem> items, String guid) {
    final lastIndex = items.indexWhere((e) => _itemGuid(e) == guid);
    return lastIndex < 0 ? items : items.sublist(0, lastIndex);
  }

  @visibleForTesting
  Future<void> checkSubscriptionForTest(MagnetSubscription subscription) async {
    if (!_subscriptions.any((item) => item.id == subscription.id)) {
      _subscriptions = [subscription];
    }
    await _checkOne(subscription);
  }

  /// 拉取订阅的最新条目（按来源分发），用于「刷新」按钮。
  Future<List<MagnetSearchItem>> fetchLatest(MagnetSubscription sub) {
    return _fetchFeed(sub);
  }

  /// 条目去重键：磁力链优先，缺失时回退种子直链（Mikan 的 enclosure
  /// 通常是 .torrent 直链而非磁力链）。
  static String _itemGuid(MagnetSearchItem item) =>
      item.magnetLink.isNotEmpty ? item.magnetLink : item.torrentUrl;

  Future<List<MagnetSearchItem>> _fetchFeed(MagnetSubscription sub) {
    final override = _fetchFeedOverride;
    if (override != null) return override(sub);
    switch (sub.kind) {
      case SubscriptionKind.animesGarden:
        return _animesGarden.fetchSubscriptionFeed(sub);
      case SubscriptionKind.mikan:
        return _search.fetchFeed(sub.feedUrl);
    }
  }
}
