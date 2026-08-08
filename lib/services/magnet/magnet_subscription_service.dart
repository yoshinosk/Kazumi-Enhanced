import 'dart:async';

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
  MagnetSubscriptionService()
      : _search = MikanSearchService(),
        _animesGarden = AnimesGardenService();

  final MikanSearchService _search;
  final AnimesGardenService _animesGarden;
  Timer? _pollTimer;

  static const Duration _pollInterval = Duration(minutes: 15);

  List<MagnetSubscription> _subscriptions = const [];
  List<MagnetSubscription> get subscriptions =>
      List.unmodifiable(_subscriptions);

  /// 发现新条目时回调，参数为 (订阅, 新条目列表)。
  void Function(MagnetSubscription, List<MagnetSearchItem>)? onNewItems;

  /// 订阅列表变化时回调，供 Controller 持久化状态展示。
  void Function(List<MagnetSubscription>)? onSubscriptionsChanged;

  bool _initialized = false;

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
    );
    final items = await _fetchFeed(base);
    final newSub = base.copyWith(
      lastGuid: items.isEmpty ? null : items.first.magnetLink,
      lastCheckedAt: DateTime.now(),
    );
    _subscriptions = [..._subscriptions, newSub];
    await MagnetSubscriptionStore.save(_subscriptions);
    onSubscriptionsChanged?.call(_subscriptions);
    return newSub;
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
        );
      }
      return s;
    }).toList();
    if (!found) return;
    await MagnetSubscriptionStore.save(_subscriptions);
    onSubscriptionsChanged?.call(_subscriptions);
  }

  Future<void> remove(String id) async {
    _subscriptions = _subscriptions.where((s) => s.id != id).toList();
    await MagnetSubscriptionStore.save(_subscriptions);
    onSubscriptionsChanged?.call(_subscriptions);
  }

  /// 检查所有订阅。出错时跳过该订阅，不影响其他订阅。
  Future<void> checkAll() async {
    if (_subscriptions.isEmpty) return;
    for (final sub in _subscriptions) {
      await _checkOne(sub);
    }
  }

  Future<void> _checkOne(MagnetSubscription sub) async {
    final items = await _fetchFeed(sub);
    if (items.isEmpty) return;
    final lastIndex = sub.lastGuid == null
        ? -1
        : items.indexWhere((e) => e.magnetLink == sub.lastGuid);
    final newItems = lastIndex < 0 ? items : items.sublist(0, lastIndex);
    final updated = sub.copyWith(
      lastGuid: items.first.magnetLink,
      lastCheckedAt: DateTime.now(),
    );
    _subscriptions = _subscriptions
        .map((s) => s.id == sub.id ? updated : s)
        .toList();
    await MagnetSubscriptionStore.save(_subscriptions);
    onSubscriptionsChanged?.call(_subscriptions);
    if (newItems.isNotEmpty) {
      onNewItems?.call(updated, newItems);
    }
  }

  /// 拉取订阅的最新条目（按来源分发），用于「刷新」按钮。
  Future<List<MagnetSearchItem>> fetchLatest(MagnetSubscription sub) {
    return _fetchFeed(sub);
  }

  Future<List<MagnetSearchItem>> _fetchFeed(MagnetSubscription sub) {
    switch (sub.kind) {
      case SubscriptionKind.animesGarden:
        return _animesGarden.fetchSubscriptionFeed(sub);
      case SubscriptionKind.mikan:
        return _search.fetchFeed(sub.feedUrl);
    }
  }
}
