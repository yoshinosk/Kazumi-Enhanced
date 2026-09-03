import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:file_picker/file_picker.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart'
    show GeneralEmptyState;
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart'
    show kLocalMediaAdapterName;
import 'package:kazumi/pages/magnet/magnet_controller.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/magnet/animes_garden_service.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/magnet/magnet_download_service.dart';
import 'package:kazumi/services/magnet/magnet_search_sources.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/media/media_scraper.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/local_episode_parser.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';

/// 番剧详情页发起的磁力搜索路由参数：搜索关键词 + 关联的番剧信息。
///
/// 携带 [anime] 时，本次会话中下载的任务默认为「已搜刮」的番剧，
/// 任务会同步番剧信息，下载完成后自动同步到媒体库。
class MagnetSearchRouteArgs {
  const MagnetSearchRouteArgs({required this.query, this.anime});

  final String query;
  final BangumiItem? anime;
}

class MagnetPage extends StatefulWidget {
  const MagnetPage({
    super.key,
    required this.controller,
    this.initialQuery,
    this.initialAnime,
  });

  final MagnetController controller;

  /// 可选的初始搜索关键词，由番剧详情页「搜索资源」传入。
  final String? initialQuery;

  /// 可选的关联番剧（由番剧详情页传入），携带后本次会话下载的任务
  /// 默认为「已搜刮」的番剧。
  final BangumiItem? initialAnime;

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
    _checkClipboardForMagnetLink();
  }

  /// 检测剪贴板中的磁力 / 种子链接，弹窗一键添加下载。
  ///
  /// 仅在进入磁力页时检查一次；与已有任务同源（按 info-hash 规范化
  /// 比较，与 addDownload 去重口径一致，忽略 tracker 参数差异）时跳过。
  Future<void> _checkClipboardForMagnetLink() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (!_isMagnetLikeLink(text)) return;
      final item = MagnetSearchItem(
        title: '剪贴板链接的任务',
        magnetLink: text.startsWith('magnet:') ? text : '',
        torrentUrl: text.startsWith('magnet:') ? '' : text,
        size: '',
        publishDate: DateTime.now(),
      );
      if (controller.isDownloadQueued(item)) return;
      if (!mounted) return;
      final theme = Theme.of(context);
      final confirmed = await KazumiDialog.show<bool>(
        builder: (dialogContext) => AlertDialog(
          title: const Text('检测到磁力链接'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                '是否添加到下载队列？',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(popWith: false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => KazumiDialog.dismiss(popWith: true),
              child: const Text('添加下载'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      controller.addDownload(item);
    } catch (e) {
      // 剪贴板不可用（权限等）时静默跳过。
      KazumiLogger().w('MagnetPage: clipboard check failed', error: e);
    }
  }

  bool _isMagnetLikeLink(String text) {
    if (text.toLowerCase().startsWith('magnet:?xt=urn:btih:')) return true;
    final lower = text.toLowerCase();
    return (lower.startsWith('http://') || lower.startsWith('https://')) &&
        lower.endsWith('.torrent');
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
            anime: widget.initialAnime,
          ),
          MagnetSubscriptionsTab(
              controller: controller, anime: widget.initialAnime),
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
    this.anime,
  });

  final MagnetController controller;
  final TextEditingController searchController;

  /// 关联番剧（由番剧详情页传入），非空时下载的任务默认为「已搜刮」。
  final BangumiItem? anime;

  @override
  State<MagnetSearchTab> createState() => _MagnetSearchTabState();
}

class _MagnetSearchTabState extends State<MagnetSearchTab> {
  MagnetController get controller => widget.controller;
  bool _autoLoading = false;

  /// 当前关键词下出现过的字幕组（去重排序），用于筛选选择器。
  /// 使用控制器缓存的候选列表：选中某字幕组后服务端过滤
  /// 会导致结果里只剩该组，缓存可保证仍能选其它组。
  List<String> get _resultFansubs => controller.fansubOptions;

