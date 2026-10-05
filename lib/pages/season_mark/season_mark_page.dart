import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/season_mark/season_mark_controller.dart';
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

  SeasonMarkController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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

  void _bulkMark(CollectType type) {
    final items = controller.subjects
        .where((item) => _selectedIds.contains(item.id))
        .toList();
    _leaveSelection();
    if (items.isEmpty) return;
    unawaited(controller.markSubjects(items, type.value));
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
            for (final year in _yearOptions())
              KazumiMenuItem(
                label: '$year 年',
                selected: year == controller.year,
                onPressed: () =>
                    unawaited(controller.setSeason(year, controller.quarterMonth)),
              ),
          ],
        ),
      ),
      actions: [
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
          onSelectionChanged: (selection) => unawaited(
              controller.setSeason(controller.year, selection.first)),
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
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          sliver: _grid(context),
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

  Widget _grid(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final contentWidth = constraints.maxWidth;
      final portrait =
          MediaQuery.orientationOf(context) == Orientation.portrait;
      final spacing = portrait ? (contentWidth < 600 ? 8.0 : 12.0) : 16.0;
      final scaler = MediaQuery.textScalerOf(context);
      final textScale = (scaler.scale(14) / 14).clamp(1.0, double.infinity);
      final minWidth =
          (contentWidth < 600 ? 136.0 : 172.0) + 32 * (textScale - 1);
      final columns = portrait
          ? 3
          : ((contentWidth + spacing) / (minWidth + spacing)).floor().clamp(1, 6);
      final width = (contentWidth - spacing * (columns - 1)) / columns;
      return SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: portrait ? 12 : spacing,
          mainAxisExtent: _MarkCard.extent(width, scaler),
        ),
        itemCount: controller.subjects.length,
        itemBuilder: (context, index) {
          final item = controller.subjects[index];
          return _MarkCard(
            key: ValueKey('mark-${item.id}'),
            item: item,
            collectType: controller.collectTypeOf(item.id),
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

  static List<int> _yearOptions() {
    final currentYear = DateTime.now().year;
    return [for (var year = currentYear + 1; year >= 2002; year--) year];
  }

  static bool _isFutureSeason(int year, int quarterMonth) =>
      DateTime(year, quarterMonth, 1).isAfter(DateTime.now());
}
