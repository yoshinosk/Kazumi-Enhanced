import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:mobx/mobx.dart';

part 'season_mark_controller.g.dart';

class SeasonMarkController = _SeasonMarkController with _$SeasonMarkController;

abstract class _SeasonMarkController with Store {
  _SeasonMarkController(this._collectController);

  final CollectController _collectController;

  static const int _pageSize = 50;

  @observable
  ObservableList<BangumiItem> subjects = ObservableList<BangumiItem>();

  /// 当前已加载条目的收藏状态（id → CollectType.value）
  @observable
  ObservableMap<int, int> collectTypes = ObservableMap<int, int>();

  @observable
  int year = DateTime.now().year;

  /// 季度起始月：1 / 4 / 7 / 10
  @observable
  int quarterMonth = _currentQuarterMonth();

  @observable
  bool isLoading = false;

  @observable
  bool isLoadingMore = false;

  @observable
  bool isError = false;

  @observable
  bool hasReachedEnd = false;

  int _offset = 0;

  /// 进入页面时应用初始年份 / 季度并加载。
  /// 参数为 null 时保持默认（当前季度）。
  @action
  Future<void> init({int? year, int? quarterMonth}) async {
    if (year != null) this.year = year;
    if (quarterMonth != null) this.quarterMonth = quarterMonth;
    await refresh();
  }

  @action
  Future<void> setSeason(int newYear, int newQuarterMonth) async {
    if (newYear == year && newQuarterMonth == quarterMonth) return;
    year = newYear;
    quarterMonth = newQuarterMonth;
    await refresh();
  }

  @action
  Future<void> refresh() async {
    _offset = 0;
    isError = false;
    hasReachedEnd = false;
    subjects.clear();
    isLoading = true;
    try {
      final page = await BangumiApi.getSubjectsBySeason(
        year: year,
        month: quarterMonth,
        limit: _pageSize,
        offset: 0,
      );
      subjects.addAll(page.items);
      _offset = page.items.length;
      if (page.items.isEmpty || _offset >= page.total) {
        hasReachedEnd = true;
      }
    } catch (e) {
      isError = true;
    } finally {
      isLoading = false;
    }
    refreshCollectTypes();
  }

  @action
  Future<void> loadMore() async {
    if (isLoading || isLoadingMore || hasReachedEnd || isError) return;
    isLoadingMore = true;
    try {
      final page = await BangumiApi.getSubjectsBySeason(
        year: year,
        month: quarterMonth,
        limit: _pageSize,
        offset: _offset,
      );
      final knownIds = subjects.map((item) => item.id).toSet();
      for (final item in page.items) {
        if (knownIds.add(item.id)) {
          subjects.add(item);
        }
      }
      _offset += page.items.length;
      if (page.items.isEmpty || _offset >= page.total) {
        hasReachedEnd = true;
      }
    } catch (e) {
      KazumiDialog.showToast(message: '加载更多失败，请稍后重试');
      // 停止继续触发，避免滚动时反复失败
      hasReachedEnd = true;
    } finally {
      isLoadingMore = false;
    }
    refreshCollectTypes();
  }

  int collectTypeOf(int bangumiId) => collectTypes[bangumiId] ?? 0;

  /// 单条打标；type == 0 表示取消收藏（走带确认的删除引导流程）
  @action
  Future<void> markSubject(BangumiItem item, int type) async {
    if (type == 0) {
      await _collectController.deleteCollect(item);
    } else {
      final summary = await _collectController.bulkSetCollect([item], type);
      if (summary.failed > 0) {
        KazumiDialog.showToast(message: '标记失败，请稍后重试');
      }
    }
    refreshCollectTypes();
  }

  @action
  Future<void> markSubjects(List<BangumiItem> items, int type) async {
    final summary = await _collectController.bulkSetCollect(items, type);
    KazumiDialog.showToast(
      message: '已标记 ${summary.imported + summary.updated} 条'
          '${summary.skipped > 0 ? '，${summary.skipped} 条无变化' : ''}'
          '${summary.failed > 0 ? '，失败 ${summary.failed} 条' : ''}',
    );
    refreshCollectTypes();
  }

  @action
  void refreshCollectTypes() {
    collectTypes.clear();
    for (final item in subjects) {
      collectTypes[item.id] = _collectController.getCollectType(item);
    }
  }
}

int _currentQuarterMonth() => switch (DateTime.now().month) {
      12 || 1 || 2 => 1,
      3 || 4 || 5 => 4,
      6 || 7 || 8 => 7,
      _ => 10,
    };
