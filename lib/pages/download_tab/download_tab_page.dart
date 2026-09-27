import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart'
    show GeneralEmptyState;
import 'package:kazumi/bean/widget/tab_pill_bar.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/magnet/magnet_controller.dart';
import 'package:kazumi/pages/magnet/magnet_page.dart'
    show MagnetDownloadsTab, MagnetSearchTab, MagnetSubscriptionsTab;
import 'package:kazumi/services/magnet/magnet_search_sources.dart';
import 'package:kazumi/utils/device.dart';

/// 下载中心：汇总磁力搜索、磁力下载、RSS 订阅与离线缓存，作为底部导航的「下载」标签页。
class DownloadTabPage extends StatefulWidget {
  const DownloadTabPage({
    super.key,
    required this.magnetController,
    required this.downloadController,
  });

  final MagnetController magnetController;
  final DownloadController downloadController;

  @override
  State<DownloadTabPage> createState() => _DownloadTabPageState();
}

class _DownloadTabPageState extends State<DownloadTabPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    widget.downloadController.refreshRecords();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 桌面宽屏：默认 TabBar 会把标签等分拉伸得很宽，改为在标题栏内
    // 放置按内容自适应的分类胶囊栏；安卓 / 窄窗口保持顶部 TabBar 切换。
    final usePillBar =
        isDesktop() && MediaQuery.sizeOf(context).width >= _pillBarBreakpoint;
    final appBar = SysAppBar(
      title: usePillBar
          ? Row(
              children: [
                const Text('下载'),
                Expanded(
                  child: Center(
                    child: TabPillBar(
                      controller: _tabController,
                      items: const [
                        TabPillItem(
                          icon: Icons.travel_explore_outlined,
                          selectedIcon: Icons.travel_explore_rounded,
                          label: '磁力搜索',
                        ),
                        TabPillItem(
                          icon: Icons.download_outlined,
                          selectedIcon: Icons.download_rounded,
                          label: '磁力下载',
                        ),
                        TabPillItem(
                          icon: Icons.rss_feed_outlined,
                          selectedIcon: Icons.rss_feed_rounded,
                          label: 'RSS 订阅',
                        ),
                        TabPillItem(
                          icon: Icons.cloud_download_outlined,
                          selectedIcon: Icons.cloud_download_rounded,
                          label: '离线缓存',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : const Text('下载'),
      actions: [
        Observer(
          builder: (_) {
            return PopupMenuButton<String>(
              tooltip: '切换搜索源',
              icon: const Icon(Icons.travel_explore_rounded),
              onSelected: (value) =>
                  widget.magnetController.setSearchSource(value),
              itemBuilder: (_) => [
                for (final source in MagnetSearchSources.all)
                  PopupMenuItem<String>(
                    value: source.id,
                    child: Row(
                      children: [
                        Icon(
                          widget.magnetController.currentSourceId == source.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(source.name),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        IconButton(
          tooltip: '下载器设置',
          onPressed: () => context.pushNamed('/settings/magnet/'),
          icon: const Icon(Icons.settings_rounded),
        ),
      ],
      bottom: usePillBar
          ? null
          : TabBar(
              controller: _tabController,
              // 窄屏 / 系统大字号下 tab 文字可能放不下：单行 + 自动缩小，
              // 避免默认的换行渲染被固定 tab 高度裁掉下半截。
              tabs: [
                for (final label in const [
                  '磁力搜索',
                  '磁力下载',
                  'RSS 订阅',
                  '离线缓存',
                ])
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, maxLines: 1),
                    ),
                  ),
              ],
            ),
    );
    final tabBarView = TabBarView(
      controller: _tabController,
      children: [
        MagnetSearchTab(
          controller: widget.magnetController,
          searchController: _searchController,
        ),
        MagnetDownloadsTab(controller: widget.magnetController),
        MagnetSubscriptionsTab(controller: widget.magnetController),
        _OfflineCacheTab(controller: widget.downloadController),
      ],
    );
    // 宽窄切换只影响标题栏内的组件，body 始终是同一个 TabBarView，
    // 各 tab 的滚动位置等 State 不会因子树重建而丢失。
    return Scaffold(appBar: appBar, body: tabBarView);
  }

  /// 宽屏（≥ 700px）时切换到顶部胶囊标签栏的断点。
  static const double _pillBarBreakpoint = 700;
}

/// 离线缓存概览：展示每部番剧的缓存进度，点击进入完整下载管理页。
class _OfflineCacheTab extends StatelessWidget {
  const _OfflineCacheTab({required this.controller});

  final DownloadController controller;

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final keys = controller.recordKeys.toList();
        if (keys.isEmpty) {
          return const Center(
            child: GeneralEmptyState(
              icon: Icons.download_done_rounded,
              title: '暂无离线缓存',
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => controller.refreshRecords(),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: keys.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final record = controller.getRecordSnapshot(keys[index]);
              if (record == null) return const SizedBox.shrink();
              return _OfflineCacheTile(record: record);
            },
          ),
        );
      },
    );
  }
}

class _OfflineCacheTile extends StatelessWidget {
  const _OfflineCacheTile({required this.record});

  final DownloadRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final episodes = record.episodes.values.toList();
    final total = episodes.length;
    final completed = episodes
        .where((e) => e.status == DownloadStatus.completed)
        .length;
    final active = episodes
        .where((e) => e.status == DownloadStatus.downloading)
        .length;
    final failed = episodes
        .where((e) => e.status == DownloadStatus.failed)
        .length;
    final progress = total > 0 ? completed / total : 0.0;

    final String statusText;
    final Color statusColor;
    if (active > 0) {
      statusText = '下载中 $active';
      statusColor = theme.colorScheme.primary;
    } else if (failed > 0) {
      statusText = '失败 $failed';
      statusColor = theme.colorScheme.error;
    } else if (completed == total) {
      statusText = '已完成';
      statusColor = Colors.green;
    } else {
      statusText = '已暂停';
      statusColor = theme.colorScheme.secondary;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      title: Text(
        record.bangumiName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('$completed / $total 集', style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
              ),
              const Spacer(),
              Text(
                record.pluginName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: () => context.pushNamed('/settings/download/'),
    );
  }
}
