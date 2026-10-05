// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'season_mark_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$SeasonMarkController on _SeasonMarkController, Store {
  late final _$subjectsAtom = Atom(
    name: '_SeasonMarkController.subjects',
    context: context,
  );

  @override
  ObservableList<BangumiItem> get subjects {
    _$subjectsAtom.reportRead();
    return super.subjects;
  }

  @override
  set subjects(ObservableList<BangumiItem> value) {
    _$subjectsAtom.reportWrite(value, super.subjects, () {
      super.subjects = value;
    });
  }

  late final _$collectTypesAtom = Atom(
    name: '_SeasonMarkController.collectTypes',
    context: context,
  );

  @override
  ObservableMap<int, int> get collectTypes {
    _$collectTypesAtom.reportRead();
    return super.collectTypes;
  }

  @override
  set collectTypes(ObservableMap<int, int> value) {
    _$collectTypesAtom.reportWrite(value, super.collectTypes, () {
      super.collectTypes = value;
    });
  }

  late final _$yearAtom = Atom(
    name: '_SeasonMarkController.year',
    context: context,
  );

  @override
  int get year {
    _$yearAtom.reportRead();
    return super.year;
  }

  @override
  set year(int value) {
    _$yearAtom.reportWrite(value, super.year, () {
      super.year = value;
    });
  }

  late final _$quarterMonthAtom = Atom(
    name: '_SeasonMarkController.quarterMonth',
    context: context,
  );

  @override
  int get quarterMonth {
    _$quarterMonthAtom.reportRead();
    return super.quarterMonth;
  }

  @override
  set quarterMonth(int value) {
    _$quarterMonthAtom.reportWrite(value, super.quarterMonth, () {
      super.quarterMonth = value;
    });
  }

  late final _$isLoadingAtom = Atom(
    name: '_SeasonMarkController.isLoading',
    context: context,
  );

  @override
  bool get isLoading {
    _$isLoadingAtom.reportRead();
    return super.isLoading;
  }

  @override
  set isLoading(bool value) {
    _$isLoadingAtom.reportWrite(value, super.isLoading, () {
      super.isLoading = value;
    });
  }

  late final _$isLoadingMoreAtom = Atom(
    name: '_SeasonMarkController.isLoadingMore',
    context: context,
  );

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

  late final _$isErrorAtom = Atom(
    name: '_SeasonMarkController.isError',
    context: context,
  );

  @override
  bool get isError {
    _$isErrorAtom.reportRead();
    return super.isError;
  }

  @override
  set isError(bool value) {
    _$isErrorAtom.reportWrite(value, super.isError, () {
      super.isError = value;
    });
  }

  late final _$hasReachedEndAtom = Atom(
    name: '_SeasonMarkController.hasReachedEnd',
    context: context,
  );

  @override
  bool get hasReachedEnd {
    _$hasReachedEndAtom.reportRead();
    return super.hasReachedEnd;
  }

  @override
  set hasReachedEnd(bool value) {
    _$hasReachedEndAtom.reportWrite(value, super.hasReachedEnd, () {
      super.hasReachedEnd = value;
    });
  }

  late final _$initAsyncAction = AsyncAction(
    '_SeasonMarkController.init',
    context: context,
  );

  @override
  Future<void> init({int? year, int? quarterMonth}) {
    return _$initAsyncAction.run(
      () => super.init(year: year, quarterMonth: quarterMonth),
    );
  }

  late final _$setSeasonAsyncAction = AsyncAction(
    '_SeasonMarkController.setSeason',
    context: context,
  );

  @override
  Future<void> setSeason(int newYear, int newQuarterMonth) {
    return _$setSeasonAsyncAction.run(
      () => super.setSeason(newYear, newQuarterMonth),
    );
  }

  late final _$refreshAsyncAction = AsyncAction(
    '_SeasonMarkController.refresh',
    context: context,
  );

  @override
  Future<void> refresh() {
    return _$refreshAsyncAction.run(() => super.refresh());
  }

  late final _$loadMoreAsyncAction = AsyncAction(
    '_SeasonMarkController.loadMore',
    context: context,
  );

  @override
  Future<void> loadMore() {
    return _$loadMoreAsyncAction.run(() => super.loadMore());
  }

  late final _$markSubjectAsyncAction = AsyncAction(
    '_SeasonMarkController.markSubject',
    context: context,
  );

  @override
  Future<void> markSubject(BangumiItem item, int type) {
    return _$markSubjectAsyncAction.run(() => super.markSubject(item, type));
  }

  late final _$markSubjectsAsyncAction = AsyncAction(
    '_SeasonMarkController.markSubjects',
    context: context,
  );

  @override
  Future<void> markSubjects(List<BangumiItem> items, int type) {
    return _$markSubjectsAsyncAction.run(() => super.markSubjects(items, type));
  }

  late final _$_SeasonMarkControllerActionController = ActionController(
    name: '_SeasonMarkController',
    context: context,
  );

  @override
  void refreshCollectTypes() {
    final _$actionInfo = _$_SeasonMarkControllerActionController.startAction(
      name: '_SeasonMarkController.refreshCollectTypes',
    );
    try {
      return super.refreshCollectTypes();
    } finally {
      _$_SeasonMarkControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
subjects: ${subjects},
collectTypes: ${collectTypes},
year: ${year},
quarterMonth: ${quarterMonth},
isLoading: ${isLoading},
isLoadingMore: ${isLoadingMore},
isError: ${isError},
hasReachedEnd: ${hasReachedEnd}
    ''';
  }
}
