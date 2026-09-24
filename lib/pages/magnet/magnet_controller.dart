import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/magnet/animes_garden_service.dart';
import 'package:kazumi/services/magnet/libtorrent_engine.dart';
import 'package:kazumi/services/magnet/magnet_download_service.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/magnet/magnet_search_sources.dart';
import 'package:kazumi/services/magnet/magnet_subscription_service.dart';
import 'package:kazumi/services/download/background_download_service.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/media/local_media_scanner.dart';
import 'package:kazumi/services/media/media_scraper.dart';
import 'package:kazumi/services/notification/app_notifications.dart';
import 'package:kazumi/services/platform/android_storage_access.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:kazumi/utils/disk_space.dart';
import 'package:kazumi/utils/format.dart' show formatSpeed;
import 'package:kazumi/utils/local_episode_parser.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart' hide formatSpeed;
import 'package:mobx/mobx.dart';
import 'package:path/path.dart' as p;

part 'magnet_controller.g.dart';

class MagnetController = _MagnetController with _$MagnetController;

String? _cleanOptional(String? value) {
  final v = value?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

abstract class _MagnetController with Store {
  _MagnetController({MediaController? mediaController})
      : _engine = MagnetSearchEngine(),
        _downloads = MagnetDownloadService(),
        _subscriptions = MagnetSubscriptionService(),
        _animesGarden = AnimesGardenService(),
        _mediaController = mediaController;

  final MagnetSearchEngine _engine;
  final MagnetDownloadService _downloads;
  final MagnetSubscriptionService _subscriptions;
  final AnimesGardenService _animesGarden;
  final MediaScraper _scraper = MediaScraper();
  final LocalMediaScanner _scanner = LocalMediaScanner();

  /// Android 前台下载服务（与在线视频下载共享，租约制）。
  final BackgroundDownloadService _bgService = BackgroundDownloadService();

  /// 前台服务通知节流：距上次更新不足该间隔时跳过。
  DateTime? _lastBgServiceUpdate;

  /// 本地媒体库控制器，用于把已完成任务的搜刮结果同步到媒体库。
  /// 由 InitPage 在启动时注入；独立构建（测试等）时可缺省。
  MediaController? _mediaController;

  /// 关联本地媒体库控制器（启动时由 InitPage 注入，必须在 init() 前调用）。
  void attachMediaController(MediaController controller) {
    _mediaController = controller;
  }

  /// 已同步刮削信息、已自动入库和正在入库的稳定任务 ID。
  final Set<String> _scrapeSyncedTaskIds = {};
  final Set<String> _scrapeSyncingTaskIds = {};
  final Set<String> _autoImportedTaskIds = {};
  final Set<String> _autoImportingTaskIds = {};

  /// 搜刮键缓存：taskId → (文件清单指纹, 键)。onChanged 每 2s 触发一次，
  /// 未同步任务的键计算涉及目录分组扫描（同步 IO + 重量级 scraper），
  /// 按指纹缓存避免重复计算；清单 / 选择 / 路径变化时指纹失效自动重算。
  final Map<String, (int, String)> _scrapeKeyCache = {};

  /// 搜刮结果同步到媒体库的连续失败计数（taskId → 次数）。
  final Map<String, int> _scrapeSyncFailures = {};

  /// 同步连续失败上限：超过后本会话不再重试，避免每 2s 一轮的无限重试。
  static const int _maxScrapeSyncFailures = 3;

  /// 正在自动搜刮的任务 ID（防重入）。
  final Set<String> _autoScrapingTaskIds = {};

  /// 任务上次状态快照（用于检测终态跳变发通知）。
  final Map<String, String> _lastTaskStatuses = {};

  /// 启动首帧标记：init() 的首次 onChanged 会推送全部持久化条目，
  /// 只用来初始化状态快照，不触发通知 / 自动搜刮 / 自动入库。
  bool _initialSnapshotHandled = false;

  /// 本会话内进入 complete / seeding 终态的任务（自动搜刮 / 入库只对
  /// 这些任务生效，避免每次启动对历史已完成任务重跑并弹权限提示）。
  final Set<String> _sessionFinalTaskIds = {};

  /// 本会话内自动入库已失败的任务（静默跳过后续重试，避免每 2s 一轮
  /// 的 onChanged 反复尝试；重启后可重新触发）。
  final Set<String> _autoImportFailedTaskIds = {};

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

  /// 当前关键词下搜索结果中出现过的字幕组候选（去重）。
  /// 独立于 searchResults 缓存，避免选中某字幕组后
  /// 服务端过滤导致候选列表只剩当前选中项。
  final Set<String> _fansubOptions = {};
  String? _fansubOptionsQuery;

  /// 字幕组候选（排序后的副本），供筛选选择器展示。
  List<String> get fansubOptions {
    final list = _fansubOptions.toList()..sort();
    return list;
  }

  int _searchPage = 1;

  @observable
  ObservableList<MagnetSubscription> subscriptions = ObservableList();

  @observable
  ObservableList<MagnetDownloadEntry> downloadTasks = ObservableList();

  @observable
  ObservableMap<String, ObservableList<MagnetSearchItem>> subscriptionFeeds =
      ObservableMap();

  /// 条目加载失败的订阅 ID（展开区显示错误与重试入口）。
  @observable
  ObservableSet<String> subscriptionFeedErrors = ObservableSet<String>();

  /// 最近搜索关键词（新 → 旧，持久化在设置中）。
  @observable
  ObservableList<String> searchHistory = ObservableList();

  /// 搜索历史保留条数上限。
  static const int _maxSearchHistory = 20;

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
    // 通知栏「暂停全部」按钮同时作用于磁力任务（与在线下载共享前台服务）。
    _bgService.addTaskDataCallback(_onForegroundTaskData);
    _downloads.onChanged = (entries) {
      downloadTasks
        ..clear()
        ..addAll(entries);
      _notifyFinalStates(entries);
      _syncForegroundService(entries);
      _syncCompletedToLibrary(entries);
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
    _subscriptions.onNewItems = (sub, items) async {
      KazumiLogger().i('Magnet: ${items.length} new items for ${sub.name}');
      // 订阅自动下载：引擎启用且订阅开启自动下载时把新条目提交下载，
      // 使用订阅指定的下载目录；按磁力链去重，避免重复任务。
      if (!sub.autoDownload) {
        KazumiDialog.showToast(
          message: '订阅「${sub.name}」有 ${items.length} 条新内容（自动下载已关闭）',
          duration: const Duration(seconds: 3),
        );
        return true;
      }
      KazumiDialog.showToast(
        message: '订阅「${sub.name}」有 ${items.length} 条新内容',
        duration: const Duration(seconds: 3),
      );
      if (!_downloads.engineEnabled) {
        KazumiDialog.showToast(message: '下载引擎未启用，订阅内容将在下次检查时重试');
        return false;
      }
      for (final item in items) {
        final uri =
            item.magnetLink.isNotEmpty ? item.magnetLink : item.torrentUrl;
        if (uri.isEmpty || _downloads.hasDownload(uri)) continue;
        final taskId = await _downloads.add(item, dir: sub.downloadPath);
        if (taskId.isEmpty) return false;
      }
      return true;
    };
    try {
      await _downloads.init();
    } catch (e) {
      KazumiLogger()
          .w('MagnetController: download service init failed', error: e);
    }
    try {
      await _subscriptions.init();
    } catch (e) {
      KazumiLogger()
          .w('MagnetController: subscription service init failed', error: e);
    }
    _loadSearchHistory();
    _refreshEngineInfo();
  }

  /// 从设置中恢复搜索历史（JSON 数组，旧 → 新）。
  void _loadSearchHistory() {
    final raw = GStorage.getSetting(SettingsKeys.magnetSearchHistory);
    if (raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      searchHistory
        ..clear()
        ..addAll(list.cast<String>().take(_maxSearchHistory));
    } catch (e) {
      KazumiLogger().w('MagnetController: load search history failed', error: e);
    }
  }

  /// 把关键词写入搜索历史（去重后置顶，超限截断）并持久化。
  void _rememberSearchQuery(String keyword) {
    searchHistory
      ..removeWhere((k) => k == keyword)
      ..insert(0, keyword);
    if (searchHistory.length > _maxSearchHistory) {
      searchHistory.removeRange(_maxSearchHistory, searchHistory.length);
    }
    unawaited(_saveSearchHistory());
  }

  Future<void> _saveSearchHistory() async {
    try {
      await GStorage.putSetting(
        SettingsKeys.magnetSearchHistory,
        jsonEncode(searchHistory.toList()),
      );
    } catch (e) {
      KazumiLogger().w('MagnetController: save search history failed', error: e);
    }
  }

  /// 删除单条搜索历史。
  @action
  Future<void> removeSearchHistory(String keyword) async {
    searchHistory.removeWhere((k) => k == keyword);
    await _saveSearchHistory();
  }

  /// 清空全部搜索历史。
  @action
  Future<void> clearSearchHistory() async {
    searchHistory.clear();
    await _saveSearchHistory();
  }

  Future<void> dispose() async {
    _bgService.removeTaskDataCallback(_onForegroundTaskData);
    await _bgService.release(BackgroundDownloadService.magnetLease);
    await _downloads.dispose();
    await _subscriptions.dispose();
  }

  void _onForegroundTaskData(Object data) {
    if (data is Map &&
        data['action'] == 'button_pressed' &&
        data['id'] == 'pause_all') {
      unawaited(pauseAllDownloads());
    }
  }

  /// 同步前台服务租约：有下载中的磁力任务时持有并展示进度通知，
  /// 全部完成 / 暂停后释放（让服务可被在线下载或随最后租约释放而停止）。
  void _syncForegroundService(List<MagnetDownloadEntry> entries) {
    if (!_bgService.isSupported) return;
    final active = entries.where((e) => e.isDownloading).toList();
    if (active.isEmpty) {
      _lastBgServiceUpdate = null;
      unawaited(_bgService.release(BackgroundDownloadService.magnetLease));
      return;
    }
    unawaited(_bgService.acquire(BackgroundDownloadService.magnetLease));
    final now = DateTime.now();
    if (_lastBgServiceUpdate != null &&
        now.difference(_lastBgServiceUpdate!) < const Duration(seconds: 2)) {
      return;
    }
    _lastBgServiceUpdate = now;
    final total = entries.where((e) => e.isDownloading || e.isQueued).length;
    final speed =
        active.fold<int>(0, (sum, e) => sum + e.downloadSpeed);
    final speedText = speed > 0 ? formatSpeed(speed.toDouble()) : '等待中';
    final firstName = active.first.fileName.isNotEmpty
        ? active.first.fileName
        : active.first.title;
    unawaited(_bgService.updateNotification(
      BackgroundDownloadService.magnetLease,
      title: '磁力下载中 (${active.length}/$total)',
      text: '$speedText · ${firstName.isNotEmpty ? firstName : '磁力下载'}',
    ));
  }

  /// 暂停全部磁力下载任务。
  @action
  Future<void> pauseAllDownloads() async {
    for (final entry in List.of(downloadTasks)) {
      if (entry.isDownloading || entry.isQueued) {
        await _downloads.pause(entry.taskId);
      }
    }
  }

  /// 继续全部已暂停 / 排队中的磁力下载任务。
  @action
  Future<void> resumeAllDownloads() async {
    for (final entry in List.of(downloadTasks)) {
      if (entry.isPaused || entry.isQueued) {
        await _downloads.unpause(entry.taskId);
      }
    }
  }

  /// 正在进行（下载 / 排队 / 校验 / 获取元数据 / 做种）的任务数。
  int get activeDownloadCount => downloadTasks
      .where((t) => t.isDownloading || t.isQueued || t.isSeeding)
      .length;

  /// 已暂停 / 排队等待继续的任务数。
  int get pausableDownloadCount =>
      downloadTasks.where((t) => t.isDownloading || t.isQueued).length;

  int get resumableDownloadCount =>
      downloadTasks.where((t) => t.isPaused || t.isQueued).length;

  /// 全部任务的总下载速度（字节 / 秒）。
  int get totalDownloadSpeed =>
      downloadTasks.fold<int>(0, (sum, t) => sum + t.downloadSpeed);

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
      // 清空搜索：同时重置关键词，让工具栏（订阅当前搜索等）随之隐藏。
      query = '';
      searchResults.clear();
      searchError = null;
      hasMoreSearchResults = false;
      _fansubOptions.clear();
      _fansubOptionsQuery = null;
      return;
    }
    if (_fansubOptionsQuery != trimmed) {
      // 新关键词：重置字幕组候选缓存
      _fansubOptionsQuery = trimmed;
      _fansubOptions.clear();
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
      _rememberFansubs(result.items);
      _rememberSearchQuery(trimmed);
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
      _rememberFansubs(result.items);
    } catch (e) {
      _searchPage -= 1;
      KazumiLogger().w('MagnetController: loadMore failed', error: e);
    } finally {
      isLoadingMore = false;
    }
  }

  /// 将搜索结果中的字幕组并入候选缓存（忽略空白）。
  void _rememberFansubs(Iterable<MagnetSearchItem> items) {
    for (final item in items) {
      final f = item.publisher?.trim();
      if (f != null && f.isNotEmpty) _fansubOptions.add(f);
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

  /// 更新订阅封面图（列表懒加载回填用，不弹提示）。
  @action
  Future<void> updateSubscriptionCover(String id, String coverUrl) async {
    final idx = subscriptions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final updated = subscriptions[idx].copyWith(coverUrl: coverUrl);
    subscriptions[idx] = updated;
    await _subscriptions.update(updated);
  }

  @action
  Future<void> removeSubscription(String id) async {
    await _subscriptions.remove(id);
    subscriptionFeeds.remove(id);
    subscriptionFeedErrors.remove(id);
  }

  @action
  Future<void> loadSubscriptionFeed(MagnetSubscription sub) async {
    try {
      final items = await _subscriptions.fetchLatest(sub);
      subscriptionFeeds[sub.id] = ObservableList.of(items);
      subscriptionFeedErrors.remove(sub.id);
    } catch (e) {
      // 拉取失败时记录错误态：展开区显示「加载失败 + 重试」而非永远转圈。
      subscriptionFeedErrors.add(sub.id);
      KazumiLogger().w(
          'MagnetController: load subscription feed failed for ${sub.name}',
          error: e);
    }
  }

  @action
  Future<void> checkSubscriptions() async {
    await _subscriptions.checkAll();
    KazumiDialog.showToast(message: '已检查所有订阅');
  }

  /// 切换订阅的自动下载开关。
  @action
  Future<void> setSubscriptionAutoDownload(String id, bool value) async {
    await _subscriptions.setAutoDownload(id, value);
  }

  /// 是否已存在与 [item] 同源资源的下载任务（按 info-hash 规范化比较，
  /// 忽略 tracker / 参数差异）。供剪贴板检测等入口在弹确认框前预判，
  /// 与 [addDownload] 的去重口径保持一致。
  bool isDownloadQueued(MagnetSearchItem item) =>
      _downloads.alreadyQueued(item);

  @action
  Future<void> addDownload(
    MagnetSearchItem item, {
    String? dir,
    MediaScrapeInfo? scrapeInfo,
  }) async {
    if (!engineEnabled) {
      KazumiDialog.showToast(message: '请先在设置中开启磁力下载引擎');
      return;
    }
    if (_downloads.alreadyQueued(item)) {
      KazumiDialog.showToast(message: '该资源已在下载队列中');
      return;
    }
    if (GStorage.getSetting(SettingsKeys.magnetDiskSpaceCheck)) {
      final proceed = await _checkDiskSpaceBeforeAdd(item, dir);
      if (!proceed) return;
    }
    final taskId = await _downloads.add(item, dir: dir, scrapeInfo: scrapeInfo);
    if (taskId.isEmpty) {
      KazumiDialog.showToast(message: '提交下载失败，请检查引擎状态');
      return;
    }
    KazumiDialog.showToast(message: '已添加到下载队列');
  }

  /// 提交下载前的磁盘空间检查：按资源体积估算所需空间，目标分区剩余不足时
  /// 弹出确认（用户可强制继续）。无法获取体积 / 分区信息时跳过检查。
  Future<bool> _checkDiskSpaceBeforeAdd(MagnetSearchItem item, String? dir) async {
    final neededBytes = _parseSizeBytes(item.size);
    if (neededBytes == null || neededBytes <= 0) return true;
    final targetDir = (dir ?? GStorage.getSetting(SettingsKeys.magnetDownloadDir))
        .toString()
        .trim();
    if (targetDir.isEmpty) return true;
    final freeBytes = await DiskSpace.availableBytes(targetDir);
    if (freeBytes == null) return true;
    if (freeBytes >= neededBytes) return true;
    final needLabel = _formatBytes(neededBytes);
    final freeLabel = _formatBytes(freeBytes);
    final confirm = await KazumiDialog.show<bool>(
      builder: (dialogContext) => AlertDialog(
        title: const Text('磁盘空间不足'),
        content: Text(
          '「${item.title.isEmpty ? '该任务' : item.title}」约需 $needLabel，'
          '目标分区仅剩 $freeLabel。\n\n'
          '继续添加可能因空间不足导致下载失败，是否仍要添加？',
        ),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => KazumiDialog.dismiss(popWith: true),
            child: const Text('仍然添加'),
          ),
        ],
      ),
    );
    return confirm ?? false;
  }

  /// 解析资源体积字符串（`1.2 GB` / `800MB` / `1.5 TiB` / `1,234 MB` 等），
  /// 失败返回 null。
  static int? _parseSizeBytes(String label) {
    if (label.trim().isEmpty) return null;
    final match = RegExp(
            r'([\d.,]+)\s*([KMGT]?i?B)', caseSensitive: false)
        .firstMatch(label.trim());
    if (match == null) return null;
    final raw = match.group(1)!.replaceAll(',', '');
    final value = double.tryParse(raw);
    if (value == null || value < 0) return null;
    final unit = match.group(2)!.toUpperCase().replaceAll('I', '');
    const mult = {'B': 1, 'KB': 1024, 'MB': 1048576, 'GB': 1073741824, 'TB': 1099511627776};
    final m = mult[unit];
    if (m == null) return null;
    return (value * m).round();
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[unit]}';
  }

  /// 任务进入终态（完成 / 错误）时发送系统通知（仅状态跳变时触发一次）。
  ///
  /// 启动首帧（init 推送全部持久化条目）只初始化状态快照，不发通知；
  /// 删除任务时清理对应的状态与防重入集合。
  void _notifyFinalStates(List<MagnetDownloadEntry> entries) {
    final ids = {for (final e in entries) e.taskId};
    _lastTaskStatuses.removeWhere((key, _) => !ids.contains(key));
    _scrapeSyncedTaskIds.removeWhere((key) => !ids.contains(key));
    _autoImportedTaskIds.removeWhere((key) => !ids.contains(key));
    _autoScrapingTaskIds.removeWhere((key) => !ids.contains(key));
    _scrapeKeyCache.removeWhere((key, _) => !ids.contains(key));
    _scrapeSyncFailures.removeWhere((key, _) => !ids.contains(key));
    for (final entry in entries) {
      final prev = _lastTaskStatuses[entry.taskId];
      _lastTaskStatuses[entry.taskId] = entry.status;
      if (!_initialSnapshotHandled) continue;
      if (prev == entry.status) continue;
      if (entry.status == 'complete' || entry.status == 'seeding') {
        _sessionFinalTaskIds.add(entry.taskId);
      }
      if (prev != 'complete' && entry.status == 'complete') {
        unawaited(AppNotifications.show(
          title: '下载完成',
          body: _entryDisplayName(entry),
        ));
      } else if (prev != 'error' && entry.status == 'error') {
        unawaited(AppNotifications.show(
          title: '下载失败',
          body: _entryDisplayName(entry),
        ));
      }
    }
    _initialSnapshotHandled = true;
  }

  /// 任务的展示名：优先番剧名，其次种子文件名 / 任务标题。
  String _entryDisplayName(MagnetDownloadEntry entry) {
    if (entry.scrapeInfo != null && entry.scrapeInfo!.displayName.isNotEmpty) {
      return entry.scrapeInfo!.displayName;
    }
    return entry.fileName.isNotEmpty ? entry.fileName : entry.title;
  }

  /// 文件完整落盘后同步刮削结果；只有停止做种进入 complete 后才自动入库。
  ///
  /// 这样把磁力下载目录加入本地媒体库后，无需手动搜刮即显示为已匹配番剧。
  /// 同步以媒体库扫描器的分组口径为键：多文件种子落在 `<savePath>/<种子名>/`
  /// 下（扫描器按子目录建文件夹，键即真实子目录）；单文件种子直接落在
  /// savePath，若该目录混有多部番剧，扫描器会按清洗后标题拆出逻辑分组
  /// 文件夹（`<savePath>/<清洗后标题>`），搜刮结果必须写在分组键上才能
  /// 命中。仅处理本会话内新完成的任务 + 已落盘的历史任务，
  /// 且不覆盖媒体库已有的匹配结果。
  ///
  /// 未携带番剧信息的任务（订阅自动下载 / 手动添加）在完成后按设置
  /// 自动搜刮：命中且置信度达标时走自动入库，未命中标记「待确认」。
  void _syncCompletedToLibrary(List<MagnetDownloadEntry> entries) {
    final media = _mediaController;
    if (media == null) return;
    for (final entry in entries) {
      if (entry.savePath.isEmpty) continue;
      if (_scrapeSyncedTaskIds.contains(entry.taskId)) continue;
      // 同步连续失败次数已达上限：本会话跳过，避免每 2s 一轮的
      // existsSync / 分组扫描重复浪费（重启后可重新触发）。
      if ((_scrapeSyncFailures[entry.taskId] ?? 0) >= _maxScrapeSyncFailures) {
        continue;
      }
      // 历史任务（本会话未进入终态）：已搜刮 / 已入库任务幂等同步到媒体库。
      // 不要求状态为 complete/seeding——文件已落盘但引擎状态尚未跳变
      // （queued / metadata 等）的任务也应尽早让媒体库显示匹配，避免
      // 「磁力页已搜刮、媒体库未匹配」的永久断层。
      if (!_sessionFinalTaskIds.contains(entry.taskId)) {
        if (entry.importedPath.isNotEmpty) {
          _syncScrapeInfo(entry, entry.importedPath);
        } else if (entry.scrapeInfo != null && _hasDownloadedFiles(entry)) {
          _syncScrapeInfo(entry, _scrapeKeyCachedFor(entry));
        }
        continue;
      }
      if (entry.status != 'complete' && entry.status != 'seeding') continue;
      if (entry.scrapeInfo == null) {
        _maybeAutoScrape(entry);
        continue;
      }
      if (entry.importedPath.isNotEmpty) {
        _autoImportedTaskIds.add(entry.taskId);
        _syncScrapeInfo(entry, entry.importedPath);
        continue;
      }
      final folderPath = _scrapeKeyForEntry(entry);
      if (folderPath.isEmpty) continue;
      // 自动入库需要同时满足：任务真正停止做种、用户开启开关、
      // 且搜刮置信度不低于阈值（详情页发起的任务置信度恒为 1.0）。
      // 边下边播在播的任务跳过入库：移动 / 重命名正被引擎流服务器
      // 读取的文件会让 HTTP 流断流；流停止后由下一轮状态同步重试
      // （此处不标记失败，避免永久跳过）。
      final shouldAutoImport = entry.status == 'complete' &&
          GStorage.getSetting(SettingsKeys.magnetAutoImportToLibrary) &&
          entry.scrapeConfidence >=
              GStorage.getSetting(SettingsKeys.magnetAutoImportConfidence) &&
          !_downloads.isStreaming(entry.taskId);
      if (!shouldAutoImport) _syncScrapeInfo(entry, folderPath);
      if (shouldAutoImport &&
          !_autoImportedTaskIds.contains(entry.taskId) &&
          !_autoImportFailedTaskIds.contains(entry.taskId) &&
          _autoImportingTaskIds.add(entry.taskId)) {
        unawaited(_runAutoImport(entry));
      }
    }
  }

  /// 未搜刮任务完成后按标题自动搜刮番剧信息（设置开关）。
  void _maybeAutoScrape(MagnetDownloadEntry entry) {
    if (entry.scrapeAttempted) return;
    if (!GStorage.getSetting(SettingsKeys.magnetAutoScrapeOnComplete)) return;
    if (!_autoScrapingTaskIds.add(entry.taskId)) return;
    unawaited(_runAutoScrape(entry));
  }

  /// 自动搜刮：把任务落盘文件构造成逻辑文件夹交给 MediaScraper。
  /// 命中后写入任务（触发下一次同步 / 入库），未命中标记「待确认」。
  Future<void> _runAutoScrape(MagnetDownloadEntry entry) async {
    try {
      final folder = _entryFolderForScrape(entry);
      if (folder == null) {
        // 无法确定落盘文件（旧数据无文件清单）：标记已尝试，否则
        // onChanged 每 2s 触发一次会无限重发 Bangumi 搜索请求。
        await _downloads.markScrapeAttempted(entry.taskId);
        return;
      }
      final result = await _scraper.scrapeFolder(folder: folder);
      if (result.status == ScrapeStatus.error) {
        // 网络 / 服务错误：不置 scrapeAttempted，留待下次状态同步重试，
        // 避免瞬时失败把任务永久标记为「待确认」。
        KazumiLogger().w(
            'MagnetController: auto scrape error for ${entry.fileName}');
        return;
      }
      if (result.status == ScrapeStatus.matched && result.info != null) {
        final info = result.info!;
        await _downloads.setScrapeInfo(
          entry.taskId,
          info,
          confidence: result.confidence,
        );
        KazumiDialog.showToast(
          message: '已自动识别「${info.displayName}」'
              '（置信度 ${(result.confidence * 100).round()}%）',
          duration: const Duration(seconds: 3),
        );
        return;
      }
      KazumiLogger().i(
          'MagnetController: auto scrape not matched for ${entry.fileName}');
      await _downloads.markScrapeAttempted(entry.taskId);
      KazumiDialog.showToast(
        message: '「${entry.title.isEmpty ? entry.fileName : entry.title}」'
            '未能自动识别番剧，可在下载页手动匹配',
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      KazumiLogger().w('MagnetController: auto scrape failed', error: e);
      // 异常（网络中断等）不置 scrapeAttempted，后续轮次自动重试。
    } finally {
      _autoScrapingTaskIds.remove(entry.taskId);
    }
  }

  /// 把任务的落盘文件构造成供搜刮使用的逻辑文件夹。
  ///
  /// 多文件种子取 `<savePath>/<种子名>` 目录名为标题来源；单文件种子
  /// 目录即下载根目录（basename 无意义），改用文件名作为标题来源。
  LocalMediaFolder? _entryFolderForScrape(MagnetDownloadEntry entry) {
    final dir = _actualDownloadDir(entry);
    if (dir.isEmpty) return null;
    final hasSubDir = !localMediaPathsEqual(dir, entry.savePath);
    final name = hasSubDir ? p.basename(dir) : entry.fileName;
    final selected = entry.selectedFileIndexes?.toSet();
    final files = <LocalMediaFile>[];
    for (final file in entry.files) {
      if (selected != null && !selected.contains(file.index)) continue;
      if (!isSupportedVideoFile(file.name)) continue;
      files.add(LocalMediaFile(
        path: entry.absolutePathFor(file) ?? '',
        name: file.name,
        size: file.size,
        modifiedAt: DateTime.now(),
      ));
    }
    if (files.isEmpty) return null;
    return LocalMediaFolder(path: dir, name: name, files: files);
  }

  void _syncScrapeInfo(MagnetDownloadEntry entry, String folderPath) {
    final media = _mediaController;
    if (media == null) return;
    if (media.getScrapeInfo(folderPath) != null) {
      _scrapeSyncedTaskIds.add(entry.taskId);
      _scrapeSyncFailures.remove(entry.taskId);
    } else if (!_scrapeSyncedTaskIds.contains(entry.taskId) &&
        (_scrapeSyncFailures[entry.taskId] ?? 0) < _maxScrapeSyncFailures &&
        _scrapeSyncingTaskIds.add(entry.taskId)) {
      unawaited(_runScrapeSync(entry, folderPath));
    }
  }

  /// 带缓存的 [_scrapeKeyForEntry]：按文件清单指纹命中直接复用，
  /// 避免每 2s 一轮的 onChanged 对未同步任务重复执行目录分组扫描。
  String _scrapeKeyCachedFor(MagnetDownloadEntry entry) {
    final fingerprint = Object.hash(
      entry.savePath,
      entry.fileName,
      entry.files.length,
      entry.selectedFileIndexes?.join(','),
    );
    final cached = _scrapeKeyCache[entry.taskId];
    if (cached != null && cached.$1 == fingerprint) return cached.$2;
    final key = _scrapeKeyForEntry(entry);
    _scrapeKeyCache[entry.taskId] = (fingerprint, key);
    return key;
  }

  Future<void> _runScrapeSync(
      MagnetDownloadEntry entry, String folderPath) async {
    try {
      await _mediaController?.applyScrapeInfo(folderPath, entry.scrapeInfo!);
      // 清理旧版本同步遗留的「真实目录键」死数据：目录被扫描器拆成
      // 逻辑分组后，真实目录键不再对应任何媒体库文件夹，删掉避免
      // 设置膨胀与后续误匹配。
      final rawDir = _actualDownloadDir(entry);
      if (rawDir.isNotEmpty && !localMediaPathsEqual(rawDir, folderPath)) {
        await _mediaController?.removeScrapeResult(rawDir);
      }
      _scrapeSyncedTaskIds.add(entry.taskId);
      _scrapeSyncFailures.remove(entry.taskId);
    } catch (e) {
      // 连续失败计数：超过上限后本会话不再重试（onChanged 每 2s
      // 触发一次，不计数会无限重试）。
      _scrapeSyncFailures[entry.taskId] =
          (_scrapeSyncFailures[entry.taskId] ?? 0) + 1;
      KazumiLogger().w('MagnetController: sync scrape info failed', error: e);
    } finally {
      _scrapeSyncingTaskIds.remove(entry.taskId);
    }
  }

  Future<void> _runAutoImport(MagnetDownloadEntry entry) async {
    try {
      if (await _autoImportToLibrary(entry)) {
        _autoImportedTaskIds.add(entry.taskId);
      } else {
        // 入库失败：本次会话内静默跳过（onChanged 每 2s 触发一次，
        // 不标记会无限重试），保留搜刮结果供媒体库展示。
        _autoImportFailedTaskIds.add(entry.taskId);
        _syncScrapeInfo(entry, _scrapeKeyForEntry(entry));
      }
    } finally {
      _autoImportingTaskIds.remove(entry.taskId);
    }
  }

  /// 任务文件的实际落盘目录：多文件种子在 `<savePath>/<种子名>` 下，
  /// 单文件种子直接落在 savePath。用引擎文件列表取第一个文件的目录。
  String _actualDownloadDir(MagnetDownloadEntry entry) {
    final selected = entry.selectedFileIndexes?.toSet();
    for (final file in entry.files) {
      if (selected != null && !selected.contains(file.index)) continue;
      final absolutePath = entry.absolutePathFor(file);
      if (absolutePath != null) return p.dirname(absolutePath);
    }
    if (entry.fileName.isNotEmpty) {
      final candidate = p.join(entry.savePath, entry.fileName);
      if (Directory(candidate).existsSync()) return p.normalize(candidate);
    }
    return p.normalize(entry.savePath);
  }

  /// 任务在媒体库中的搜刮键：与媒体库扫描器的标题分组口径一致。
  ///
  /// 单文件种子直接落在下载根目录且该目录混有多部番剧时，扫描器会把
  /// 目录拆成 `<目录>/<清洗后标题>` 的逻辑分组文件夹（磁盘上不存在），
  /// 搜刮结果必须写在分组键上才能在媒体库命中；目录内只有单一标题时
  /// 键即真实目录。用扫描器同款逻辑（`scanFoldersForDir`）求当前目录
  /// 会呈现的文件夹，再按文件路径归属匹配出本任务所在分组。
  ///
  /// 拿不到任务文件清单 / 目录不可读时回退真实落盘目录（与旧行为一致）。
  String _scrapeKeyForEntry(MagnetDownloadEntry entry) {
    final dir = _actualDownloadDir(entry);
    if (dir.isEmpty) return '';
    final entryKeys = <String>{};
    final selected = entry.selectedFileIndexes?.toSet();
    for (final file in entry.files) {
      if (selected != null && !selected.contains(file.index)) continue;
      final absolutePath = entry.absolutePathFor(file);
      if (absolutePath != null) entryKeys.add(localMediaPathKey(absolutePath));
    }
    if (entryKeys.isEmpty) return dir;
    final folders = _scanner.scanFoldersForDir(dir);
    for (final folder in folders) {
      for (final f in folder.files) {
        if (entryKeys.contains(localMediaPathKey(f.path))) return folder.path;
      }
    }
    return dir;
  }

  /// 任务是否有文件已实际落盘（供历史任务同步搜刮结果时判定）。
  ///
  /// 有文件清单时按清单逐个检查；无清单（旧数据）时回退检查
  /// 实际落盘目录是否存在。
  bool _hasDownloadedFiles(MagnetDownloadEntry entry) {
    final selected = entry.selectedFileIndexes?.toSet();
    var checkedAny = false;
    for (final file in entry.files) {
      if (selected != null && !selected.contains(file.index)) continue;
      checkedAny = true;
      final absolutePath = entry.absolutePathFor(file);
      if (absolutePath != null && File(absolutePath).existsSync()) return true;
    }
    if (!checkedAny) {
      final dir = _actualDownloadDir(entry);
      return dir.isNotEmpty && Directory(dir).existsSync();
    }
    return false;
  }

  /// 下载完成后自动入库（需在设置中开启且任务已搜刮）：
  /// 把所选文件移动到 `<目标根>/<番剧名>/`，尽量按 `第N话` 重命名，
  /// 然后把目标文件夹加入媒体库并触发重扫。
  Future<bool> _autoImportToLibrary(MagnetDownloadEntry entry) async {
    if (entry.status != 'complete') return false;
    if (!GStorage.getSetting(SettingsKeys.magnetAutoImportToLibrary)) {
      return false;
    }
    final info = entry.scrapeInfo;
    if (info == null) return false;
    final media = _mediaController;
    if (media == null) return false;
    if (Platform.isAndroid &&
        !await AndroidStorageAccess.hasMediaReadPermission()) {
      // 无读取权限时静默跳过（不弹窗）：自动入库发生在下载完成的后台
      // 时刻，弹权限窗没有 Activity 上下文；权限就绪后用户可重新触发。
      KazumiLogger().i(
          'MagnetController: auto import skipped (no media read permission)');
      return false;
    }
    final root = await _resolveAutoImportRoot(media);
    if (root == null) return false;

    final safeName = _safeFolderName(info.displayName);
    if (safeName.isEmpty) return false;
    final targetDirPath = p.join(root, safeName);
    try {
      final files = await _downloads.listFiles(entry.taskId);
      if (files.isEmpty) return false;
      final selected = entry.selectedFileIndexes?.toSet();
      final targetDir = Directory(targetDirPath);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      var movedCount = 0;
      for (final f in files) {
        if (selected != null && !selected.contains(f.index)) continue;
        if (!f.isStreamable) continue;
        final manifestFile = MagnetDownloadFile.fromFileInfo(f);
        final sourcePath = entry.absolutePathFor(manifestFile);
        if (sourcePath == null) continue;
        final src = File(sourcePath);
        if (!await src.exists()) continue;
        final ext = p.extension(f.name).toLowerCase();
        final ep = parseLocalEpisodeNumber(f.name);
        final baseName = ep > 0
            ? '第${ep.toString().padLeft(2, '0')}话'
            : p.basenameWithoutExtension(f.name);
        final dst = await _uniqueDestination(targetDirPath, baseName, ext,
            p.basenameWithoutExtension(f.name), sourcePath);
        try {
          await _moveVerified(src, dst);
          movedCount++;
        } catch (e) {
          KazumiLogger()
              .w('MagnetController: move file failed: ${src.path}', error: e);
        }
      }
      if (movedCount == 0) return false;
      // 目标目录加入媒体库并写入搜刮结果，然后重扫。
      if (!media.folders.any((folder) => localMediaPathsEqual(folder, root))) {
        await media.addFolder(root);
      } else {
        await media.scan();
      }
      final previousFolder = _scrapeKeyForEntry(entry);
      if (!localMediaPathsEqual(previousFolder, targetDirPath)) {
        await media.removeScrapeResult(previousFolder);
      }
      await media.applyScrapeInfo(targetDirPath, info);
      await _downloads.markImported(entry.taskId, targetDirPath);
      KazumiDialog.showToast(
        message: '「${info.displayName}」已自动入库（$movedCount 个文件）',
        duration: const Duration(seconds: 3),
      );
      return true;
    } catch (e) {
      KazumiLogger().w('MagnetController: auto import failed', error: e);
      return false;
    }
  }

  /// 同盘优先原子重命名；跨盘时复制到临时文件，校验长度后再替换并删源。
  static Future<void> _moveVerified(File source, File destination) async {
    if (localMediaPathsEqual(source.path, destination.path)) return;
    try {
      await source.rename(destination.path);
      return;
    } on FileSystemException {
      final temporary = File('${destination.path}.kazumi-importing');
      if (await temporary.exists()) await temporary.delete();
      try {
        await source.copy(temporary.path);
        final sourceLength = await source.length();
        if (await temporary.length() != sourceLength) {
          throw const FileSystemException('Copied file length mismatch');
        }
        await temporary.rename(destination.path);
        await source.delete();
      } catch (_) {
        if (await temporary.exists()) await temporary.delete();
        rethrow;
      }
    }
  }

  static Future<File> _uniqueDestination(String directory, String baseName,
      String extension, String original, String sourcePath) async {
    var candidate = File(p.join(directory, '$baseName$extension'));
    if (!await candidate.exists() ||
        localMediaPathsEqual(candidate.path, sourcePath)) {
      return candidate;
    }
    candidate = File(p.join(directory, '$baseName.$original$extension'));
    if (!await candidate.exists() ||
        localMediaPathsEqual(candidate.path, sourcePath)) {
      return candidate;
    }
    var suffix = 2;
    while (await candidate.exists()) {
      candidate =
          File(p.join(directory, '$baseName.$original-$suffix$extension'));
      suffix++;
    }
    return candidate;
  }

  /// 自动入库目标根目录：优先设置值，其次媒体库第一个文件夹。
  Future<String?> _resolveAutoImportRoot(MediaController media) async {
    final configured =
        GStorage.getSetting(SettingsKeys.magnetAutoImportRoot).trim();
    if (configured.isNotEmpty) return configured;
    if (media.folders.isNotEmpty) return media.folders.first;
    return null;
  }

  /// 清洗番剧名为可用的文件夹名。
  static String _safeFolderName(String name) {
    return name
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @action
  Future<void> pauseDownload(String taskId) async {
    final ok = await _downloads.pause(taskId);
    if (!ok) KazumiDialog.showToast(message: '暂停任务失败');
  }

  @action
  Future<void> resumeDownload(String taskId) async {
    final ok = await _downloads.unpause(taskId);
    if (!ok) KazumiDialog.showToast(message: '恢复任务失败');
  }

  /// 错误任务一键重试（重新提交源，保留磁盘数据）。
  @action
  Future<void> retryDownload(String taskId) async {
    final ok = await _downloads.retry(taskId);
    if (!ok) {
      KazumiDialog.showToast(message: '重试失败：请检查引擎状态与磁力链接');
    } else {
      KazumiDialog.showToast(message: '已重新提交下载');
    }
  }

  /// 清除全部已完成任务的记录（保留磁盘文件）。
  @action
  Future<int> clearCompletedDownloads() => _downloads.clearCompleted();

  /// 手动校验任务文件（force_recheck）。
  @action
  Future<bool> recheckDownload(String taskId) => _downloads.recheck(taskId);

  @action
  Future<void> removeDownload(String taskId, {bool deleteFiles = false}) async {
    final ok = await _downloads.remove(taskId, deleteFiles: deleteFiles);
    if (!ok) KazumiDialog.showToast(message: '删除任务失败');
  }

  @action
  Future<void> refreshDownloads() => _downloads.refresh();

  /// 搜索 Bangumi 番剧（供下载任务的「手动匹配番剧」对话框使用）。
  Future<List<BangumiItem>> searchBangumi(String keyword) async {
    if (keyword.trim().isEmpty) return const [];
    try {
      final page = await BangumiApi.bangumiSearch(keyword.trim(), limit: 20);
      return page?.items ?? const [];
    } catch (e) {
      KazumiLogger().w('MagnetController: searchBangumi failed', error: e);
      return const [];
    }
  }

  /// 手动把任务匹配到番剧（置信度 1.0），随后自动同步媒体库并视设置入库。
  @action
  Future<void> matchDownloadToBangumi(String taskId, BangumiItem item) async {
    final info = MediaScrapeInfo.fromBangumiItem(item);
    await _downloads.setScrapeInfo(taskId, info, confidence: 1.0);
    KazumiDialog.showToast(message: '已关联「${info.displayName}」');
  }

  /// 清除任务现有搜刮结果并重新按标题自动搜刮。
  @action
  Future<void> rescrapeDownload(String taskId) async {
    await _downloads.resetScrape(taskId);
  }

  /// 列出任务的种子文件（元数据就绪后才可用）。
  Future<List<FileInfo>> listDownloadFiles(String taskId) =>
      _downloads.listFiles(taskId);

  /// 启动边下边播：返回可交给播放器的 HTTP 流 URL，失败返回 null。
  /// 暂停 / 排队中的任务会先恢复下载。
  Future<String?> startStream(String taskId, int fileIndex) async {
    final entry = _downloads.entries
        .where((e) => e.taskId == taskId)
        .firstOrNull;
    if (entry == null) return null;
    if (entry.isPaused || entry.isQueued) {
      await _downloads.unpause(taskId);
    }
    return _downloads.startStream(taskId, fileIndex);
  }

  /// 停止任务的全部边下边播流（播放页退出时调用，释放流服务器资源）。
  void stopStreams(String taskId) => _downloads.stopStreamsForTask(taskId);

  /// 设置任务的文件选择（部分下载）。
  Future<bool> setDownloadFileSelection(
      String taskId, List<int> selected) async {
    final ok = await _downloads.setFileSelection(taskId, selected);
    if (!ok) KazumiDialog.showToast(message: '设置文件选择失败');
    return ok;
  }

  /// 引擎设置变化时调用，重新启动 / 停止引擎。
  @action
  Future<void> applyMagnetSettingsChanged() async {
    await _downloads.applySettingsChanged();
    await _subscriptions.applySettings();
    _refreshEngineInfo();
  }

  /// 测试引擎连接，返回 libtorrent 版本或 null。
  Future<String?> pingEngine() => _downloads.ping();
}
