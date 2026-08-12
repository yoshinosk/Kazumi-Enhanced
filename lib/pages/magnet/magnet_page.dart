import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:file_picker/file_picker.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart' show GeneralEmptyState;
import 'package:kazumi/pages/magnet/magnet_controller.dart';
import 'package:kazumi/services/magnet/animes_garden_service.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/magnet/magnet_download_service.dart';
import 'package:kazumi/services/magnet/magnet_search_sources.dart';

class MagnetPage extends StatefulWidget {
  const MagnetPage({super.key, required this.controller, this.initialQuery});

  final MagnetController controller;

  /// 可选的初始搜索关键词，由番剧详情页「搜索资源」传入。
  final String? initialQuery;

  @override
  State<MagnetPage> createState() => _MagnetPageState();
}

class _MagnetPageState extends State<MagnetPage>
    with SingleTickerProviderStateMixin {
  MagnetController get controller => widget.controller;
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final initial = widget.initialQuery;
    if (initial != null && initial.trim().isNotEmpty) {
      _searchController.text = initial.trim();
      // 延迟一帧执行搜索，确保控制器已就绪。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.search(initial.trim());
      });
    } else {
      _searchController.text = controller.query;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('磁力搜索'),
        leading: IconButton(
          onPressed: () => context.maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          Observer(builder: (_) {
            return PopupMenuButton<String>(
              tooltip: '切换搜索源',
              icon: const Icon(Icons.travel_explore_rounded),
              onSelected: (value) => controller.setSearchSource(value),
              itemBuilder: (_) => [
                for (final source in MagnetSearchSources.all)
                  PopupMenuItem<String>(
                    value: source.id,
                    child: Row(
                      children: [
                        Icon(
                          controller.currentSourceId == source.id
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
          }),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '搜索'),
            Tab(text: '订阅'),
            Tab(text: '下载'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          MagnetSearchTab(
            controller: controller,
            searchController: _searchController,
          ),
          MagnetSubscriptionsTab(controller: controller),
          MagnetDownloadsTab(controller: controller),
        ],
      ),
    );
  }
}

class MagnetSearchTab extends StatefulWidget {
  const MagnetSearchTab({
    super.key,
    required this.controller,
    required this.searchController,
  });

  final MagnetController controller;
  final TextEditingController searchController;

  @override
  State<MagnetSearchTab> createState() => _MagnetSearchTabState();
}

class _MagnetSearchTabState extends State<MagnetSearchTab> {
  MagnetController get controller => widget.controller;
  List<AnimesGardenTeam> _teams = const [];
  bool _loadingTeams = false;
  bool _autoLoading = false;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    setState(() => _loadingTeams = true);
    final teams = await controller.fetchAnimesGardenTeams();
    if (mounted) {
      setState(() {
        _teams = teams;
        _loadingTeams = false;
      });
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n is! ScrollEndNotification) return false;
    final metrics = n.metrics;
    if (metrics.pixels >= metrics.maxScrollExtent - 240 &&
        controller.hasMoreSearchResults &&
        !controller.isLoadingMore &&
        !controller.isSearching &&
        !_autoLoading) {
      _autoLoading = true;
      controller.loadMore().whenComplete(() {
        if (mounted) _autoLoading = false;
      });
    }
    return false;
  }

  Future<void> _pickSearchFansub() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final searchCtrl =
            TextEditingController(text: controller.searchFansub ?? '');
        return StatefulBuilder(
          builder: (innerCtx, setInnerState) {
            final q = searchCtrl.text.trim().toLowerCase();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(innerCtx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('筛选字幕组', style: TextStyle(fontSize: 16)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(innerCtx, null),
                          child: const Text('取消'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '搜索或手动输入字幕组名称',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                      ),
                      onChanged: (_) => setInnerState(() {}),
                    ),
                  ),
                  const Divider(height: 8),
                  Flexible(
                    child: _loadingTeams
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              if (controller.searchFansub != null)
                                ListTile(
                                  leading:
                                      const Icon(Icons.clear_rounded, size: 20),
                                  title: const Text('清除（不限字幕组）'),
                                  onTap: () =>
                                      Navigator.pop(innerCtx, '__clear__'),
                                ),
                              ..._teams
                                  .where((t) =>
                                      t.name.toLowerCase().contains(q))
                                  .map((t) => ListTile(
                                        dense: true,
                                        title: Text(t.name),
                                        trailing: t.name ==
                                                controller.searchFansub
                                            ? const Icon(Icons.check_rounded,
                                                size: 20)
                                            : null,
                                        onTap: () =>
                                            Navigator.pop(innerCtx, t.name),
                                      )),
                              if (searchCtrl.text.trim().isNotEmpty &&
                                  !_teams.any((t) =>
                                      t.name == searchCtrl.text.trim()))
                                ListTile(
                                  dense: true,
                                  leading:
                                      const Icon(Icons.add_rounded, size: 20),
                                  title: Text('使用「${searchCtrl.text.trim()}」'),
                                  onTap: () => Navigator.pop(
                                      innerCtx, searchCtrl.text.trim()),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
    if (picked == null) return;
    final value = picked == '__clear__' ? null : picked;
    await controller.setSearchFansub(value);
  }

  void _createSubscriptionFromSearch() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _AddSubscriptionPage(
        controller: controller,
        presetKind: SubscriptionKind.animesGarden,
        presetFeedUrl: controller.query,
        presetFansub: controller.searchFansub,
      ),
      fullscreenDialog: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: widget.searchController,
            decoration: InputDecoration(
              hintText: '输入番剧名称或关键词',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search_rounded),
                onPressed: () => controller.search(widget.searchController.text),
              ),
            ),
            onSubmitted: (value) => controller.search(value),
          ),
          // 搜索条件工具栏：字幕组筛选（仅 AG 源）+ 按当前条件创建订阅
          Observer(builder: (_) {
            final isAg =
                controller.defaultSource.kind == MagnetSourceKind.json;
            final hasQuery = controller.query.trim().isNotEmpty;
            if (!isAg && !hasQuery) {
              return const SizedBox(height: 4);
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  if (isAg)
                    Expanded(
                      child: InkWell(
                        onTap: _pickSearchFansub,
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon:
                                const Icon(Icons.groups_rounded, size: 18),
                            prefixIconConstraints:
                                const BoxConstraints(minWidth: 32),
                          ),
                          child: Text(
                            controller.searchFansub ?? '字幕组：不限',
                            style: TextStyle(
                              fontSize: 13,
                              color: controller.searchFansub == null
                                  ? Theme.of(context).hintColor
                                  : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (hasQuery) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _createSubscriptionFromSearch,
                      icon: const Icon(Icons.rss_feed_rounded, size: 18),
                      label: const Text('订阅当前搜索',
                          style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          Expanded(
            child: Observer(builder: (_) {
              if (controller.isSearching) {
                return const Center(child: CircularProgressIndicator());
              }
              if (controller.searchResults.isEmpty) {
                return Center(
                  child: GeneralEmptyState(
                    icon: Icons.search_off_rounded,
                    title: controller.searchError ?? '输入关键词开始搜索',
                  ),
                );
              }
              return NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: controller.searchResults.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index == controller.searchResults.length) {
                      // 底部加载指示：自动加载更多时显示 spinner，无更多时收尾间距
                      if (controller.isLoadingMore) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      return const SizedBox(height: 8);
                    }
                    final item = controller.searchResults[index];
                    return _MagnetSearchTile(
                      item: item,
                      onDownload: () => controller.addDownload(item),
                    );
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _MagnetSearchTile extends StatelessWidget {
  const _MagnetSearchTile({required this.item, required this.onDownload});

  final MagnetSearchItem item;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              if (item.size.isNotEmpty)
                _MetaChip(icon: Icons.sd_storage_rounded, label: item.size),
              if (item.publisher != null)
                _MetaChip(
                    icon: Icons.person_outline, label: item.publisher!),
              _MetaChip(
                icon: Icons.schedule_rounded,
                label: _formatDate(item.publishDate),
              ),
            ],
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.download_for_offline_outlined),
        tooltip: '下载',
        onPressed: onDownload,
      ),
      onTap: () => _showDetailSheet(context),
    );
  }

  void _showDetailSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (item.size.isNotEmpty) _DetailRow(label: '大小', value: item.size),
              if (item.publisher != null)
                _DetailRow(label: '发布者', value: item.publisher!),
              _DetailRow(
                  label: '发布时间', value: _formatDate(item.publishDate)),
              if (item.magnetLink.isNotEmpty) ...[
                const SizedBox(height: 8),
                _DetailRow(
                  label: '磁力链',
                  value: item.magnetLink,
                  selectable: true,
                ),
              ],
              if (item.torrentUrl.isNotEmpty) ...[
                const SizedBox(height: 8),
                _DetailRow(
                  label: '种子直链',
                  value: item.torrentUrl,
                  selectable: true,
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onDownload();
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('下载'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: selectable
                ? SelectableText(value, style: theme.textTheme.bodySmall)
                : Text(value, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// RSS 订阅列表 Tab，可在磁力搜索页和下载中心复用。
class MagnetSubscriptionsTab extends StatefulWidget {
  const MagnetSubscriptionsTab({super.key, required this.controller});

  final MagnetController controller;

  @override
  State<MagnetSubscriptionsTab> createState() => _MagnetSubscriptionsTabState();
}

class _MagnetSubscriptionsTabState extends State<MagnetSubscriptionsTab> {
  MagnetController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddDialog(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('添加订阅'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: controller.subscriptions.isEmpty
                      ? null
                      : () => controller.checkSubscriptions(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('检查更新'),
                ),
              ],
            ),
          ),
          Expanded(
            child: controller.subscriptions.isEmpty
                ? const Center(
                    child: GeneralEmptyState(
                      icon: Icons.rss_feed_rounded,
                      title: '还没有 RSS 订阅源，点击上方按钮添加',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: controller.subscriptions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final sub = controller.subscriptions[index];
                      return _SubscriptionTile(
                        subscription: sub,
                        controller: controller,
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }

  void _showAddDialog(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _AddSubscriptionPage(controller: controller),
      fullscreenDialog: true,
    ));
  }
}

class _SubscriptionTile extends StatefulWidget {
  const _SubscriptionTile({
    required this.subscription,
    required this.controller,
  });

  final MagnetSubscription subscription;
  final MagnetController controller;

  @override
  State<_SubscriptionTile> createState() => _SubscriptionTileState();
}

class _SubscriptionTileState extends State<_SubscriptionTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final sub = widget.subscription;
    final theme = Theme.of(context);
    return Column(
      children: [
        ListTile(
          leading: Icon(sub.kind == SubscriptionKind.animesGarden
              ? Icons.cloud_circle_rounded
              : Icons.rss_feed_rounded),
          title: Text(sub.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            _subscriptionSummary(sub),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: '加载条目',
                onPressed: () => widget.controller.loadSubscriptionFeed(sub),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: '编辑订阅',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _AddSubscriptionPage(
                      controller: widget.controller,
                      existing: sub,
                    ),
                    fullscreenDialog: true,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: '删除订阅',
                onPressed: () =>
                    widget.controller.removeSubscription(sub.id),
              ),
            ],
          ),
          onTap: () {
            setState(() => _expanded = !_expanded);
            if (_expanded) {
              widget.controller.loadSubscriptionFeed(sub);
            }
          },
        ),
        if (_expanded)
          Observer(
            builder: (_) {
              final feed = widget.controller.subscriptionFeeds[sub.id];
              if (feed == null) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (feed.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('暂无条目'),
                );
              }
              return Column(
                children: [
                  for (final item in feed.take(20))
                    _MagnetSearchTile(
                      item: item,
                      onDownload: () =>
                          widget.controller.addDownload(item),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

String _subscriptionSummary(MagnetSubscription sub) {
  final parts = <String>[];
  if (sub.kind == SubscriptionKind.animesGarden) {
    parts.add('AG: ${sub.feedUrl}');
    if (sub.fansub != null) parts.add('字幕组:${sub.fansub}');
    if (sub.keywords != null) parts.add('关键字:${sub.keywords}');
    if (sub.since != null) {
      parts.add('${sub.since!.year}-${sub.since!.month.toString().padLeft(2, '0')}-${sub.since!.day.toString().padLeft(2, '0')}后');
    }
    if (sub.minSizeMb != null) parts.add('≥${sub.minSizeMb}MB');
    if (sub.maxSizeMb != null) parts.add('≤${sub.maxSizeMb}MB');
    if (sub.downloadPath != null) parts.add('目录:${sub.downloadPath}');
  } else {
    parts.add(sub.feedUrl);
  }
  return parts.join('  ');
}

enum _DownloadsFilter { all, active, completed }

/// 磁力下载任务列表 Tab，可在磁力搜索页和下载中心复用。
///
/// 支持按「全部 / 进行中 / 已完成」筛选：
/// - 进行中 = 下载中（等待 / 获取元数据 / 校验 / 下载）+ 做种中；
/// - 已完成 = 下载完成且做种达标（做种率 ≥ 1）。
class MagnetDownloadsTab extends StatefulWidget {
  const MagnetDownloadsTab({super.key, required this.controller});

  final MagnetController controller;

  @override
  State<MagnetDownloadsTab> createState() => _MagnetDownloadsTabState();
}

class _MagnetDownloadsTabState extends State<MagnetDownloadsTab> {
  _DownloadsFilter _filter = _DownloadsFilter.all;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Observer(builder: (_) {
      if (!controller.engineEnabled) {
        return const Center(
          child: GeneralEmptyState(
            icon: Icons.cloud_off_rounded,
            title: '未启用磁力下载引擎，请前往 设置 → 磁力搜索 开启',
          ),
        );
      }
      final tasks = switch (_filter) {
        _DownloadsFilter.all => controller.downloadTasks,
        _DownloadsFilter.active => controller.downloadTasks
            .where((t) => t.isDownloading || t.isSeeding)
            .toList(),
        _DownloadsFilter.completed =>
          controller.downloadTasks.where((t) => t.isCompleted).toList(),
      };
      final (icon, emptyTitle) = switch (_filter) {
        _DownloadsFilter.all => (
            Icons.download_done_rounded,
            '暂无下载任务'
          ),
        _DownloadsFilter.active => (
            Icons.downloading_rounded,
            '没有进行中的任务'
          ),
        _DownloadsFilter.completed => (
            Icons.done_all_rounded,
            '还没有已完成的任务'
          ),
      };
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_DownloadsFilter>(
                segments: const [
                  ButtonSegment(
                    value: _DownloadsFilter.all,
                    label: Text('全部'),
                  ),
                  ButtonSegment(
                    value: _DownloadsFilter.active,
                    label: Text('进行中'),
                  ),
                  ButtonSegment(
                    value: _DownloadsFilter.completed,
                    label: Text('已完成'),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (selection) =>
                    setState(() => _filter = selection.first),
                showSelectedIcon: false,
              ),
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: GeneralEmptyState(icon: icon, title: emptyTitle),
                  )
                : RefreshIndicator(
                    onRefresh: () => controller.refreshDownloads(),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: tasks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        return _DownloadTaskTile(
                          task: task,
                          onPause: () => controller.pauseDownload(task.gid),
                          onResume: () => controller.resumeDownload(task.gid),
                          onRemove: () => controller.removeDownload(task.gid),
                        );
                      },
                    ),
                  ),
          ),
        ],
      );
    });
  }
}

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onRemove,
  });

  final MagnetDownloadEntry task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = task.progress;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      title: Text(
        task.title.isEmpty ? task.fileName : task.title,
        maxLines: 2,
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusChip(status: task.status),
                    if (task.totalLength > 0)
                      Text(
                        '${_formatBytes(task.completedLength)} / ${_formatBytes(task.totalLength)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (task.downloadSpeed > 0)
                      _TaskMeta(
                        icon: Icons.south_rounded,
                        color: theme.colorScheme.primary,
                        text: '${_formatBytes(task.downloadSpeed)}/s',
                      ),
                    if (task.uploadSpeed > 0 && !task.isCompleted)
                      _TaskMeta(
                        icon: Icons.north_rounded,
                        color: theme.colorScheme.secondary,
                        text: '${_formatBytes(task.uploadSpeed)}/s',
                      ),
                    if (task.numSeeds + task.numPeers > 0 && !task.isCompleted)
                      _TaskMeta(
                        icon: Icons.groups_2_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                        text: '做种 ${task.numSeeds} · 连接 ${task.numPeers}',
                      ),
                    if (task.seedRatio > 0)
                      _TaskMeta(
                        icon: Icons.sync_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                        text: '做种率 ${_formatRatio(task.seedRatio)}',
                      ),
                    if (task.isActive && task.etaSeconds >= 0)
                      _TaskMeta(
                        icon: Icons.timer_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                        text: '剩余 ${_formatEta(task.etaSeconds)}',
                      ),
                    if (task.status == 'checking')
                      _TaskMeta(
                        icon: Icons.verified_outlined,
                        color: theme.colorScheme.tertiary,
                        text: '正在校验已下载文件',
                      ),
                    if (task.status == 'metadata')
                      _TaskMeta(
                        icon: Icons.hub_outlined,
                        color: theme.colorScheme.tertiary,
                        text: '正在获取种子元数据',
                      ),
                  ],
                ),
              ),
              if (task.totalLength > 0) ...[
                const SizedBox(width: 10),
                Text(
                  '${(progress.clamp(0.0, 1.0) * 100).toStringAsFixed(1)}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) {
          switch (value) {
            case 'pause':
              onPause();
              break;
            case 'resume':
              onResume();
              break;
            case 'remove':
              onRemove();
              break;
          }
        },
        itemBuilder: (context) => [
          if (task.isActive)
            const PopupMenuItem(value: 'pause', child: Text('暂停')),
          if (task.isPaused)
            const PopupMenuItem(value: 'resume', child: Text('继续')),
          const PopupMenuItem(value: 'remove', child: Text('删除')),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (status) {
      'active' => ('下载中', theme.colorScheme.primary),
      'waiting' => ('等待中', theme.colorScheme.tertiary),
      'metadata' => ('获取元数据中', theme.colorScheme.tertiary),
      'checking' => ('校验进度中', theme.colorScheme.tertiary),
      'seeding' => ('做种中', theme.colorScheme.tertiary),
      'paused' => ('已暂停', theme.colorScheme.secondary),
      'complete' => ('已完成', Colors.green),
      'error' => ('错误', theme.colorScheme.error),
      'removed' => ('已删除', theme.colorScheme.error),
      _ => (status, theme.colorScheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _TaskMeta extends StatelessWidget {
  const _TaskMeta({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[unit]}';
}

String _formatRatio(double ratio) {
  if (ratio <= 0) return '0.00';
  if (ratio >= 100) return ratio.toStringAsFixed(0);
  return ratio.toStringAsFixed(2);
}

String _formatEta(int seconds) {
  if (seconds <= 0) return '0s';
  if (seconds < 60) return '${seconds}s';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

/// 添加 / 编辑订阅页面。
///
/// 支持 Mikan（RSS）和 Animes Garden（JSON API + 客户端筛选）两种源。
/// Animes Garden 可配置字幕组、关键字、日期下限、体积范围、下载目录。
class _AddSubscriptionPage extends StatefulWidget {
  const _AddSubscriptionPage({
    required this.controller,
    this.existing,
    this.presetKind,
    this.presetFeedUrl,
    this.presetFansub,
  });

  final MagnetController controller;
  final MagnetSubscription? existing;

  /// 从搜索页「订阅当前搜索」带入的预设：源类型 / 关键词 / 字幕组。
  final SubscriptionKind? presetKind;
  final String? presetFeedUrl;
  final String? presetFansub;

  @override
  State<_AddSubscriptionPage> createState() => _AddSubscriptionPageState();
}

class _AddSubscriptionPageState extends State<_AddSubscriptionPage> {
  late SubscriptionKind _kind;
  final _nameCtrl = TextEditingController();
  final _feedCtrl = TextEditingController(); // Mikan: RSS / AG: 关键词
  final _keywordsCtrl = TextEditingController();
  final _minSizeCtrl = TextEditingController();
  final _maxSizeCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  DateTime? _since;
  String? _fansub;
  List<AnimesGardenTeam> _teams = const [];
  bool _loadingTeams = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _kind = e.kind;
      _nameCtrl.text = e.name;
      _feedCtrl.text = e.feedUrl;
      _keywordsCtrl.text = e.keywords ?? '';
      _minSizeCtrl.text = e.minSizeMb?.toString() ?? '';
      _maxSizeCtrl.text = e.maxSizeMb?.toString() ?? '';
      _pathCtrl.text = e.downloadPath ?? '';
      _since = e.since;
      _fansub = e.fansub;
    } else {
      _kind = widget.presetKind ?? SubscriptionKind.animesGarden;
      // 从搜索页带入的预设：填充关键词与字幕组，名称留空让用户填
      _feedCtrl.text = widget.presetFeedUrl ?? '';
      _fansub = widget.presetFansub;
    }
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    setState(() => _loadingTeams = true);
    final teams = await widget.controller.fetchAnimesGardenTeams();
    if (mounted) {
      setState(() {
        _teams = teams;
        _loadingTeams = false;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _feedCtrl.dispose();
    _keywordsCtrl.dispose();
    _minSizeCtrl.dispose();
    _maxSizeCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_feedCtrl.text.trim().isEmpty) {
      KazumiDialog.showToast(
        message: _kind == SubscriptionKind.mikan ? '请填写 RSS 地址' : '请填写搜索关键词',
      );
      return;
    }
    double? parseMb(String s) {
      final v = double.tryParse(s.trim());
      return (s.trim().isEmpty || v == null) ? null : v;
    }
    final sub = MagnetSubscription(
      id: widget.existing?.id ?? '',
      name: _nameCtrl.text.trim(),
      feedUrl: _feedCtrl.text.trim(),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      kind: _kind,
      fansub: _fansub,
      keywords: _keywordsCtrl.text.trim().isEmpty ? null : _keywordsCtrl.text.trim(),
      since: _since,
      minSizeMb: parseMb(_minSizeCtrl.text),
      maxSizeMb: parseMb(_maxSizeCtrl.text),
      downloadPath: _pathCtrl.text.trim().isEmpty ? null : _pathCtrl.text.trim(),
    );
    if (widget.existing == null) {
      await widget.controller.addSubscription(sub);
    } else {
      await widget.controller.updateSubscription(sub);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isAg = _kind == SubscriptionKind.animesGarden;
    return Scaffold(
      appBar: SysAppBar(
        title: Text(widget.existing == null ? '添加订阅' : '编辑订阅'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 8,
              children: SubscriptionKind.values.map((k) {
                final selected = k == _kind;
                return ChoiceChip(
                  label: Text(k == SubscriptionKind.animesGarden
                      ? 'Animes Garden'
                      : 'Mikan RSS'),
                  selected: selected,
                  onSelected: (_) => setState(() => _kind = k),
                );
              }).toList(),
            ),
          ),
          ListTile(
            title: TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '名称（可选）',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          ListTile(
            title: TextField(
              controller: _feedCtrl,
              decoration: InputDecoration(
                labelText: isAg ? '搜索关键词' : 'RSS 地址',
                hintText: isAg
                    ? '如：葬送的芙莉莲'
                    : 'https://mikanani.me/RSS/Bangumi?bangumiId=xxx',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (isAg) ...[
            ListTile(
              leading: const Icon(Icons.groups_rounded),
              title: const Text('字幕组'),
              subtitle: Text(
                _fansub == null ? '不限' : _fansub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _loadingTeams
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _loadingTeams ? null : _pickFansub,
            ),
            ListTile(
              leading: const Icon(Icons.key_rounded),
              title: TextField(
                controller: _keywordsCtrl,
                decoration: const InputDecoration(
                  labelText: '标题关键字（可选，逗号分隔多关键字）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.event_rounded),
              title: const Text('发布日期下限'),
              subtitle: Text(_since == null
                  ? '不限'
                  : '${_since!.year}-${_since!.month.toString().padLeft(2, '0')}-${_since!.day.toString().padLeft(2, '0')}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_since != null)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 20),
                      onPressed: () => setState(() => _since = null),
                    ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _since ?? DateTime.now(),
                  firstDate: DateTime(2010),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (d != null) setState(() => _since = d);
              },
            ),
            ListTile(
              leading: const Icon(Icons.straighten_rounded),
              title: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minSizeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '最小 MB',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('～'),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _maxSizeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '最大 MB',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: TextField(
                controller: _pathCtrl,
                decoration: const InputDecoration(
                  labelText: '下载目录（可选，留空用默认）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.folder_open_rounded, size: 20),
                tooltip: '选择目录',
                onPressed: _pickDownloadDir,
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _pickDownloadDir() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择下载目录',
    );
    if (path != null && mounted) {
      setState(() => _pathCtrl.text = path);
    }
  }

  Future<void> _pickFansub() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final searchCtrl = TextEditingController(text: _fansub ?? '');
        return StatefulBuilder(
          builder: (innerCtx, setInnerState) {
            final q = searchCtrl.text.trim().toLowerCase();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(innerCtx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('选择字幕组', style: TextStyle(fontSize: 16)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(innerCtx, null),
                          child: const Text('取消'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '搜索或手动输入字幕组名称',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                      ),
                      onChanged: (_) => setInnerState(() {}),
                    ),
                  ),
                  const Divider(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (_fansub != null)
                          ListTile(
                            leading: const Icon(Icons.clear_rounded, size: 20),
                            title: const Text('清除（不限字幕组）'),
                            onTap: () => Navigator.pop(innerCtx, '__clear__'),
                          ),
                        ..._teams
                            .where((t) => t.name.toLowerCase().contains(q))
                            .map((t) => ListTile(
                                  dense: true,
                                  title: Text(t.name),
                                  trailing: t.name == _fansub
                                      ? const Icon(Icons.check_rounded, size: 20)
                                      : null,
                                  onTap: () => Navigator.pop(innerCtx, t.name),
                                )),
                        if (searchCtrl.text.trim().isNotEmpty &&
                            !_teams.any((t) => t.name == searchCtrl.text.trim()))
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.add_rounded, size: 20),
                            title: Text('使用「${searchCtrl.text.trim()}」'),
                            onTap: () =>
                                Navigator.pop(innerCtx, searchCtrl.text.trim()),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
    if (picked == null) return;
    setState(() => _fansub = picked == '__clear__' ? null : picked);
  }
}
