// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stats_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$StatsController on _StatsController, Store {
  late final _$collectiblesAtom = Atom(
    name: '_StatsController.collectibles',
    context: context,
  );

  @override
  ObservableList<CollectedBangumi> get collectibles {
    _$collectiblesAtom.reportRead();
    return super.collectibles;
  }

  @override
  set collectibles(ObservableList<CollectedBangumi> value) {
    _$collectiblesAtom.reportWrite(value, super.collectibles, () {
      super.collectibles = value;
    });
  }

  late final _$undatedCountAtom = Atom(
    name: '_StatsController.undatedCount',
    context: context,
  );

  @override
  int get undatedCount {
    _$undatedCountAtom.reportRead();
    return super.undatedCount;
  }

  @override
  set undatedCount(int value) {
    _$undatedCountAtom.reportWrite(value, super.undatedCount, () {
      super.undatedCount = value;
    });
  }

  late final _$selectingAtom = Atom(
    name: '_StatsController.selecting',
    context: context,
  );

  @override
  bool get selecting {
    _$selectingAtom.reportRead();
    return super.selecting;
  }

  @override
  set selecting(bool value) {
    _$selectingAtom.reportWrite(value, super.selecting, () {
      super.selecting = value;
    });
  }

  late final _$selectedIdsAtom = Atom(
    name: '_StatsController.selectedIds',
    context: context,
  );

  @override
  ObservableSet<int> get selectedIds {
    _$selectedIdsAtom.reportRead();
    return super.selectedIds;
  }

  @override
  set selectedIds(ObservableSet<int> value) {
    _$selectedIdsAtom.reportWrite(value, super.selectedIds, () {
      super.selectedIds = value;
    });
  }

  late final _$statusFilterAtom = Atom(
    name: '_StatsController.statusFilter',
    context: context,
  );

  @override
  int get statusFilter {
    _$statusFilterAtom.reportRead();
    return super.statusFilter;
  }

  @override
  set statusFilter(int value) {
    _$statusFilterAtom.reportWrite(value, super.statusFilter, () {
      super.statusFilter = value;
    });
  }

  late final _$sortOrderAtom = Atom(
    name: '_StatsController.sortOrder',
    context: context,
  );

  @override
  StatsSortOrder get sortOrder {
    _$sortOrderAtom.reportRead();
    return super.sortOrder;
  }

  @override
  set sortOrder(StatsSortOrder value) {
    _$sortOrderAtom.reportWrite(value, super.sortOrder, () {
      super.sortOrder = value;
    });
  }

  late final _$_StatsControllerActionController = ActionController(
    name: '_StatsController',
    context: context,
  );

  @override
  void load() {
    final _$actionInfo = _$_StatsControllerActionController.startAction(
      name: '_StatsController.load',
    );
    try {
      return super.load();
    } finally {
      _$_StatsControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void enterSelection() {
    final _$actionInfo = _$_StatsControllerActionController.startAction(
      name: '_StatsController.enterSelection',
    );
    try {
      return super.enterSelection();
    } finally {
      _$_StatsControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void leaveSelection() {
    final _$actionInfo = _$_StatsControllerActionController.startAction(
      name: '_StatsController.leaveSelection',
    );
    try {
      return super.leaveSelection();
    } finally {
      _$_StatsControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void toggleSelect(int id) {
    final _$actionInfo = _$_StatsControllerActionController.startAction(
      name: '_StatsController.toggleSelect',
    );
    try {
      return super.toggleSelect(id);
    } finally {
      _$_StatsControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void toggleSelectAll(List<CollectedBangumi> visibleEntries) {
    final _$actionInfo = _$_StatsControllerActionController.startAction(
      name: '_StatsController.toggleSelectAll',
    );
    try {
      return super.toggleSelectAll(visibleEntries);
    } finally {
      _$_StatsControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setStatusFilter(int value) {
    final _$actionInfo = _$_StatsControllerActionController.startAction(
      name: '_StatsController.setStatusFilter',
    );
    try {
      return super.setStatusFilter(value);
    } finally {
      _$_StatsControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setSortOrder(StatsSortOrder order) {
    final _$actionInfo = _$_StatsControllerActionController.startAction(
      name: '_StatsController.setSortOrder',
    );
    try {
      return super.setSortOrder(order);
    } finally {
      _$_StatsControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
collectibles: ${collectibles},
undatedCount: ${undatedCount},
selecting: ${selecting},
selectedIds: ${selectedIds},
statusFilter: ${statusFilter},
sortOrder: ${sortOrder}
    ''';
  }
}