  /// 详情页传入的番剧转换出的搜刮信息，非空时本次会话下载的任务
  /// 默认为「已搜刮」的番剧。
  MediaScrapeInfo? get _animeScrapeInfo {
    final anime = widget.anime;
    return anime == null ? null : MediaScrapeInfo.fromBangumiItem(anime);
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
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (controller.searchFansub != null)
                          ListTile(
                            leading: const Icon(Icons.clear_rounded, size: 20),
                            title: const Text('清除（不限字幕组）'),
                            onTap: () => Navigator.pop(innerCtx, '__clear__'),
                          ),
                        ..._resultFansubs
                            .where((name) => name.toLowerCase().contains(q))
                            .map((name) => ListTile(
                                  dense: true,
                                  title: Text(name),
                                  trailing: name == controller.searchFansub
                                      ? const Icon(Icons.check_rounded,
                                          size: 20)
                                      : null,
                                  onTap: () => Navigator.pop(innerCtx, name),
                                )),
                        if (_resultFansubs.isEmpty &&
                            searchCtrl.text.trim().isEmpty)
                          const ListTile(
                            dense: true,
                            enabled: false,
                            title: Text('当前搜索结果中没有字幕组信息'),
                          ),
                        if (searchCtrl.text.trim().isNotEmpty &&
                            !_resultFansubs.contains(searchCtrl.text.trim()))
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
                onPressed: () =>
                    controller.search(widget.searchController.text),
              ),
            ),
            onSubmitted: (value) => controller.search(value),
          ),
          // 搜索条件工具栏：字幕组筛选（仅 AG 源）+ 按当前条件创建订阅
          Observer(builder: (_) {
            final isAg = controller.defaultSource.kind == MagnetSourceKind.json;
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
                      label:
                          const Text('订阅当前搜索', style: TextStyle(fontSize: 13)),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      return const SizedBox(height: 8);
                    }
                    final item = controller.searchResults[index];
                    return _MagnetSearchTile(
                      item: item,
                      onDownload: () => controller.addDownload(
                        item,
                        scrapeInfo: _animeScrapeInfo,
                      ),
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
                _MetaChip(icon: Icons.person_outline, label: item.publisher!),
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
              if (item.size.isNotEmpty)
                _DetailRow(label: '大小', value: item.size),
              if (item.publisher != null)
                _DetailRow(label: '发布者', value: item.publisher!),
              _DetailRow(label: '发布时间', value: _formatDate(item.publishDate)),
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
  const MagnetSubscriptionsTab(
      {super.key, required this.controller, this.anime});

  final MagnetController controller;

  /// 关联番剧（由番剧详情页传入），非空时下载的任务默认为「已搜刮」。
  final BangumiItem? anime;

  @override
  State<MagnetSubscriptionsTab> createState() => _MagnetSubscriptionsTabState();
}

class _MagnetSubscriptionsTabState extends State<MagnetSubscriptionsTab> {
  MagnetController get controller => widget.controller;

  /// 详情页传入的番剧转换出的搜刮信息，非空时本次会话下载的任务
  /// 默认为「已搜刮」的番剧。
  MediaScrapeInfo? get _animeScrapeInfo {
    final anime = widget.anime;
    return anime == null ? null : MediaScrapeInfo.fromBangumiItem(anime);
  }

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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: controller.subscriptions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final sub = controller.subscriptions[index];
                      return _SubscriptionTile(
                        subscription: sub,
                        controller: controller,
                        scrapeInfo: _animeScrapeInfo,
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
    this.scrapeInfo,
  });

  final MagnetSubscription subscription;
  final MagnetController controller;

  /// 关联番剧的搜刮信息，非空时下载的任务默认为「已搜刮」。
  final MediaScrapeInfo? scrapeInfo;

  @override
  State<_SubscriptionTile> createState() => _SubscriptionTileState();
}

class _SubscriptionTileState extends State<_SubscriptionTile> {
  bool _expanded = false;

  /// 封面懒加载回填去重（避免列表重建时重复请求）。
  static final Set<String> _coverBackfilling = {};

  @override
  void initState() {
    super.initState();
    _maybeBackfillCover();
  }

