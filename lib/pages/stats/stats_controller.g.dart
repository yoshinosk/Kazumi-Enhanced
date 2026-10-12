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
  String toString() {
    return '''
collectibles: ${collectibles},
undatedCount: ${undatedCount}
    ''';
  }
}
