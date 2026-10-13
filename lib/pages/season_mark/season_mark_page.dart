import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/bangumi_card_grid.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/season_mark/season_mark_controller.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/surface_theme.dart';

part 'season_mark_card.dart';

/// 季度补标：按年份 + 季度浏览 bgm.tv 动画并打收藏标记。
class SeasonMarkPage extends StatefulWidget {
  const SeasonMarkPage({
    super.key,
    required this.controller,
    this.initialYear,
    this.initialQuarterMonth,
  });

  final SeasonMarkController controller;

  /// 从统计页跳转时携带的目标年份 / 季度
  final int? initialYear;
  final int? initialQuarterMonth;

  @override
  State<SeasonMarkPage> createState() => _SeasonMarkPageState();
}

class _SeasonMarkPageState extends State<SeasonMarkPage> {
  final ScrollController _scrollController = ScrollController();
  bool _selecting = false;
  final Set<int> _selectedIds = {};

  /// 卡片视图大小（大 / 中 / 小），与追番统计页共用同一份设置。
  BangumiCardViewSize _viewSize = BangumiCardViewSize.large;

  SeasonMarkController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _viewSize = BangumiCardViewSize.fromName(
      GStorage.getSetting(SettingsKeys.bangumiCardViewSize),
    );
    unawaited(controller.init(
      year: widget.initialYear,
      quarterMonth: widget.initialQuarterMonth,
    ));
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scrollController.position;
    if (position.extentAfter < 300) {
      unawaited(controller.loadMore());
    }
  }

  void _enterSelection() {
    if (_selecting) return;
    setState(() => _selecting = true);
  }

  void _leaveSelection() {
    if (!_selecting) return;
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(int id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  void _toggleSelectAll() {
    setState(() {
      final allSelected = controller.subjects
          .every((item) => _selectedIds.contains(item.id));
      if (allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(
            controller.subjects.map((item) => item.id));
      }
    });
  }

  void _changeViewSize(BangumiCardViewSize size) {
    if (size == _viewSize) return;
    setState(() => _viewSize = size);
    unawaited(GStorage.putSetting(SettingsKeys.bangumiCardViewSize, size.name));
  }

  void _bulkMark(CollectType type) {
    final items = controller.subjects
        .where((item) => _selectedIds.contains(item.id))
        .toList();
    _leaveSelection();
    if (items.isEmpty) return;
    unawaited(controller.markSubjects(items, type.value));
  }

  /// 切季：多选中的条目已不属于新列表，先清空勾选再加载。
  void _setSeason(int year, int quarterMonth) {
    if (_selecting) {
      setState(() => _selectedIds.clear());
    }
    unawaited(controller.setSeason(year, quarterMonth));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leaveSelection();
      },
      child: Scaffold(
        appBar: _selecting ? _selectionAppBar() : _normalAppBar(),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              Observer(builder: (_) => _quarterSelector(context)),
              Expanded(child: Observer(builder: _buildContent)),
            ],
          ),
        ),
        bottomNavigationBar: _selecting ? _selectionBar(context) : null,
      ),
    );
  }

  SysAppBar _normalAppBar() {
    return SysAppBar(
      title: Observer(
        builder: (context) => KazumiMenuButton(
          builder: (context, toggle) => TextButton.icon(
            onPressed: toggle,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.expand_more_rounded, size: 20),
            label: Text(
              '${controller.year} 年',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          menuChildren: [
            for (final year in _yearOptions(controller.year))
              KazumiMenuItem(
                label: '$year 年',
                selected: year == controller.year,
                onPressed: () => _setSeason(year, controller.quarterMonth),
              ),
          ],
        ),
      ),
      actions: [
        BangumiCardViewSizeMenu(value: _viewSize, onChanged: _changeViewSize),
        IconButton(
          tooltip: '多选打标',
          icon: const Icon(Icons.checklist_rounded),
          onPressed: _enterSelection,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  SysAppBar _selectionAppBar() {
    return SysAppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: '退出多选',
        onPressed: _leaveSelection,
      ),
      title: Text('已选 ${_selectedIds.length} 项'),
      actions: [
        TextButton(
          onPressed: _toggleSelectAll,
          child: Observer(builder: (context) {
            final allSelected = controller.subjects.isNotEmpty &&
                controller.subjects
                    .every((item) => _selectedIds.contains(item.id));
            return Text(allSelected ? '取消全选' : '全选');
          }),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _quarterSelector(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          selected: {controller.quarterMonth},
          onSelectionChanged: (selection) =>
              _setSeason(controller.year, selection.first),
          segments: [
            for (final month in const [1, 4, 7, 10])
              ButtonSegment(
                value: month,
                label: Text('$month 月'),
                enabled: !_isFutureSeason(controller.year, month),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (controller.isLoading && controller.subjects.isEmpty) {
      return const Center(child: LoadingIndicator());
    }
    if (controller.isError && controller.subjects.isEmpty) {
      return BangumiMirrorErrorWidget(
        onRetry: () => unawaited(controller.refresh()),
      );
    }
    if (controller.subjects.isEmpty) {
      return const GeneralEmptyState(
        icon: Icons.event_busy_rounded,
        title: '该季度没有找到动画条目',
      );
    }
    // 收藏状态必须在 build 阶段读取（Observer 才能跟踪）；SliverLayoutBuilder
    // 的 builder 在 layout 阶段执行，在那里读 Observable 不会触发重建。
    final entries = [
      for (final item in controller.subjects)
        (item, controller.collectTypeOf(item.id)),
    ];
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          sliver: _grid(context, entries),
        ),
        if (controller.isLoadingMore)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            ),
          )
        else if (controller.hasReachedEnd)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  '没有更多了',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _grid(BuildContext context, List<(BangumiItem, int)> entries) {
    // 必须用 SliverLayoutBuilder：本方法返回 Sliver，普通 LayoutBuilder
    // 出现在 sliver 位置会在构建时抛异常（表现为整页白屏）。
    return SliverLayoutBuilder(builder: (context, constraints) {
      final contentWidth = constraints.crossAxisExtent;
      final portrait =
          MediaQuery.orientationOf(context) == Orientation.portrait;
      final layout = BangumiCardGridLayout.compute(
        contentWidth: contentWidth,
        portrait: portrait,
        scaler: MediaQuery.textScalerOf(context),
        size: _viewSize,
      );
      return SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: layout.columns,
          crossAxisSpacing: layout.spacing,
          mainAxisSpacing: layout.mainAxisSpacing,
          mainAxisExtent: layout.cardExtent,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final (item, collectType) = entries[index];
          return _MarkCard(
            key: ValueKey('mark-${item.id}'),
            item: item,
            collectType: collectType,
            viewSize: _viewSize,
            selecting: _selecting,
            selected: _selectedIds.contains(item.id),
            onTap: () => _toggleSelect(item.id),
            onLongPress: _enterSelection,
            onMark: (type) => unawaited(controller.markSubject(item, type)),
            onOpenDetails: () => context.pushNamed('/info/', arguments: item),
          );
        },
      );
    });
  }

  Widget _selectionBar(BuildContext context) {
    return BottomAppBar(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '已选 ${_selectedIds.length} 项',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          KazumiMenuButton(
            builder: (context, toggle) => FilledButton.tonalIcon(
              onPressed: _selectedIds.isEmpty ? null : toggle,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.expand_more_rounded, size: 18),
              label: const Text('标记为…'),
            ),
            menuChildren: [
              for (final type
                  in CollectType.values.where((type) => type.isCollected))
                KazumiMenuItem(
                  label: type.label,
                  onPressed: () => _bulkMark(type),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static List<int> _yearOptions(int selectedYear) {
    final currentYear = DateTime.now().year;
    final years = [for (var year = currentYear + 1; year >= 2002; year--) year];
    // 从统计页可能带入超出常规范围的年份，兜底保证当前年份在菜单中。
    if (!years.contains(selectedYear)) {
      years
        ..add(selectedYear)
        ..sort((a, b) => b.compareTo(a));
    }
    return years;
  }

  static bool _isFutureSeason(int year, int quarterMonth) =>
      DateTime(year, quarterMonth, 1).isAfter(DateTime.now());
}
