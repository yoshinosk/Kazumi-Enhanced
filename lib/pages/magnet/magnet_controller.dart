import 'dart:async';

import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/magnet/animes_garden_service.dart';
import 'package:kazumi/services/magnet/libtorrent_engine.dart';
import 'package:kazumi/services/magnet/magnet_download_service.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/magnet/magnet_search_sources.dart';
import 'package:kazumi/services/magnet/magnet_subscription_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:mobx/mobx.dart';

part 'magnet_controller.g.dart';

class MagnetController = _MagnetController with _$MagnetController;

String? _cleanOptional(String? value) {
  final v = value?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

abstract class _MagnetController with Store {
  _MagnetController()
      : _engine = MagnetSearchEngine(),
        _downloads = MagnetDownloadService(),
        _subscriptions = MagnetSubscriptionService(),
        _animesGarden = AnimesGardenService();

  final MagnetSearchEngine _engine;
  final MagnetDownloadService _downloads;
  final MagnetSubscriptionService _subscriptions;
  final AnimesGardenService _animesGarden;

  bool _initialized = false;

  @observable
  String query = '';

  @observable
  ObservableList<MagnetSearchItem> searchResults = ObservableList();

  @observable
  bool isSearching = false;

  @observable
  String? searchError;

  @observable
  bool hasMoreSearchResults = false;

  @observable
  bool isLoadingMore = false;

  /// 当前搜索会话的字幕组筛选（仅 AG 源生效）。
  /// null 表示不限；初值取自设置默认值，可在搜索页覆盖。
  @observable
  String? searchFansub =
      _cleanOptional(GStorage.getSetting(SettingsKeys.animesGardenFansub));

  int _searchPage = 1;

  @observable
  ObservableList<MagnetSubscription> subscriptions = ObservableList();

  @observable
  ObservableList<MagnetDownloadEntry> downloadTasks = ObservableList();

  @observable
  ObservableMap<String, ObservableList<MagnetSearchItem>> subscriptionFeeds =
      ObservableMap();

  @observable
  String currentSourceId =
      GStorage.getSetting(SettingsKeys.magnetDefaultSource);

  bool get engineEnabled => _downloads.engineEnabled;

  /// 内置引擎状态。
  @observable
  LibtorrentEngineState engineState = LibtorrentEngineState.stopped;

  @observable
  String? engineError;

  /// 内置引擎正在运行吗。
  bool get engineRunning => engineState == LibtorrentEngineState.running;

  /// Tracker 缓存数量。
  @observable
  int trackerCount = 0;

  /// Tracker 最近更新时间。
  @observable
  DateTime? trackerUpdatedAt;

  @observable
  bool trackerUpdating = false;

  /// 当前默认搜索源。
  MagnetSearchSource get defaultSource =>
      MagnetSearchSources.byId(currentSourceId);

  /// 切换当前搜索源，并持久化为默认源。
  @action
  Future<void> setSearchSource(String sourceId) async {
    final source = MagnetSearchSources.byId(sourceId);
    currentSourceId = source.id;
    await GStorage.putSetting(SettingsKeys.magnetDefaultSource, source.id);
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _downloads.onChanged = (entries) {
      downloadTasks
        ..clear()
        ..addAll(entries);
    };
    _downloads.onEngineStateChanged = (state) {
      engineState = state;
      engineError = _downloads.engine.lastError;
    };
    _subscriptions.onSubscriptionsChanged = (list) {
      subscriptions
        ..clear()
        ..addAll(list);
    };
    _subscriptions.onNewItems = (sub, items) {
      KazumiLogger().i('Magnet: ${items.length} new items for ${sub.name}');
      KazumiDialog.showToast(
        message: '订阅「${sub.name}」有 ${items.length} 条新内容',
        duration: const Duration(seconds: 3),
      );
      // 订阅自动下载：引擎启用时把新条目提交下载，使用订阅指定的下载目录。
      if (_downloads.engineEnabled && items.isNotEmpty) {
        for (final item in items) {
          _downloads.add(item, dir: sub.downloadPath);
        }
      }
    };
    try {
      await _downloads.init();
    } catch (e) {
      KazumiLogger().w('MagnetController: download service init failed', error: e);
    }
    try {
      await _subscriptions.init();
    } catch (e) {
      KazumiLogger()
          .w('MagnetController: subscription service init failed', error: e);
    }
    _refreshEngineInfo();
  }

  Future<void> dispose() async {
    await _downloads.dispose();
    await _subscriptions.dispose();
  }

  /// 同步引擎 / tracker 状态到 observable。
  void _refreshEngineInfo() {
    engineState = _downloads.engineState;
    engineError = _downloads.engine.lastError;
    trackerCount = _downloads.cachedTrackerCount;
    trackerUpdatedAt = _downloads.trackerLastUpdated;
  }

  /// 手动启动内置引擎。
  @action
  Future<bool> startBuiltinEngine() async {
    final ok = await _downloads.startEngine();
    _refreshEngineInfo();
    if (!ok) {
      KazumiDialog.showToast(message: _downloads.engine.lastError ?? '引擎启动失败');
    }
    return ok;
  }

  /// 手动停止内置引擎。
  @action
  Future<void> stopBuiltinEngine() async {
    await _downloads.stopEngine();
    _refreshEngineInfo();
  }

  /// 立即更新 tracker 列表。
  @action
  Future<void> updateTrackers() async {
    trackerUpdating = true;
    final count = await _downloads.updateTrackers();
    trackerUpdating = false;
    _refreshEngineInfo();
    if (count > 0) {
      KazumiDialog.showToast(
        message: 'Tracker 已更新：$count 个可用节点',
        duration: const Duration(seconds: 3),
      );
    } else {
      KazumiDialog.showToast(message: 'Tracker 更新失败，请检查网络后重试');
    }
  }

  @action
  void setQuery(String value) {
    query = value;
  }

  @action
  Future<void> search(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      searchResults.clear();
      searchError = null;
      hasMoreSearchResults = false;
      return;
    }
    isSearching = true;
    searchError = null;
    query = trimmed;
    _searchPage = 1;
    try {
      final result = await _engine.searchPage(
        trimmed,
        defaultSource,
        fansub: searchFansub,
      );
      searchResults
        ..clear()
        ..addAll(result.items);
      hasMoreSearchResults = result.hasMore;
      if (result.items.isEmpty) {
        searchError = '没有找到相关资源。可尝试切换其它搜索源，或检查代理设置（这些站点通常需要代理才能访问）';
      }
    } catch (e) {
      searchError = '搜索失败：$e';
      KazumiLogger().w('MagnetController: search failed', error: e);
    } finally {
      isSearching = false;
    }
  }

  /// 加载下一页搜索结果（仅 Animes Garden 源支持）。
  @action
  Future<void> loadMore() async {
    if (isLoadingMore || !hasMoreSearchResults) return;
    if (defaultSource.kind != MagnetSourceKind.json) return;
    isLoadingMore = true;
    try {
      _searchPage += 1;
      final result = await _engine.searchPage(
        query,
        defaultSource,
        page: _searchPage,
        fansub: searchFansub,
      );
      searchResults.addAll(result.items);
      hasMoreSearchResults = result.hasMore;
    } catch (e) {
      _searchPage -= 1;
      KazumiLogger().w('MagnetController: loadMore failed', error: e);
    } finally {
      isLoadingMore = false;
    }
  }

  /// 设置搜索字幕组筛选并重新搜索。null 表示不限。
  @action
  Future<void> setSearchFansub(String? fansub) async {
    searchFansub = fansub;
    if (query.trim().isNotEmpty) {
      await search(query);
    }
  }

  @action
  Future<void> refreshSearch() => search(query);

  /// 拉取 Animes Garden 字幕组列表（供订阅 / 设置页下拉）。
  Future<List<AnimesGardenTeam>> fetchAnimesGardenTeams() {
    return _animesGarden.fetchTeams();
  }

  @action
  Future<void> addSubscription(MagnetSubscription subscription) async {
    try {
      await _subscriptions.add(subscription);
      KazumiDialog.showToast(message: '订阅已添加');
    } catch (e) {
      KazumiDialog.showToast(message: '添加订阅失败：$e');
    }
  }

  @action
  Future<void> updateSubscription(MagnetSubscription updated) async {
    try {
      await _subscriptions.update(updated);
      KazumiDialog.showToast(message: '订阅已更新');
    } catch (e) {
      KazumiDialog.showToast(message: '更新订阅失败：$e');
    }
  }

  @action
  Future<void> removeSubscription(String id) async {
    await _subscriptions.remove(id);
    subscriptionFeeds.remove(id);
  }

  @action
  Future<void> loadSubscriptionFeed(MagnetSubscription sub) async {
    final items = await _subscriptions.fetchLatest(sub);
    subscriptionFeeds[sub.id] = ObservableList.of(items);
  }

  @action
  Future<void> checkSubscriptions() async {
    await _subscriptions.checkAll();
    KazumiDialog.showToast(message: '已检查所有订阅');
  }

  @action
  Future<void> addDownload(MagnetSearchItem item, {String? dir}) async {
    if (!engineEnabled) {
      KazumiDialog.showToast(message: '请先在设置中开启磁力下载引擎');
      return;
    }
    final gid = await _downloads.add(item, dir: dir);
    if (gid.isEmpty) {
      KazumiDialog.showToast(message: '提交下载失败，请检查引擎状态');
      return;
    }
    KazumiDialog.showToast(message: '已添加到下载队列');
  }

  @action
  Future<void> pauseDownload(String gid) async {
    final ok = await _downloads.pause(gid);
    if (!ok) KazumiDialog.showToast(message: '暂停任务失败');
  }

  @action
  Future<void> resumeDownload(String gid) async {
    final ok = await _downloads.unpause(gid);
    if (!ok) KazumiDialog.showToast(message: '恢复任务失败');
  }

  @action
  Future<void> removeDownload(String gid) async {
    final ok = await _downloads.remove(gid);
    if (!ok) KazumiDialog.showToast(message: '删除任务失败');
  }

  @action
  Future<void> refreshDownloads() => _downloads.refresh();

  /// 引擎设置变化时调用，重新启动 / 停止引擎。
  @action
  Future<void> applyMagnetSettingsChanged() async {
    await _downloads.applySettingsChanged();
    _refreshEngineInfo();
  }

  /// 测试引擎连接，返回 libtorrent 版本或 null。
  Future<String?> pingEngine() => _downloads.ping();
}