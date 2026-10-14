import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/bangumi_card_grid.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/collect/collect_library_query.dart';
import 'package:kazumi/pages/stats/stats_controller.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/surface_theme.dart';
import 'package:fl_chart/fl_chart.dart';

part 'stats_group_list.dart';
part 'stats_charts.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({
    super.key,
    required this.controller,
  });

  final StatsController controller;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  StatsController get controller => widget.controller;

  /// 季度列表的卡片视图大小（大 / 中 / 小），与补标页共用同一份设置。
  BangumiCardViewSize _viewSize = BangumiCardViewSize.large;

  @override
  void initState() {
    super.initState();
    _viewSize = BangumiCardViewSize.fromName(
      GStorage.getSetting(SettingsKeys.bangumiCardViewSize),
    );
    widget.controller.load();
    widget.controller.startListening();
  }

  @override
  void dispose() {
    widget.controller.stopListening();
    _tabController.dispose();
    super.dispose();
  }

  void _bulkMark(CollectType type) {
    final items = controller.selectedItems();
    controller.leaveSelection();
    if (items.isEmpty) return;
    unawaited(controller.bulkMark(items, type).then((summary) {
      KazumiDialog.showToast(
        message: '已标记 ${summary.imported + summary.updated} 部'
            '${summary.skipped > 0 ? '，${summary.skipped} 部无变化' : ''}'
            '${summary.failed > 0 ? '，失败 ${summary.failed} 部' : ''}',
      );
    }));
  }

  void _confirmBulkDelete() {
    final items = controller.selectedItems();
    if (items.isEmpty) return;
    KazumiDialog.show(
      builder: (context) => AlertDialog(
        title: const Text('批量删除收藏'),
        content: Text('确定要删除 ${items.length} 部番剧的收藏记录吗？'),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              KazumiDialog.dismiss();
              unawaited(_bulkDelete(items));
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _bulkDelete(List<BangumiItem> items) async {
    final result = await controller.bulkDelete(items);
    KazumiDialog.showToast(
      message: '已删除 ${result.deleted} 部'
          '${result.failed > 0 ? '，失败 ${result.failed} 部' : ''}',
    );
    controller.leaveSelection();
  }

  void _changeViewSize(BangumiCardViewSize size) {
    if (size == _viewSize) return;
    setState(() => _viewSize = size);
    unawaited(GStorage.putSetting(SettingsKeys.bangumiCardViewSize, size.name));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Observer(
      builder: (context) {
        final selecting = controller.selecting;
        return PopScope(
          canPop: !selecting,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) controller.leaveSelection();
          },
          child: Scaffold(
            appBar:
                selecting ? _selectionAppBar(theme) : _normalAppBar(theme),
            body: SafeArea(
              top: false,
              bottom: false,
              child: Observer(
                builder: (context) {
                  if (controller.collectibles.isEmpty) {
                    return const GeneralEmptyState(
                      icon: Icons.query_stats_rounded,
                      title: '还没有收藏的番剧，先去添加一些吧',
                    );
                  }
                  final entries = controller.filteredEntries();
                  final groups = groupByAirDate(
                    entries,
                    sortOrder: controller.sortOrder,
                  );
                  return TabBarView(
                    controller: _tabController,
                    physics: selecting
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    children: [
                      StatsGroupList(
                        entries: entries,
                        groups: groups,
                        undatedCount: controller.undatedCount,
                        controller: controller,
                        viewSize: _viewSize,
                        onOpen: (item) =>
                            context.pushNamed('/info/', arguments: item),
                        onMarkSeason: (year, month) => context.pushNamed(
                            '/mark/',
                            arguments: {'year': year, 'month': month}),
                      ),
                      StatsCharts(entries: controller.collectibles.toList()),
                    ],
                  );
                },
              ),
            ),
            bottomNavigationBar: selecting ? _selectionBar(context) : null,
          ),
        );
      },
    );
  }

  SysAppBar _normalAppBar(ThemeData theme) {
    return SysAppBar(
      title: Text(
        '追番统计',
        style: theme.textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      actions: [
        KazumiMenuButton(
          builder: (context, toggle) => IconButton(
            tooltip: '排序方式',
            icon: const Icon(Icons.sort_rounded),
            onPressed: toggle,
          ),
          menuChildren: [
            for (final order in StatsSortOrder.values)
              KazumiMenuItem(
                label: order.label,
                selected: order == controller.sortOrder,
                onPressed: () => controller.setSortOrder(order),
              ),
          ],
        ),
        BangumiCardViewSizeMenu(value: _viewSize, onChanged: _changeViewSize),
        IconButton(
          tooltip: '多选打标',
          icon: const Icon(Icons.checklist_rounded),
          onPressed: controller.enterSelection,
        ),
        const SizedBox(width: 8),
      ],
      bottom: _tabBar(theme),
    );
  }

  SysAppBar _selectionAppBar(ThemeData theme) {
    final visible = controller.filteredEntries();
    final allSelected = visible.isNotEmpty &&
        visible.every((entry) =>
            controller.selectedIds.contains(entry.bangumiItem.id));
    return SysAppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: '退出多选',
        onPressed: controller.leaveSelection,
      ),
      title: Text('已选 ${controller.selectedIds.length} 项'),
      actions: [
        TextButton(
          onPressed: () => controller.toggleSelectAll(visible),
          child: Text(allSelected ? '取消全选' : '全选'),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  PreferredSizeWidget _tabBar(ThemeData theme) {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      dividerHeight: 0,
      indicatorSize: TabBarIndicatorSize.tab,
      indicatorPadding: const EdgeInsets.symmetric(horizontal: 2),
      indicator: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      indicatorAnimation: TabIndicatorAnimation.elastic,
      labelColor: theme.colorScheme.onPrimaryContainer,
      unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
      labelStyle:
          theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle:
          theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      splashBorderRadius: BorderRadius.circular(24),
      tabs: const [
        Tab(height: 48, text: '季度列表'),
        Tab(height: 48, text: '图表'),
      ],
    );
  }

  Widget _selectionBar(BuildContext context) {
    final theme = Theme.of(context);
    return BottomAppBar(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '已选 ${controller.selectedIds.length} 项',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          KazumiMenuButton(
            builder: (context, toggle) => FilledButton.tonalIcon(
              onPressed: controller.selectedIds.isEmpty ? null : toggle,
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
          const SizedBox(width: 8),
          IconButton(
            tooltip: '删除收藏',
            icon: Icon(Icons.delete_outline_rounded,
                color: theme.colorScheme.error),
            onPressed: controller.selectedIds.isEmpty
                ? null
                : _confirmBulkDelete,
          ),
        ],
      ),
    );
  }
}
