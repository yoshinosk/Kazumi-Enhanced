// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'magnet_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$MagnetController on _MagnetController, Store {
  late final _$queryAtom =
      Atom(name: '_MagnetController.query', context: context);

  @override
  String get query {
    _$queryAtom.reportRead();
    return super.query;
  }

  @override
  set query(String value) {
    _$queryAtom.reportWrite(value, super.query, () {
      super.query = value;
    });
  }

  late final _$searchResultsAtom =
      Atom(name: '_MagnetController.searchResults', context: context);

  @override
  ObservableList<MagnetSearchItem> get searchResults {
    _$searchResultsAtom.reportRead();
    return super.searchResults;
  }

  @override
  set searchResults(ObservableList<MagnetSearchItem> value) {
    _$searchResultsAtom.reportWrite(value, super.searchResults, () {
      super.searchResults = value;
    });
  }

  late final _$isSearchingAtom =
      Atom(name: '_MagnetController.isSearching', context: context);

  @override
  bool get isSearching {
    _$isSearchingAtom.reportRead();
    return super.isSearching;
  }

  @override
  set isSearching(bool value) {
    _$isSearchingAtom.reportWrite(value, super.isSearching, () {
      super.isSearching = value;
    });
  }

  late final _$searchErrorAtom =
      Atom(name: '_MagnetController.searchError', context: context);

  @override
  String? get searchError {
    _$searchErrorAtom.reportRead();
    return super.searchError;
  }

  @override
  set searchError(String? value) {
    _$searchErrorAtom.reportWrite(value, super.searchError, () {
      super.searchError = value;
    });
  }

  late final _$hasMoreSearchResultsAtom =
      Atom(name: '_MagnetController.hasMoreSearchResults', context: context);

  @override
  bool get hasMoreSearchResults {
    _$hasMoreSearchResultsAtom.reportRead();
    return super.hasMoreSearchResults;
  }

  @override
  set hasMoreSearchResults(bool value) {
    _$hasMoreSearchResultsAtom.reportWrite(value, super.hasMoreSearchResults,
        () {
      super.hasMoreSearchResults = value;
    });
  }

  late final _$isLoadingMoreAtom =
      Atom(name: '_MagnetController.isLoadingMore', context: context);

  @override
  bool get isLoadingMore {
    _$isLoadingMoreAtom.reportRead();
    return super.isLoadingMore;
  }

  @override
  set isLoadingMore(bool value) {
    _$isLoadingMoreAtom.reportWrite(value, super.isLoadingMore, () {
      super.isLoadingMore = value;
    });
  }

  late final _$searchFansubAtom =
      Atom(name: '_MagnetController.searchFansub', context: context);

  @override
  String? get searchFansub {
    _$searchFansubAtom.reportRead();
    return super.searchFansub;
  }

  @override
  set searchFansub(String? value) {
    _$searchFansubAtom.reportWrite(value, super.searchFansub, () {
      super.searchFansub = value;
    });
  }

  late final _$subscriptionsAtom =
      Atom(name: '_MagnetController.subscriptions', context: context);

  @override
  ObservableList<MagnetSubscription> get subscriptions {
    _$subscriptionsAtom.reportRead();
    return super.subscriptions;
  }

  @override
  set subscriptions(ObservableList<MagnetSubscription> value) {
    _$subscriptionsAtom.reportWrite(value, super.subscriptions, () {
      super.subscriptions = value;
    });
  }

  late final _$downloadTasksAtom =
      Atom(name: '_MagnetController.downloadTasks', context: context);

  @override
  ObservableList<MagnetDownloadEntry> get downloadTasks {
    _$downloadTasksAtom.reportRead();
    return super.downloadTasks;
  }

  @override
  set downloadTasks(ObservableList<MagnetDownloadEntry> value) {
    _$downloadTasksAtom.reportWrite(value, super.downloadTasks, () {
      super.downloadTasks = value;
    });
  }

  late final _$subscriptionFeedsAtom =
      Atom(name: '_MagnetController.subscriptionFeeds', context: context);

  @override
  ObservableMap<String, ObservableList<MagnetSearchItem>>
      get subscriptionFeeds {
    _$subscriptionFeedsAtom.reportRead();
    return super.subscriptionFeeds;
  }

  @override
  set subscriptionFeeds(
      ObservableMap<String, ObservableList<MagnetSearchItem>> value) {
    _$subscriptionFeedsAtom.reportWrite(value, super.subscriptionFeeds, () {
      super.subscriptionFeeds = value;
    });
  }

  late final _$currentSourceIdAtom =
      Atom(name: '_MagnetController.currentSourceId', context: context);

  @override
  String get currentSourceId {
    _$currentSourceIdAtom.reportRead();
    return super.currentSourceId;
  }

  @override
  set currentSourceId(String value) {
    _$currentSourceIdAtom.reportWrite(value, super.currentSourceId, () {
      super.currentSourceId = value;
    });
  }

  late final _$engineStateAtom =
      Atom(name: '_MagnetController.engineState', context: context);

  @override
  LibtorrentEngineState get engineState {
    _$engineStateAtom.reportRead();
    return super.engineState;
  }

  @override
  set engineState(LibtorrentEngineState value) {
    _$engineStateAtom.reportWrite(value, super.engineState, () {
      super.engineState = value;
    });
  }

  late final _$engineErrorAtom =
      Atom(name: '_MagnetController.engineError', context: context);

  @override
  String? get engineError {
    _$engineErrorAtom.reportRead();
    return super.engineError;
  }

  @override
  set engineError(String? value) {
    _$engineErrorAtom.reportWrite(value, super.engineError, () {
      super.engineError = value;
    });
  }

  late final _$trackerCountAtom =
      Atom(name: '_MagnetController.trackerCount', context: context);

  @override
  int get trackerCount {
    _$trackerCountAtom.reportRead();
    return super.trackerCount;
  }

  @override
  set trackerCount(int value) {
    _$trackerCountAtom.reportWrite(value, super.trackerCount, () {
      super.trackerCount = value;
    });
  }

  late final _$trackerUpdatedAtAtom =
      Atom(name: '_MagnetController.trackerUpdatedAt', context: context);

  @override
  DateTime? get trackerUpdatedAt {
    _$trackerUpdatedAtAtom.reportRead();
    return super.trackerUpdatedAt;
  }

  @override
  set trackerUpdatedAt(DateTime? value) {
    _$trackerUpdatedAtAtom.reportWrite(value, super.trackerUpdatedAt, () {
      super.trackerUpdatedAt = value;
    });
  }

  late final _$trackerUpdatingAtom =
      Atom(name: '_MagnetController.trackerUpdating', context: context);

  @override
  bool get trackerUpdating {
    _$trackerUpdatingAtom.reportRead();
    return super.trackerUpdating;
  }

  @override
  set trackerUpdating(bool value) {
    _$trackerUpdatingAtom.reportWrite(value, super.trackerUpdating, () {
      super.trackerUpdating = value;
    });
  }

  late final _$setSearchSourceAsyncAction =
      AsyncAction('_MagnetController.setSearchSource', context: context);

  @override
  Future<void> setSearchSource(String sourceId) {
    return _$setSearchSourceAsyncAction
        .run(() => super.setSearchSource(sourceId));
  }

  late final _$pauseAllDownloadsAsyncAction =
      AsyncAction('_MagnetController.pauseAllDownloads', context: context);

  @override
  Future<void> pauseAllDownloads() {
    return _$pauseAllDownloadsAsyncAction.run(() => super.pauseAllDownloads());
  }

  late final _$startBuiltinEngineAsyncAction =
      AsyncAction('_MagnetController.startBuiltinEngine', context: context);

  @override
  Future<bool> startBuiltinEngine() {
    return _$startBuiltinEngineAsyncAction
        .run(() => super.startBuiltinEngine());
  }

  late final _$stopBuiltinEngineAsyncAction =
      AsyncAction('_MagnetController.stopBuiltinEngine', context: context);

  @override
  Future<void> stopBuiltinEngine() {
    return _$stopBuiltinEngineAsyncAction.run(() => super.stopBuiltinEngine());
  }

  late final _$updateTrackersAsyncAction =
      AsyncAction('_MagnetController.updateTrackers', context: context);

  @override
  Future<void> updateTrackers() {
    return _$updateTrackersAsyncAction.run(() => super.updateTrackers());
  }

  late final _$searchAsyncAction =
      AsyncAction('_MagnetController.search', context: context);

  @override
  Future<void> search(String keyword) {
    return _$searchAsyncAction.run(() => super.search(keyword));
  }

  late final _$loadMoreAsyncAction =
      AsyncAction('_MagnetController.loadMore', context: context);

  @override
  Future<void> loadMore() {
    return _$loadMoreAsyncAction.run(() => super.loadMore());
  }

  late final _$setSearchFansubAsyncAction =
      AsyncAction('_MagnetController.setSearchFansub', context: context);

  @override
  Future<void> setSearchFansub(String? fansub) {
    return _$setSearchFansubAsyncAction
        .run(() => super.setSearchFansub(fansub));
  }

  late final _$addSubscriptionAsyncAction =
      AsyncAction('_MagnetController.addSubscription', context: context);

  @override
  Future<void> addSubscription(MagnetSubscription subscription) {
    return _$addSubscriptionAsyncAction
        .run(() => super.addSubscription(subscription));
  }

  late final _$updateSubscriptionAsyncAction =
      AsyncAction('_MagnetController.updateSubscription', context: context);

  @override
  Future<void> updateSubscription(MagnetSubscription updated) {
    return _$updateSubscriptionAsyncAction
        .run(() => super.updateSubscription(updated));
  }

  late final _$updateSubscriptionCoverAsyncAction = AsyncAction(
      '_MagnetController.updateSubscriptionCover',
      context: context);

  @override
  Future<void> updateSubscriptionCover(String id, String coverUrl) {
    return _$updateSubscriptionCoverAsyncAction
        .run(() => super.updateSubscriptionCover(id, coverUrl));
  }

  late final _$removeSubscriptionAsyncAction =
      AsyncAction('_MagnetController.removeSubscription', context: context);

  @override
  Future<void> removeSubscription(String id) {
    return _$removeSubscriptionAsyncAction
        .run(() => super.removeSubscription(id));
  }

  late final _$loadSubscriptionFeedAsyncAction =
      AsyncAction('_MagnetController.loadSubscriptionFeed', context: context);

  @override
  Future<void> loadSubscriptionFeed(MagnetSubscription sub) {
    return _$loadSubscriptionFeedAsyncAction
        .run(() => super.loadSubscriptionFeed(sub));
  }

  late final _$checkSubscriptionsAsyncAction =
      AsyncAction('_MagnetController.checkSubscriptions', context: context);

  @override
  Future<void> checkSubscriptions() {
    return _$checkSubscriptionsAsyncAction
        .run(() => super.checkSubscriptions());
  }

  late final _$setSubscriptionAutoDownloadAsyncAction = AsyncAction(
      '_MagnetController.setSubscriptionAutoDownload',
      context: context);

  @override
  Future<void> setSubscriptionAutoDownload(String id, bool value) {
    return _$setSubscriptionAutoDownloadAsyncAction
        .run(() => super.setSubscriptionAutoDownload(id, value));
  }

  late final _$addDownloadAsyncAction =
      AsyncAction('_MagnetController.addDownload', context: context);

  @override
  Future<void> addDownload(MagnetSearchItem item,
      {String? dir, MediaScrapeInfo? scrapeInfo}) {
    return _$addDownloadAsyncAction
        .run(() => super.addDownload(item, dir: dir, scrapeInfo: scrapeInfo));
  }

  late final _$pauseDownloadAsyncAction =
      AsyncAction('_MagnetController.pauseDownload', context: context);

  @override
  Future<void> pauseDownload(String taskId) {
    return _$pauseDownloadAsyncAction.run(() => super.pauseDownload(taskId));
  }

  late final _$resumeDownloadAsyncAction =
      AsyncAction('_MagnetController.resumeDownload', context: context);

  @override
  Future<void> resumeDownload(String taskId) {
    return _$resumeDownloadAsyncAction.run(() => super.resumeDownload(taskId));
  }

  late final _$retryDownloadAsyncAction =
      AsyncAction('_MagnetController.retryDownload', context: context);

  @override
  Future<void> retryDownload(String taskId) {
    return _$retryDownloadAsyncAction.run(() => super.retryDownload(taskId));
  }

  late final _$removeDownloadAsyncAction =
      AsyncAction('_MagnetController.removeDownload', context: context);

  @override
  Future<void> removeDownload(String taskId, {bool deleteFiles = false}) {
    return _$removeDownloadAsyncAction
        .run(() => super.removeDownload(taskId, deleteFiles: deleteFiles));
  }

  late final _$matchDownloadToBangumiAsyncAction =
      AsyncAction('_MagnetController.matchDownloadToBangumi', context: context);

  @override
  Future<void> matchDownloadToBangumi(String taskId, BangumiItem item) {
    return _$matchDownloadToBangumiAsyncAction
        .run(() => super.matchDownloadToBangumi(taskId, item));
  }

  late final _$rescrapeDownloadAsyncAction =
      AsyncAction('_MagnetController.rescrapeDownload', context: context);

  @override
  Future<void> rescrapeDownload(String taskId) {
    return _$rescrapeDownloadAsyncAction
        .run(() => super.rescrapeDownload(taskId));
  }

  late final _$applyMagnetSettingsChangedAsyncAction = AsyncAction(
      '_MagnetController.applyMagnetSettingsChanged',
      context: context);

  @override
  Future<void> applyMagnetSettingsChanged() {
    return _$applyMagnetSettingsChangedAsyncAction
        .run(() => super.applyMagnetSettingsChanged());
  }

  late final _$_MagnetControllerActionController =
      ActionController(name: '_MagnetController', context: context);

  @override
  void setQuery(String value) {
    final _$actionInfo = _$_MagnetControllerActionController.startAction(
        name: '_MagnetController.setQuery');
    try {
      return super.setQuery(value);
    } finally {
      _$_MagnetControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  Future<void> refreshSearch() {
    final _$actionInfo = _$_MagnetControllerActionController.startAction(
        name: '_MagnetController.refreshSearch');
    try {
      return super.refreshSearch();
    } finally {
      _$_MagnetControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  Future<int> clearCompletedDownloads() {
    final _$actionInfo = _$_MagnetControllerActionController.startAction(
        name: '_MagnetController.clearCompletedDownloads');
    try {
      return super.clearCompletedDownloads();
    } finally {
      _$_MagnetControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  Future<bool> recheckDownload(String taskId) {
    final _$actionInfo = _$_MagnetControllerActionController.startAction(
        name: '_MagnetController.recheckDownload');
    try {
      return super.recheckDownload(taskId);
    } finally {
      _$_MagnetControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  Future<void> refreshDownloads() {
    final _$actionInfo = _$_MagnetControllerActionController.startAction(
        name: '_MagnetController.refreshDownloads');
    try {
      return super.refreshDownloads();
    } finally {
      _$_MagnetControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
query: ${query},
searchResults: ${searchResults},
isSearching: ${isSearching},
searchError: ${searchError},
hasMoreSearchResults: ${hasMoreSearchResults},
isLoadingMore: ${isLoadingMore},
searchFansub: ${searchFansub},
subscriptions: ${subscriptions},
downloadTasks: ${downloadTasks},
subscriptionFeeds: ${subscriptionFeeds},
currentSourceId: ${currentSourceId},
engineState: ${engineState},
engineError: ${engineError},
trackerCount: ${trackerCount},
trackerUpdatedAt: ${trackerUpdatedAt},
trackerUpdating: ${trackerUpdating}
    ''';
  }
}
