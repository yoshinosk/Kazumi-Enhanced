import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/magnet/animes_garden_service.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/magnet/mikan_search_service.dart';

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

  static const Duration _pollInterval = Duration(minutes: 15);

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
  }

  Future<void> dispose() async {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => checkAll());
  }

  /// 添加订阅，立即拉取一次以初始化 lastGuid，不触发 onNewItems。
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
    );
    final items = await _fetchFeed(base);
    final newSub = base.copyWith(
      lastGuid: items.isEmpty ? null : _itemGuid(items.first),
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
    final lastIndex = (sub.lastGuid == null || sub.lastGuid!.isEmpty)
        ? -1
        : items.indexWhere((e) => _itemGuid(e) == sub.lastGuid);
    final newItems = lastIndex < 0 ? items : items.sublist(0, lastIndex);
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
