// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$MediaController on _MediaController, Store {
  late final _$foldersAtom =
      Atom(name: '_MediaController.folders', context: context);

  @override
  ObservableList<String> get folders {
    _$foldersAtom.reportRead();
    return super.folders;
  }

  @override
  set folders(ObservableList<String> value) {
    _$foldersAtom.reportWrite(value, super.folders, () {
      super.folders = value;
    });
  }

  late final _$libraryAtom =
      Atom(name: '_MediaController.library', context: context);

  @override
  ObservableList<LocalMediaFolder> get library {
    _$libraryAtom.reportRead();
    return super.library;
  }

  @override
  set library(ObservableList<LocalMediaFolder> value) {
    _$libraryAtom.reportWrite(value, super.library, () {
      super.library = value;
    });
  }

  late final _$isScanningAtom =
      Atom(name: '_MediaController.isScanning', context: context);

  @override
  bool get isScanning {
    _$isScanningAtom.reportRead();
    return super.isScanning;
  }

  @override
  set isScanning(bool value) {
    _$isScanningAtom.reportWrite(value, super.isScanning, () {
      super.isScanning = value;
    });
  }

  late final _$scrapeResultsAtom =
      Atom(name: '_MediaController.scrapeResults', context: context);

  @override
  ObservableMap<String, MediaScrapeInfo> get scrapeResults {
    _$scrapeResultsAtom.reportRead();
    return super.scrapeResults;
  }

  @override
  set scrapeResults(ObservableMap<String, MediaScrapeInfo> value) {
    _$scrapeResultsAtom.reportWrite(value, super.scrapeResults, () {
      super.scrapeResults = value;
    });
  }

  late final _$isScrapingAtom =
      Atom(name: '_MediaController.isScraping', context: context);

  @override
  bool get isScraping {
    _$isScrapingAtom.reportRead();
    return super.isScraping;
  }

  @override
  set isScraping(bool value) {
    _$isScrapingAtom.reportWrite(value, super.isScraping, () {
      super.isScraping = value;
    });
  }

  late final _$scrapeDoneAtom =
      Atom(name: '_MediaController.scrapeDone', context: context);

  @override
  int get scrapeDone {
    _$scrapeDoneAtom.reportRead();
    return super.scrapeDone;
  }

  @override
  set scrapeDone(int value) {
    _$scrapeDoneAtom.reportWrite(value, super.scrapeDone, () {
      super.scrapeDone = value;
    });
  }

  late final _$scrapeTotalAtom =
      Atom(name: '_MediaController.scrapeTotal', context: context);

  @override
  int get scrapeTotal {
    _$scrapeTotalAtom.reportRead();
    return super.scrapeTotal;
  }

  @override
  set scrapeTotal(int value) {
    _$scrapeTotalAtom.reportWrite(value, super.scrapeTotal, () {
      super.scrapeTotal = value;
    });
  }

  late final _$scrapeMatchedAtom =
      Atom(name: '_MediaController.scrapeMatched', context: context);

  @override
  int get scrapeMatched {
    _$scrapeMatchedAtom.reportRead();
    return super.scrapeMatched;
  }

  @override
  set scrapeMatched(int value) {
    _$scrapeMatchedAtom.reportWrite(value, super.scrapeMatched, () {
      super.scrapeMatched = value;
    });
  }

  late final _$scrapeFailedAtom =
      Atom(name: '_MediaController.scrapeFailed', context: context);

  @override
  int get scrapeFailed {
    _$scrapeFailedAtom.reportRead();
    return super.scrapeFailed;
  }

  @override
  set scrapeFailed(int value) {
    _$scrapeFailedAtom.reportWrite(value, super.scrapeFailed, () {
      super.scrapeFailed = value;
    });
  }

  late final _$scrapeCurrentNameAtom =
      Atom(name: '_MediaController.scrapeCurrentName', context: context);

  @override
  String get scrapeCurrentName {
    _$scrapeCurrentNameAtom.reportRead();
    return super.scrapeCurrentName;
  }

  @override
  set scrapeCurrentName(String value) {
    _$scrapeCurrentNameAtom.reportWrite(value, super.scrapeCurrentName, () {
      super.scrapeCurrentName = value;
    });
  }

  late final _$scrapeKeywordAtom =
      Atom(name: '_MediaController.scrapeKeyword', context: context);

  @override
  String get scrapeKeyword {
    _$scrapeKeywordAtom.reportRead();
    return super.scrapeKeyword;
  }

  @override
  set scrapeKeyword(String value) {
    _$scrapeKeywordAtom.reportWrite(value, super.scrapeKeyword, () {
      super.scrapeKeyword = value;
    });
  }

  late final _$addFolderAsyncAction =
      AsyncAction('_MediaController.addFolder', context: context);

  @override
  Future<void> addFolder(String path) {
    return _$addFolderAsyncAction.run(() => super.addFolder(path));
  }

  late final _$removeFolderAsyncAction =
      AsyncAction('_MediaController.removeFolder', context: context);

  @override
  Future<void> removeFolder(String path) {
    return _$removeFolderAsyncAction.run(() => super.removeFolder(path));
  }

  late final _$scanAsyncAction =
      AsyncAction('_MediaController.scan', context: context);

  @override
  Future<void> scan() {
    return _$scanAsyncAction.run(() => super.scan());
  }

  late final _$setGroupByFolderAsyncAction =
      AsyncAction('_MediaController.setGroupByFolder', context: context);

  @override
  Future<void> setGroupByFolder(bool value) {
    return _$setGroupByFolderAsyncAction
        .run(() => super.setGroupByFolder(value));
  }

  late final _$setViewModeAsyncAction =
      AsyncAction('_MediaController.setViewMode', context: context);

  @override
  Future<void> setViewMode(String mode) {
    return _$setViewModeAsyncAction.run(() => super.setViewMode(mode));
  }

  late final _$scrapeAllAsyncAction =
      AsyncAction('_MediaController.scrapeAll', context: context);

  @override
  Future<void> scrapeAll() {
    return _$scrapeAllAsyncAction.run(() => super.scrapeAll());
  }

  late final _$setFolderMatchAsyncAction =
      AsyncAction('_MediaController.setFolderMatch', context: context);

  @override
  Future<void> setFolderMatch(String folderPath, BangumiItem item) {
    return _$setFolderMatchAsyncAction
        .run(() => super.setFolderMatch(folderPath, item));
  }

  late final _$removeScrapeResultAsyncAction =
      AsyncAction('_MediaController.removeScrapeResult', context: context);

  @override
  Future<void> removeScrapeResult(String folderPath) {
    return _$removeScrapeResultAsyncAction
        .run(() => super.removeScrapeResult(folderPath));
  }

  late final _$deleteFileAsyncAction =
      AsyncAction('_MediaController.deleteFile', context: context);

  @override
  Future<void> deleteFile(LocalMediaFile file) {
    return _$deleteFileAsyncAction.run(() => super.deleteFile(file));
  }

  late final _$renameFileAsyncAction =
      AsyncAction('_MediaController.renameFile', context: context);

  @override
  Future<void> renameFile(LocalMediaFile file, String newName) {
    return _$renameFileAsyncAction.run(() => super.renameFile(file, newName));
  }

  late final _$moveFileAsyncAction =
      AsyncAction('_MediaController.moveFile', context: context);

  @override
  Future<void> moveFile(LocalMediaFile file, String destDir) {
    return _$moveFileAsyncAction.run(() => super.moveFile(file, destDir));
  }

  late final _$_MediaControllerActionController =
      ActionController(name: '_MediaController', context: context);

  @override
  void cancelScrape() {
    final _$actionInfo = _$_MediaControllerActionController.startAction(
        name: '_MediaController.cancelScrape');
    try {
      return super.cancelScrape();
    } finally {
      _$_MediaControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
folders: ${folders},
library: ${library},
isScanning: ${isScanning},
scrapeResults: ${scrapeResults},
isScraping: ${isScraping},
scrapeDone: ${scrapeDone},
scrapeTotal: ${scrapeTotal},
scrapeMatched: ${scrapeMatched},
scrapeFailed: ${scrapeFailed},
scrapeCurrentName: ${scrapeCurrentName},
scrapeKeyword: ${scrapeKeyword}
    ''';
  }
}