  /// 旧订阅没有封面：进入列表时按名称搜索一次并回填持久化。
  Future<void> _maybeBackfillCover() async {
    final sub = widget.subscription;
    if (sub.coverUrl.isNotEmpty || _coverBackfilling.contains(sub.id)) return;
    _coverBackfilling.add(sub.id);
    try {
      final keyword = sub.name.isNotEmpty ? sub.name : sub.feedUrl;
      if (keyword.isEmpty) return;
      final page = await BangumiApi.bangumiSearch(keyword, limit: 5);
      if (!mounted || page == null || page.items.isEmpty) return;
      final cover =
          page.items.first.images['large'] ?? page.items.first.images['common'];
      if (cover != null && cover.isNotEmpty) {
        await widget.controller.updateSubscriptionCover(sub.id, cover);
      }
    } catch (e) {
      KazumiLogger().w('MagnetSubscription: backfill cover failed', error: e);
    } finally {
      _coverBackfilling.remove(sub.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.subscription;
    final theme = Theme.of(context);
    return Column(
      children: [
        ListTile(
          leading: sub.coverUrl.isNotEmpty
              ? SizedBox(
                  width: 44,
                  height: 60,
                  child:
                      NetworkImgLayer(src: sub.coverUrl, width: 44, height: 60),
                )
              : Icon(sub.kind == SubscriptionKind.animesGarden
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
                onPressed: () => widget.controller.removeSubscription(sub.id),
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
              final sub = widget.subscription;
              final feed = widget.controller.subscriptionFeeds[sub.id];
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 8),
                    child: SwitchListTile(
                      dense: true,
                      value: sub.autoDownload,
                      onChanged: (v) => widget.controller
                          .setSubscriptionAutoDownload(sub.id, v),
                      title: const Text('发现新内容时自动下载',
                          style: TextStyle(fontSize: 14)),
                      subtitle: const Text(
                        '关闭后仅在发现新条目时提醒，不会自动提交下载',
                        style: TextStyle(fontSize: 12),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const Divider(height: 1),
                  if (feed == null)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (feed.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('暂无条目'),
                    )
                  else
                    for (final item in feed.take(20))
                      _MagnetSearchTile(
                        item: item,
                        onDownload: () => widget.controller.addDownload(
                          item,
                          scrapeInfo: widget.scrapeInfo,
                        ),
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
      parts.add(
          '${sub.since!.year}-${sub.since!.month.toString().padLeft(2, '0')}-${sub.since!.day.toString().padLeft(2, '0')}后');
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
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  /// 是否按番剧分组展示（持久化在设置中，下载中心与磁力页共享）。
  bool get _grouped => GStorage.getSetting(SettingsKeys.magnetGroupDownloads);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _setGrouped(bool value) async {
    await GStorage.putSetting(SettingsKeys.magnetGroupDownloads, value);
    setState(() {});
  }

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
      final query = _searchQuery.trim().toLowerCase();
      Iterable<MagnetDownloadEntry> base = switch (_filter) {
        _DownloadsFilter.all => controller.downloadTasks,
        _DownloadsFilter.active => controller.downloadTasks
            .where((t) => t.isDownloading || t.isSeeding)
            .toList(),
        _DownloadsFilter.completed =>
          controller.downloadTasks.where((t) => t.isCompleted).toList(),
      };
      if (query.isNotEmpty) {
        base = base.where((t) =>
            t.title.toLowerCase().contains(query) ||
            t.fileName.toLowerCase().contains(query) ||
            (t.scrapeInfo?.displayName.toLowerCase().contains(query) ?? false));
      }
      // 列表固定按添加时间倒序展示（新任务在前），与任务状态无关。
      final tasks = base.toList()..sort(_compareTasksByAddedDesc);
      final hasCompleted = controller.downloadTasks.any((t) => t.isCompleted);
      final (icon, emptyTitle) = switch (_filter) {
        _DownloadsFilter.all => (Icons.download_done_rounded, '暂无下载任务'),
        _DownloadsFilter.active => (Icons.downloading_rounded, '没有进行中的任务'),
        _DownloadsFilter.completed => (Icons.done_all_rounded, '还没有已完成的任务'),
      };
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
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
                if (_filter == _DownloadsFilter.completed && hasCompleted)
                  IconButton(
                    tooltip: '清除已完成记录（保留文件）',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () => _confirmClearCompleted(context),
                  ),
                IconButton(
                  tooltip: _grouped ? '已按番剧分组' : '按番剧分组',
                  icon: Icon(
                    _grouped
                        ? Icons.library_books_rounded
                        : Icons.library_books_outlined,
                  ),
                  onPressed: () => _setGrouped(!_grouped),
                ),
                IconButton(
                  tooltip: '手动添加磁力链接',
                  icon: const Icon(Icons.add_link_rounded),
                  onPressed: () => _showAddMagnetDialog(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: '搜索任务',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: GeneralEmptyState(icon: icon, title: emptyTitle),
                  )
                : RefreshIndicator(
                    onRefresh: () => controller.refreshDownloads(),
                    child: _grouped
                        ? _buildGroupedList(context, tasks)
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            itemCount: tasks.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final task = tasks[index];
                              return _buildTaskTile(context, task);
                            },
                          ),
                  ),
          ),
        ],
      );
    });
  }

  /// 按番剧聚合的任务列表：每组一个头部（封面 / 标题 / 缺集检测）+ 任务条目。
  Widget _buildGroupedList(
      BuildContext context, List<MagnetDownloadEntry> tasks) {
    final byKey = <String, _DownloadGroup>{};
    for (final task in tasks) {
      final info = task.scrapeInfo;
      final key = info?.identityKey ??
          'raw:${task.title.isEmpty ? task.fileName : task.title}';
      final title = info?.displayName ??
          (task.title.isNotEmpty ? task.title : task.fileName);
      final group = byKey.putIfAbsent(
        key,
        () => _DownloadGroup(
          title: title,
          coverUrl: info?.coverUrl ?? '',
          bangumiId: info?.bangumiId,
          tasks: [],
        ),
      );
      group.tasks.add(task);
    }
    for (final group in byKey.values) {
      group.tasks.sort(_compareTasksByAddedDesc);
    }
    // 分组固定按「添加分组的时间」倒序：首个任务创建分组的时刻，
    // 即组内最早的任务添加时间，不随任务状态变化。
    final sortedGroups = byKey.values.toList()
      ..sort((a, b) => b.groupAddedAt.compareTo(a.groupAddedAt));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: sortedGroups.length,
      itemBuilder: (context, index) {
        final group = sortedGroups[index];
        return _DownloadGroupSection(
          key: ValueKey('group-${group.key}'),
          group: group,
          buildTaskTile: _buildTaskTile,
          onMissingEpisodes: (g) => _showGroupMissingEpisodes(context, g),
        );
      },
    );
  }

  /// 任务展示顺序：固定按添加时间倒序，同刻添加的按标题保持稳定。
  static int _compareTasksByAddedDesc(
      MagnetDownloadEntry a, MagnetDownloadEntry b) {
    final cmp = b.addedAt.compareTo(a.addedAt);
    if (cmp != 0) return cmp;
    return a.title.compareTo(b.title);
  }

  Widget _buildTaskTile(BuildContext context, MagnetDownloadEntry task,
      {bool grouped = false}) {
    return _DownloadTaskTile(
      task: task,
      grouped: grouped,
      onPause: () => widget.controller.pauseDownload(task.taskId),
      onResume: () => widget.controller.resumeDownload(task.taskId),
      onRemove: () => _confirmRemove(context, task),
      // 单文件种子没有「部分下载」的余地，不显示文件选择入口。
      onSelectFiles: task.totalLength > 0 && task.files.length != 1
          ? () => _showFileSelection(task)
          : null,
      onMatchAnime: task.scrapePending
          ? () => _showMatchAnimeDialog(context, task)
          : null,
      onRescrape: task.scrapePending
          ? () => widget.controller.rescrapeDownload(task.taskId)
          : null,
      onStream: task.files.any((f) => f.isStreamable)
          ? (task.hasCompleteFiles
              // 文件已完整落盘的任务（含做种中、完成后暂停 / 已停止等
              // 状态）一律走媒体库本地播放流程，不再提供边下边播；
              // 未完成任务才走引擎流式播放。
              ? () => _showCompletedPlayback(context, task)
              : () => _showStreamSelection(context, task))
          : null,
      onRetry: task.isError
          ? () => widget.controller.retryDownload(task.taskId)
          : null,
      onRecheck: (task.isActive || task.isPaused) && task.totalLength > 0
          ? () => _recheckTask(context, task)
          : null,
    );
  }

  /// 分组「缺集检测」：对比组内已下载集数与 Bangumi 正片集数，
  /// 点击缺失集数跳转磁力搜索补集。
  Future<void> _showGroupMissingEpisodes(
      BuildContext context, _DownloadGroup group) async {
    final bangumiId = group.bangumiId;
    if (bangumiId == null) return;
    final downloaded = <int>{};
    for (final task in group.tasks) {
      final selected = task.selectedFileIndexes?.toSet();
      if (task.importedPath.isNotEmpty) {
        // 已入库：文件被移入媒体库，原下载路径不再存在，所选文件视为已有。
        for (final file in task.files) {
          if (selected != null && !selected.contains(file.index)) continue;
          final ep = parseLocalEpisodeNumber(file.name);
          if (ep > 0) downloaded.add(ep);
        }
        continue;
      }
      for (final file in task.files) {
        if (selected != null && !selected.contains(file.index)) continue;
        final ep = parseLocalEpisodeNumber(file.name);
        if (ep <= 0) continue;
        // 只统计真实落盘的文件：种子文件清单 ≠ 已下载文件（全集包只勾选
        // 下载前几集时，全量清单会让「缺集检测」误报为无缺集）。
        final absolutePath = task.absolutePathFor(file);
        if (absolutePath == null || !File(absolutePath).existsSync()) {
          continue;
        }
        downloaded.add(ep);
      }
    }
    List<int> missing;
    try {
      final episodes = await BangumiApi.getBangumiEpisodesByID(bangumiId);
      final maxHave =
          downloaded.isEmpty ? 0 : downloaded.reduce((a, b) => a > b ? a : b);
      missing = [
        for (final e in episodes)
          if (e.type == 0 &&
              e.episode.toInt() > 0 &&
              !downloaded.contains(e.episode.toInt()) &&
              (maxHave == 0 || e.episode.toInt() <= maxHave + 12))
            e.episode.toInt(),
      ]..sort();
    } catch (e) {
      KazumiLogger()
          .w('MagnetDownloadsTab: missing episodes query failed', error: e);
      KazumiDialog.showToast(message: '获取集数信息失败，请检查网络');
      return;
    }
    if (!mounted || !context.mounted) return;
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('「${group.title}」缺集（${missing.length}）',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('点击集数前往磁力搜索补集', style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              if (missing.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text('未发现缺集'),
                    ],
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final ep in missing)
                          ActionChip(
                            label: Text('第$ep话'),
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              context.pushNamed(
                                '/magnet/',
                                arguments: MagnetSearchRouteArgs(
                                  query:
                                      '${group.title} ${ep.toString().padLeft(2, '0')}',
                                  anime: group.toBangumiItem(),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 清除全部已完成记录的确认对话框。
  Future<void> _confirmClearCompleted(BuildContext context) async {
    final theme = Theme.of(context);
    final confirmed = await KazumiDialog.show<bool>(
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除已完成记录'),
        content: Text(
          '将移除所有已完成任务的历史记录，磁盘上的文件会保留。',
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => KazumiDialog.dismiss(popWith: true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final count = await widget.controller.clearCompletedDownloads();
    if (mounted) {
      KazumiDialog.showToast(message: '已清除 $count 条已完成记录');
    }
  }

  /// 手动添加磁力链接 / .torrent（URL 或本地文件）。
  Future<void> _showAddMagnetDialog(BuildContext context) async {
    final linkCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    String? saveDir;
    KazumiDialog.show(
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final theme = Theme.of(dialogContext);
          return AlertDialog(
            title: const Text('手动添加下载'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: linkCtrl,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: '磁力链接 / 种子 URL / .torrent 路径',
                    hintText: 'magnet:?xt=urn:btih:...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '任务名称（可选）',
                    hintText: '留空则获取元数据后自动填充',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        saveDir == null ? '保存到默认下载目录' : '保存到：$saveDir',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.platform
                            .getDirectoryPath(dialogTitle: '选择保存目录');
                        if (picked != null) {
                          setDialogState(() => saveDir = picked);
                        }
                      },
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: const Text('选择目录'),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final link = linkCtrl.text.trim();
                  if (link.isEmpty) {
                    KazumiDialog.showToast(message: '请输入磁力链接或种子地址');
                    return;
                  }
                  Navigator.pop(dialogContext);
                  final item = MagnetSearchItem(
                    title: titleCtrl.text.trim().isEmpty
                        ? '手动添加的任务'
                        : titleCtrl.text.trim(),
                    magnetLink: link.startsWith('magnet:') ? link : '',
                    torrentUrl: link.startsWith('magnet:') ? '' : link,
                    size: '',
                    publishDate: DateTime.now(),
                  );
                  widget.controller.addDownload(item, dir: saveDir);
                },
                child: const Text('添加'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 删除任务确认，可选同时删除已下载文件。
  Future<void> _confirmRemove(
      BuildContext context, MagnetDownloadEntry task) async {
    var deleteFiles = false;
    KazumiDialog.show(
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('删除下载任务'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.title.isEmpty ? task.fileName : task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              if (task.importedPath.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.folder_open_rounded, size: 16),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '该任务文件已自动移入媒体库，删除任务不会影响已入库的文件。',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              CheckboxListTile(
                value: deleteFiles,
                onChanged: (v) =>
                    setDialogState(() => deleteFiles = v ?? false),
                title: const Text('同时删除已下载的文件'),
                subtitle: deleteFiles
                    ? const Text('将永久删除磁盘上的文件，不可恢复',
                        style: TextStyle(color: Colors.red))
                    : const Text('仅移除任务记录，文件保留在磁盘上'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: deleteFiles
                    ? Theme.of(dialogContext).colorScheme.error
                    : null,
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                widget.controller
                    .removeDownload(task.taskId, deleteFiles: deleteFiles);
              },
              child: Text(deleteFiles ? '删除任务和文件' : '删除任务'),
            ),
          ],
        ),
      ),
    );
  }

  /// 手动校验任务文件。
  Future<void> _recheckTask(
      BuildContext context, MagnetDownloadEntry task) async {
    final ok = await widget.controller.recheckDownload(task.taskId);
    if (!mounted) return;
    KazumiDialog.showToast(
      message: ok ? '已提交校验，请稍候查看进度' : '校验失败：任务未挂载到引擎',
    );
  }

  /// 「待确认」任务手动匹配番剧：搜索 Bangumi 并写入任务。
  Future<void> _showMatchAnimeDialog(
      BuildContext context, MagnetDownloadEntry task) async {
    final scraper = MediaScraper();
    final initial = scraper
        .cleanName(task.fileName.isNotEmpty ? task.fileName : task.title);
    final item = await showModalBottomSheet<BangumiItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MatchAnimeSheet(
        controller: widget.controller,
        initialKeyword: initial,
      ),
    );
    if (item == null || !mounted) return;
    await widget.controller.matchDownloadToBangumi(task.taskId, item);
  }

  /// 已完成任务播放：文件已完整落盘，直接走媒体库本地播放流程
  /// （应用内播放器 + 弹幕 + 历史续播 + Bangumi 进度联动）。
  /// 完成任务的引擎句柄已被移除（停止做种），引擎流不可用，
  /// 不能再走边下边播路径。
  Future<void> _showCompletedPlayback(
      BuildContext context, MagnetDownloadEntry task) async {
    final selected = task.selectedFileIndexes?.toSet();
    final playable = <LocalMediaFile>[];
    for (final file in task.files) {
      if (selected != null && !selected.contains(file.index)) continue;
      if (!isSupportedVideoFile(file.name)) continue;
      final absolutePath = task.absolutePathFor(file);
      if (absolutePath == null) continue;
      final diskFile = File(absolutePath);
      if (!diskFile.existsSync()) continue;
      final stat = diskFile.statSync();
      playable.add(LocalMediaFile(
        path: absolutePath,
        name: file.name,
        size: stat.size,
        modifiedAt: stat.modified,
      ));
    }
    final bangumiId = task.scrapeInfo?.bangumiId;
    if (playable.isEmpty && bangumiId != null && bangumiId > 0) {
      // 任务文件已入库（被移入媒体库）或被移动：原下载路径不存在，
      // 回退用媒体库中该番剧的文件播放。
      playable.addAll(inject<MediaController>().filesForBangumi(bangumiId));
    }
    if (playable.isEmpty) {
      KazumiDialog.showToast(message: '没有可播放的文件（可能已入库或文件被移动）');
      return;
    }
    LocalMediaFile target;
    if (playable.length == 1) {
      target = playable.first;
    } else {
      if (!context.mounted) return;
      final picked = await showModalBottomSheet<LocalMediaFile>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '选择要播放的文件',
                    style: Theme.of(sheetContext).textTheme.titleSmall,
                  ),
                ),
              ),
              ...playable.map(
                (f) => ListTile(
                  leading: const Icon(Icons.ondemand_video_rounded),
                  title:
                      Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(sheetContext, f),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (picked == null || !context.mounted) return;
      target = picked;
    }
    final info = task.scrapeInfo;
    final bangumiItem = info != null
        ? info.toBangumiItem()
        : _magnetPlaceholderBangumiItem(task);
    final playbackFiles = _mergeLibraryFilesForPlayback(playable, bangumiId);
    final index = playbackFiles.indexWhere((f) => f.path == target.path);
    if (!context.mounted) return;
    await context.pushNamed(
      '/video/',
      arguments: LocalMediaVideoPlaybackArgs(
        bangumiItem: bangumiItem,
        files: playbackFiles,
        selectedIndex: index < 0 ? 0 : index,
        // 与媒体库播放使用同一 adapter（'local'）：同一路径的播放历史
        // 互相续播，Bangumi 进度联动共用一条链路。
        pluginName: kLocalMediaAdapterName,
        bangumiSyncId: info?.bangumiId,
      ),
    );
  }

  /// 合并本地媒体库中同番剧的文件作为播放选集列表（按路径去重，
  /// 按文件名解析出的集数排序）。
  ///
  /// 磁力任务里可能只下载了某几集，而媒体库中已有该番剧的其他集数；
  /// 只传任务自身文件会让播放器选集面板看不到媒体库里的其他文件。
  List<LocalMediaFile> _mergeLibraryFilesForPlayback(
      List<LocalMediaFile> taskFiles, int? bangumiId) {
    if (bangumiId == null || bangumiId <= 0) return taskFiles;
    final libraryFiles = inject<MediaController>().filesForBangumi(bangumiId);
    if (libraryFiles.isEmpty) return taskFiles;
    final byPath = <String, LocalMediaFile>{
      for (final f in taskFiles) f.path: f,
    };
    for (final file in libraryFiles) {
      byPath.putIfAbsent(file.path, () => file);
    }
    final merged = byPath.values.toList()
      ..sort((a, b) {
        final epA = parseLocalEpisodeNumber(a.name);
        final epB = parseLocalEpisodeNumber(b.name);
        if (epA != epB) return epA.compareTo(epB);
        return a.name.compareTo(b.name);
      });
    return merged;
  }

  /// 边下边播：选择种子内可流式播放的文件，启动引擎流后跳转播放页。
  Future<void> _showStreamSelection(
      BuildContext context, MagnetDownloadEntry task) async {
    final files = await widget.controller.listDownloadFiles(task.taskId);
    if (!context.mounted) return;
    final streamable = files.where((f) => f.isStreamable).toList();
    if (streamable.isEmpty) {
      KazumiDialog.showToast(message: '没有可流式播放的文件（元数据可能未就绪）');
      return;
    }
    FileInfo target;
    if (streamable.length == 1) {
      target = streamable.first;
    } else {
      final picked = await showModalBottomSheet<FileInfo>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '选择要边下边播的文件',
                    style: Theme.of(sheetContext).textTheme.titleSmall,
                  ),
                ),
              ),
              ...streamable.map(
                (f) => ListTile(
                  leading: const Icon(Icons.ondemand_video_rounded),
                  title: Text(f.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(sheetContext, f),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (picked == null || !context.mounted) return;
      target = picked;
    }
    final url = await widget.controller.startStream(task.taskId, target.index);
    if (!context.mounted) return;
    if (url == null) {
      KazumiDialog.showToast(message: '启动边下边播失败，请检查引擎状态');
      return;
    }
    final bangumiItem = task.scrapeInfo != null
        ? task.scrapeInfo!.toBangumiItem()
        : _magnetPlaceholderBangumiItem(task);
    await context.pushNamed(
      '/video/',
      arguments: MagnetStreamVideoPlaybackArgs(
        bangumiItem: bangumiItem,
        streamUrl: url,
        fileName: target.name,
      ),
    );
    // 播放页退出后停止该任务的流服务器（HTTP 端口 / 预读缓存随之释放），
    // 否则每个流会话永久驻留直至任务删除。
    if (context.mounted) {
      widget.controller.stopStreams(task.taskId);
    }
  }

  /// 未搜刮任务边下边播时使用的占位 BangumiItem：
  /// 负值哈希 ID 保证不触发 Bangumi 远端查询，仍可按标题检索弹幕。
  BangumiItem _magnetPlaceholderBangumiItem(MagnetDownloadEntry task) {
    final name = task.title.isNotEmpty ? task.title : task.fileName;
    var h = 0;
    for (final code in name.codeUnits) {
      h = (h * 31 + code) & 0x7FFFFFFF;
    }
    final id = h == 0 ? -1 : -h;
    return BangumiItem(
      id: id,
      type: 2,
      name: name,
      nameCn: name,
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: {
        'large': '',
        'common': '',
        'medium': '',
        'small': '',
        'grid': '',
      },
      tags: const [],
      alias: const [],
      ratingScore: 0,
      votes: 0,
      votesCount: const [],
      info: '',
    );
  }

  /// 文件选择（部分下载）底部面板。
  Future<void> _showFileSelection(MagnetDownloadEntry task) async {
    final files = await widget.controller.listDownloadFiles(task.taskId);
    if (!mounted) return;
    if (files.isEmpty) {
      KazumiDialog.showToast(message: '元数据尚未就绪，无法列出文件');
      return;
    }
    final initial = task.selectedFileIndexes?.toSet() ??
        {for (var i = 0; i < files.length; i++) i};
    var selected = Set<int>.from(initial);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final theme = Theme.of(sheetContext);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '选择下载文件（${selected.length}/${files.length}）',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () => setSheetState(() {
                            selected = selected.length == files.length
                                ? {}
                                : {for (var i = 0; i < files.length; i++) i};
                          }),
                          child: Text(
                            selected.length == files.length ? '全不选' : '全选',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final file = files[index];
                        final checked = selected.contains(index);
                        return CheckboxListTile(
                          dense: true,
                          value: checked,
                          onChanged: (v) => setSheetState(() {
                            if (v ?? false) {
                              selected.add(index);
                            } else {
                              selected.remove(index);
                            }
                          }),
                          title: Text(
                            file.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          subtitle: Text(
                            _formatBytes(file.size),
                            style: theme.textTheme.bodySmall,
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () {
                                  Navigator.pop(sheetContext);
                                  widget.controller.setDownloadFileSelection(
                                      task.taskId, selected.toList()..sort());
                                },
                          child: const Text('应用选择'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 一个按番剧聚合的下载任务分组。
class _DownloadGroup {
  _DownloadGroup({
    required this.title,
    required this.coverUrl,
    required this.bangumiId,
    required this.tasks,
  });

  final String title;
  final String coverUrl;
  final int? bangumiId;
  final List<MagnetDownloadEntry> tasks;

  /// 分组添加时间：以组内最早的任务添加时间为准（该任务创建了分组）。
  DateTime get groupAddedAt => tasks
      .map((t) => t.addedAt)
      .reduce((a, b) => a.isBefore(b) ? a : b);

  /// 分组的稳定键（用于 State 复用与折叠状态记忆）。
  String get key =>
      bangumiId != null ? 'bgm:$bangumiId' : 'raw:${title.toLowerCase()}';

  int get count => tasks.length;

  bool get hasActive =>
      tasks.any((t) => t.isDownloading || t.isQueued || t.isSeeding);

  BangumiItem? toBangumiItem() {
    for (final task in tasks) {
      final info = task.scrapeInfo;
      if (info != null) return info.toBangumiItem();
    }
    return null;
  }
}

/// 分组头部 + 折叠的任务条目列表。
class _DownloadGroupSection extends StatefulWidget {
  const _DownloadGroupSection({
    super.key,
    required this.group,
    required this.buildTaskTile,
    required this.onMissingEpisodes,
  });

  final _DownloadGroup group;
  final Widget Function(BuildContext context, MagnetDownloadEntry task,
      {bool grouped}) buildTaskTile;

  /// 点击「缺集」时触发（由外层 Tab 执行 Bangumi 查询与跳转）。
  final void Function(_DownloadGroup group) onMissingEpisodes;

  @override
  State<_DownloadGroupSection> createState() => _DownloadGroupSectionState();
}

class _DownloadGroupSectionState extends State<_DownloadGroupSection> {
  late bool _expanded = widget.group.hasActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = widget.group;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          onTap: () => setState(() => _expanded = !_expanded),
          leading: group.coverUrl.isNotEmpty
              ? SizedBox(
                  width: 36,
                  height: 50,
                  child: NetworkImgLayer(
                      src: group.coverUrl, width: 36, height: 50),
                )
              : const Icon(Icons.movie_outlined),
          title: Text(
            group.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          subtitle: Text(
            '${group.count} 个任务',
            style: theme.textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (group.bangumiId != null)
                TextButton(
                  onPressed: () => widget.onMissingEpisodes(group),
                  child: const Text('缺集'),
                ),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              children: [
                for (final task in group.tasks)
                  widget.buildTaskTile(context, task, grouped: true),
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

/// 「待确认」下载任务的手动匹配面板：搜索 Bangumi 番剧并返回选中条目。
class _MatchAnimeSheet extends StatefulWidget {
  const _MatchAnimeSheet({
    required this.controller,
    required this.initialKeyword,
  });

  final MagnetController controller;
  final String initialKeyword;

  @override
  State<_MatchAnimeSheet> createState() => _MatchAnimeSheetState();
}

class _MatchAnimeSheetState extends State<_MatchAnimeSheet> {
  late final TextEditingController _keywordCtrl;
  List<BangumiItem> _results = const [];
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _keywordCtrl = TextEditingController(text: widget.initialKeyword);
    _search();
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _keywordCtrl.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    final items = await widget.controller.searchBangumi(keyword);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = items;
      if (items.isEmpty) {
        _error = '没有找到相关番剧，试试更换关键词';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('匹配番剧', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _keywordCtrl,
                      decoration: const InputDecoration(
                        hintText: '搜索番剧关键词',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _searching ? null : _search,
                    icon: const Icon(Icons.search_rounded),
                    tooltip: '搜索',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            _error ?? '输入关键词搜索 Bangumi',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = _results[index];
                            final cover =
                                item.images['large'] ?? item.images['common'];
                            return ListTile(
                              onTap: () => Navigator.pop(context, item),
                              leading: (cover != null && cover.isNotEmpty)
                                  ? SizedBox(
                                      width: 36,
                                      height: 48,
                                      child: NetworkImgLayer(
                                        src: cover,
                                        width: 36,
                                        height: 48,
                                      ),
                                    )
                                  : null,
                              title: Text(
                                item.nameCn.isNotEmpty
                                    ? item.nameCn
                                    : item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: item.airDate.isNotEmpty
                                  ? Text(item.airDate)
                                  : null,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onRemove,
    this.grouped = false,
    this.onSelectFiles,
    this.onMatchAnime,
    this.onRescrape,
    this.onStream,
    this.onRetry,
    this.onRecheck,
  });

  final MagnetDownloadEntry task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRemove;

  /// 按番剧分组展示时的子条目：组头已展示封面与番剧名，子条目不再
  /// 重复（标题改用文件名 / 任务名以便区分集数，隐藏「已搜刮」标记）。
  final bool grouped;

  /// 元数据就绪后可用的「选择下载文件」回调。
  final VoidCallback? onSelectFiles;

  /// 「待确认」任务可用的「匹配番剧」回调。
  final VoidCallback? onMatchAnime;

  /// 「待确认」任务可用的「重新搜刮」回调。
  final VoidCallback? onRescrape;

  /// 元数据就绪后可用的「边下边播」回调。
  final VoidCallback? onStream;

  /// 错误任务可用的「重试」回调。
  final VoidCallback? onRetry;

  /// 元数据就绪后可用的「校验文件」回调。
  final VoidCallback? onRecheck;

  void _openAnimePage(BuildContext context) {
    final info = task.scrapeInfo;
    if (info == null) return;
    context.pushNamed('/info/', arguments: info.toBangumiItem());
  }

  /// 任务所选文件覆盖的集数范围（如「第 1 集」「第 1-12 集」）。
  ///
  /// 已搜刮任务的标题统一显示番剧名，按番剧分组时各条目无法区分集数，
  /// 用文件名解析出的集数范围作为标识；解析不出集数返回 null。
  String? _episodeRangeLabel() {
    final selected = task.selectedFileIndexes?.toSet();
    final episodes = <int>{};
    for (final file in task.files) {
      if (selected != null && !selected.contains(file.index)) continue;
      final ep = parseLocalEpisodeNumber(file.name);
      if (ep > 0) episodes.add(ep);
    }
    if (episodes.isEmpty) return null;
    final sorted = episodes.toList()..sort();
    return sorted.length == 1
        ? '第 ${sorted.first} 集'
        : '第 ${sorted.first}-${sorted.last} 集';
  }

  List<PopupMenuEntry<String>> _menuItems() => [
        if (onStream != null)
          PopupMenuItem(
            value: 'stream',
            child: Text(task.hasCompleteFiles ? '播放' : '边下边播'),
          ),
        if (task.isActive)
          const PopupMenuItem(value: 'pause', child: Text('暂停')),
        if (task.isPaused)
          const PopupMenuItem(value: 'resume', child: Text('继续')),
        if (task.isQueued)
          const PopupMenuItem(value: 'resume', child: Text('立即开始')),
        if (task.isError)
          const PopupMenuItem(value: 'retry', child: Text('重试')),
        if (onRecheck != null)
          const PopupMenuItem(value: 'recheck', child: Text('校验文件')),
        if (onSelectFiles != null)
          const PopupMenuItem(value: 'files', child: Text('选择下载文件')),
        if (onMatchAnime != null)
          const PopupMenuItem(value: 'match', child: Text('匹配番剧')),
        if (onRescrape != null)
          const PopupMenuItem(value: 'rescrape', child: Text('重新搜刮')),
        const PopupMenuItem(value: 'remove', child: Text('删除')),
      ];

  void _onMenuSelected(String value) {
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
      case 'files':
        onSelectFiles?.call();
        break;
      case 'match':
        onMatchAnime?.call();
        break;
      case 'rescrape':
        onRescrape?.call();
        break;
      case 'stream':
        onStream?.call();
        break;
      case 'retry':
        onRetry?.call();
        break;
      case 'recheck':
        onRecheck?.call();
        break;
    }
  }

  /// 右键（Windows）在光标处弹出与「⋯」按钮一致的操作菜单。
  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlay.globalToLocal(position);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy,
        overlay.size.width - local.dx,
        overlay.size.height - local.dy,
      ),
      items: _menuItems(),
    );
    if (value != null) {
      _onMenuSelected(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = task.progress;
    final info = task.scrapeInfo;
    // 分组子条目：番剧名在组头已展示，这里用文件名（含集数，最能区分
    // 各条目）/ 任务名作为标题；未分组时维持「番剧名 → 任务名 → 文件名」。
    final displayTitle = grouped
        ? (task.fileName.isNotEmpty ? task.fileName : task.title)
        : ((info != null && info.displayName.isNotEmpty)
            ? info.displayName
            : task.title);
    final episodeRange = _episodeRangeLabel();
    return GestureDetector(
      // 右键任务条目也能展开操作菜单（Windows 桌面端）。
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        // 已搜刮的任务可直接跳转番剧详情页。
        onTap: info == null ? null : () => _openAnimePage(context),
        // 分组子条目不显示封面（组头已有）。
        leading: !grouped && info != null && info.coverUrl.isNotEmpty
            ? SizedBox(
                width: 44,
                height: 60,
                child:
                    NetworkImgLayer(src: info.coverUrl, width: 44, height: 60),
              )
            : null,
        title: Row(
          children: [
            Expanded(
              child: Text(
                displayTitle.isEmpty ? task.fileName : displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (episodeRange != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  episodeRange,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.secondary),
                ),
              ),
            ],
            // 分组子条目的组头已表明番剧归属，不再显示「已搜刮」标记；
            // 「待确认」「已入库」仍保留（有独立信息量）。
            if (!grouped && task.isScraped) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '已搜刮',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
            ] else if (task.scrapePending) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '待确认',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.tertiary),
                ),
              ),
            ],
            if (task.importedPath.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '已入库',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
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
                      if (task.numSeeds + task.numPeers > 0 &&
                          !task.isCompleted)
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
          onSelected: _onMenuSelected,
          itemBuilder: (context) => _menuItems(),
        ),
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
      'queued' => ('排队中', theme.colorScheme.tertiary),
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

    var sub = MagnetSubscription(
      id: widget.existing?.id ?? '',
      name: _nameCtrl.text.trim(),
      feedUrl: _feedCtrl.text.trim(),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      kind: _kind,
      fansub: _fansub,
      keywords:
          _keywordsCtrl.text.trim().isEmpty ? null : _keywordsCtrl.text.trim(),
      since: _since,
      minSizeMb: parseMb(_minSizeCtrl.text),
      maxSizeMb: parseMb(_maxSizeCtrl.text),
      downloadPath:
          _pathCtrl.text.trim().isEmpty ? null : _pathCtrl.text.trim(),
      coverUrl: widget.existing?.coverUrl ?? '',
    );
    if (sub.coverUrl.isEmpty) {
      final cover = await _resolveCover(sub);
      if (cover != null) sub = sub.copyWith(coverUrl: cover);
    }
    if (widget.existing == null) {
      await widget.controller.addSubscription(sub);
    } else {
      await widget.controller.updateSubscription(sub);
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// 通过 Bangumi 搜索解析订阅的番剧封面，失败时返回 null。
  Future<String?> _resolveCover(MagnetSubscription sub) async {
    final keyword = sub.name.isNotEmpty ? sub.name : sub.feedUrl;
    if (keyword.isEmpty) return null;
    try {
      final page = await BangumiApi.bangumiSearch(keyword, limit: 5);
      if (page == null || page.items.isEmpty) return null;
      final item = page.items.first;
      final cover = item.images['large'] ?? item.images['common'] ?? '';
      return cover.isEmpty ? null : cover;
    } catch (e) {
      KazumiLogger().w('MagnetSubscription: resolve cover failed', error: e);
      return null;
    }
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
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('保存'),
              ),
            ),
          ),
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
                                      ? const Icon(Icons.check_rounded,
                                          size: 20)
                                      : null,
                                  onTap: () => Navigator.pop(innerCtx, t.name),
                                )),
                        if (searchCtrl.text.trim().isNotEmpty &&
                            !_teams
                                .any((t) => t.name == searchCtrl.text.trim()))
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
