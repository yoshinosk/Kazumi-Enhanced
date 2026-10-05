import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/collect/collect_library_query.dart';
import 'package:kazumi/pages/stats/stats_controller.dart';
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

  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: SysAppBar(
        title: Text(
          '追番统计',
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        bottom: TabBar(
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
          labelStyle: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
          unselectedLabelStyle: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w500),
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          splashBorderRadius: BorderRadius.circular(24),
          tabs: const [
            Tab(height: 48, text: '季度列表'),
            Tab(height: 48, text: '图表'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Observer(
          builder: (context) {
            final entries = widget.controller.collectibles.toList();
            if (entries.isEmpty) {
              return const GeneralEmptyState(
                icon: Icons.query_stats_rounded,
                title: '还没有收藏的番剧，先去添加一些吧',
              );
            }
            return TabBarView(
              controller: _tabController,
              children: [
                StatsGroupList(
                  entries: entries,
                  undatedCount: widget.controller.undatedCount,
                  onOpen: (item) => context.pushNamed('/info/', arguments: item),
                ),
                StatsCharts(entries: entries),
              ],
            );
          },
        ),
      ),
    );
  }
}
