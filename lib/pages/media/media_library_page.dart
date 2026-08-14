import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart' show GeneralEmptyState;
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart' show kLocalMediaAdapterName;
import 'package:kazumi/pages/magnet/magnet_page.dart' show MagnetSearchRouteArgs;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/utils/local_episode_parser.dart';
import 'package:kazumi/utils/file_system.dart' show revealInFileManager;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

/// 未搜刮到番剧时，从文件名/所在目录名推断一个尽量干净的标题，
/// 作为弹幕标题检索的兜底关键词。
String _inferLocalTitle(LocalMediaFile file) {
  final fromFile = sanitizeAnimeTitle(file.name);
  if (fromFile.length >= 2) return fromFile;
  final folderName = p.basename(p.dirname(file.path));
  final fromFolder = sanitizeAnimeTitle(folderName);
  if (fromFolder.length >= 2) return fromFolder;
  return folderName.isNotEmpty ? folderName : file.name;
}

/// 未匹配番剧时使用的占位 BangumiItem。
/// 此时 BGM ID 映射不可用，但仍可通过文件哈希匹配与标题检索加载弹幕。
///
/// id 使用标题的稳定负值哈希：避免所有未匹配番剧共用 id=0 导致历史记录
/// 与续播进度互相覆盖（负值同时保证不会误触发 Bangumi 相关查询）。
BangumiItem _placeholderBangumiItem(String name) => BangumiItem(
      id: _placeholderIdFor(name),
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
        'grid': ''
      },
      tags: const [],
      alias: const [],
      ratingScore: 0,
      votes: 0,
      votesCount: const [],
      info: '',
    );

int _placeholderIdFor(String name) {
  var h = 0;
  for (final code in name.codeUnits) {
    h = (h * 31 + code) & 0x7FFFFFFF;
  }
  return h == 0 ? -1 : -h;
}

class MediaLibraryPage extends StatefulWidget {
  const MediaLibraryPage({super.key, required this.controller});

  final MediaController controller;

  @override
  State<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<MediaLibraryPage> {
  MediaController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('本地媒体库'),
        actions: [
          // 视图切换
          _ViewModeToggle(controller: controller),
          // 排序（仅番剧 / 网格视图有意义）
          _SortMenu(controller: controller),
          IconButton(
            tooltip: '扫描',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: controller.isScanning ? null : () => controller.scan(),
          ),
          IconButton(
            tooltip: '搜刮元数据',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: controller.isScraping
                ? null
                : () => _confirmScrape(context),
          ),
          IconButton(
            tooltip: '文件夹管理',
            icon: const Icon(Icons.folder_open_rounded),
            onPressed: () => _showFolderManager(context),
          ),
        ],
      ),
      body: Observer(builder: (_) {
        if (controller.isScanning && controller.library.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.folders.isEmpty) {
          return Center(
            child: GeneralEmptyState(
              icon: Icons.folder_off_rounded,
              title: '尚未添加任何文件夹\n点击右上角添加本地视频目录',
            ),
          );
        }
        if (controller.library.isEmpty) {
          return Center(
            child: GeneralEmptyState(
              icon: Icons.video_library_outlined,
              title: '所选文件夹中没有发现视频文件',
            ),
          );
        }
        if (controller.isGridMode) {
          return _GridView(controller: controller, onFileTap: _playFile);
        }
        return controller.isAnimeMode
            ? _AnimeView(controller: controller, onFileTap: _playFile)
            : _FolderView(controller: controller, onFileTap: _playFile);
      }),
      bottomNavigationBar: _ScrapeProgressBar(controller: controller),
    );
  }

  Future<void> _playFile(
    LocalMediaFile file,
    List<LocalMediaFile> siblings,
    MediaScrapeInfo? info,
  ) async {
    // 仅 Windows 端改为应用内播放（与在线播放一致并关联弹幕），其余平台保持系统默认播放器
    if (!Platform.isWindows) {
      try {
        final result = await OpenFilex.open(file.path);
        if (result.type != ResultType.done) {
          KazumiDialog.showToast(message: '无法播放：${result.message}');
        }
      } catch (e) {
        KazumiDialog.showToast(message: '打开文件失败：$e');
      }
      return;
    }
    final bangumiItem = info != null
        ? info.toBangumiItem()
        : _placeholderBangumiItem(_inferLocalTitle(file));
    final int index = siblings.indexWhere((f) => f.path == file.path);
    final args = LocalMediaVideoPlaybackArgs(
      bangumiItem: bangumiItem,
      files: siblings,
      selectedIndex: index < 0 ? 0 : index,
      pluginName: kLocalMediaAdapterName,
      bangumiSyncId: info?.bangumiId,
    );
    if (!context.mounted) return;
    context.pushNamed('/video/', arguments: args);
  }

  void _confirmScrape(BuildContext context) {
    final total = controller.library.length;
    final unmatched = controller.unmatchedCount;
    var onlyUnmatched = controller.scrapeOnlyUnmatched;

    KazumiDialog.show(
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final targetCount = onlyUnmatched ? unmatched : total;
          final canStart = targetCount > 0;
          return AlertDialog(
            title: const Text('搜刮番剧元数据'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('将根据文件夹名称自动搜索 Bangumi 匹配番剧信息，可能需要一些时间。'),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '共 $total 个文件夹 · 已匹配 ${total - unmatched} · 未匹配 $unmatched',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  value: onlyUnmatched,
                  onChanged: (value) {
                    final next = value ?? false;
                    setDialogState(() => onlyUnmatched = next);
                    controller.setScrapeOnlyUnmatched(next);
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: const Text('仅搜刮未匹配的番剧'),
                  subtitle: Text(
                    onlyUnmatched
                        ? '跳过已匹配的 ${total - unmatched} 个文件夹，保留其现有结果'
                        : '重新搜刮全部 $total 个文件夹，已有匹配可能被覆盖',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onlyUnmatched
                          ? theme.colorScheme.outline
                          : theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => KazumiDialog.dismiss(),
                child: Text(
                  '取消',
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              ),
              TextButton(
                onPressed: canStart
                    ? () {
                        controller.scrapeAll(onlyUnmatched: onlyUnmatched);
                        KazumiDialog.dismiss();
                      }
                    : null,
                child: Text(
                  canStart ? '开始搜刮（$targetCount）' : '无待搜刮项',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFolderManager(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _FolderManagerSheet(
          controller: controller,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

// ============ 视图切换 ============

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.controller});

  final MediaController controller;

  IconData _iconFor(String mode) => switch (mode) {
        'grid' => Icons.grid_view_rounded,
        'anime' => Icons.movie_outlined,
        _ => Icons.folder_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      final current = controller.viewMode;
      return PopupMenuButton<String>(
        tooltip: '视图模式',
        icon: Icon(_iconFor(current)),
        onSelected: (mode) => controller.setViewMode(mode),
        itemBuilder: (_) => [
          for (final entry in const [
            ('folder', '按文件夹', Icons.folder_outlined),
            ('anime', '按番剧', Icons.movie_outlined),
            ('grid', '网格', Icons.grid_view_rounded),
          ])
            PopupMenuItem(
              value: entry.$1,
              child: Row(
                children: [
                  Icon(entry.$3, size: 20),
                  const SizedBox(width: 12),
                  Text(entry.$2),
                  if (current == entry.$1) ...[
                    const Spacer(),
                    const Icon(Icons.check_rounded, size: 18),
                  ],
                ],
              ),
            ),
        ],
      );
    });
  }
}

// ============ 排序菜单 ============

/// 番剧 / 网格视图的排序控制：依据 + 方向。
///
/// 文件夹视图按磁盘扫描顺序展示，排序无意义，直接隐藏。
class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.controller});

  final MediaController controller;

  static const _modes = [
    ('date', '按番剧日期'),
    ('name', '按标题'),
    ('count', '按文件数'),
  ];

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      if (!controller.isAnimeMode && !controller.isGridMode) {
        return const SizedBox.shrink();
      }
      final current = controller.sortMode;
      final desc = controller.sortDescending;
      return PopupMenuButton<String>(
        tooltip: '排序方式',
        icon: const Icon(Icons.sort_rounded),
        onSelected: (value) {
          if (value == '__direction__') {
            controller.setSortDescending(!desc);
          } else {
            controller.setSortMode(value);
          }
        },
        itemBuilder: (_) => [
          for (final entry in _modes)
            PopupMenuItem(
              value: entry.$1,
              child: Row(
                children: [
                  Text(entry.$2),
                  if (current == entry.$1) ...[
                    const Spacer(),
                    const Icon(Icons.check_rounded, size: 18),
                  ],
                ],
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: '__direction__',
            child: Row(
              children: [
                Icon(
                  desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Text(desc ? '降序（最新在前）' : '升序（最早在前）'),
              ],
            ),
          ),
        ],
      );
    });
  }
}

// ============ 文件夹视图 ============

class _FolderView extends StatelessWidget {
  const _FolderView({required this.controller, required this.onFileTap});

  final MediaController controller;
  final Future<void> Function(LocalMediaFile, List<LocalMediaFile>, MediaScrapeInfo?)
      onFileTap;

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _StatsBar(controller: controller)),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _FolderSection(
                controller: controller,
                folder: controller.library[index],
                onFileTap: onFileTap,
              ),
              childCount: controller.library.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      );
    });
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.controller});

  final MediaController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            controller.isGridMode
                ? '共 ${controller.gridItems.length} 项 · ${controller.totalFiles} 个视频'
                : '共 ${controller.library.length} 个文件夹，${controller.totalFiles} 个视频',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          if (controller.isScanning)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

// ============ 搜刮进度条 ============

/// 搜刮时固定在页面底部的进度条，展示当前进度与搜刮信息。
class _ScrapeProgressBar extends StatelessWidget {
  const _ScrapeProgressBar({required this.controller});

  final MediaController controller;

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      if (!controller.isScraping) {
        return const SizedBox.shrink();
      }
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final total = controller.scrapeTotal;
      final done = controller.scrapeDone;
      final progress = total > 0
          ? (done / total).clamp(0.0, 1.0)
          : null;
      return Material(
        color: colorScheme.surfaceContainer,
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '正在搜刮 $done/$total',
                            style: theme.textTheme.titleSmall,
                          ),
                          if (controller.scrapeCurrentName.isNotEmpty)
                            Text(
                              controller.scrapeCurrentName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '匹配 ${controller.scrapeMatched} · 未找到 ${controller.scrapeFailed}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: '取消搜刮',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => controller.cancelScrape(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _FolderSection extends StatefulWidget {
  const _FolderSection({
    required this.controller,
    required this.folder,
    required this.onFileTap,
  });

  final MediaController controller;
  final LocalMediaFolder folder;
  final Future<void> Function(LocalMediaFile, List<LocalMediaFile>, MediaScrapeInfo?)
      onFileTap;

  @override
  State<_FolderSection> createState() => _FolderSectionState();
}

class _FolderSectionState extends State<_FolderSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folder = widget.folder;
    final info = widget.controller.getScrapeInfo(folder.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.folder_rounded),
          title: Text(
            info?.displayName ?? folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          subtitle: Text(
            '${folder.count} 个文件 · ${folder.path}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (info != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Chip(
                    label: Text(
                      '已匹配',
                      style: theme.textTheme.labelSmall,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) =>
                    _handleFolderAction(value, folder, info),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'match',
                    child: Text('手动匹配番剧'),
                  ),
                  if (info != null)
                    const PopupMenuItem(
                      value: 'clear',
                      child: Text('清除匹配'),
                    ),
                ],
              ),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            ],
          ),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              children: [
                for (final file in folder.files)
                  _FileTile(
                    file: file,
                    onTap: () => widget.onFileTap(
                      file,
                      folder.files,
                      widget.controller.getScrapeInfo(folder.path),
                    ),
                    onMenu: () => _showFileMenu(file),
                  ),
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }

  void _handleFolderAction(
    String action,
    LocalMediaFolder folder,
    MediaScrapeInfo? info,
  ) {
    if (action == 'match') {
      _showManualMatchDialog(context, folder);
    } else if (action == 'clear') {
      widget.controller.removeScrapeResult(folder.path);
    }
  }

  void _showFileMenu(LocalMediaFile file) {
    _showFileActionSheet(
      context,
      widget.controller,
      file,
      widget.folder.files,
      widget.controller.getScrapeInfo(widget.folder.path),
      onPlay: widget.onFileTap,
    );
  }

  void _showManualMatchDialog(BuildContext context, LocalMediaFolder folder) {
    showDialog<void>(
      context: context,
      builder: (_) => _ManualMatchDialog(
        controller: widget.controller,
        folder: folder,
      ),
    );
  }
}

// ============ 番剧视图 ============

class _AnimeView extends StatelessWidget {
  const _AnimeView({required this.controller, required this.onFileTap});

  final MediaController controller;
  final Future<void> Function(LocalMediaFile, List<LocalMediaFile>, MediaScrapeInfo?)
      onFileTap;

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      final groups = controller.animeGroups;
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _StatsBar(controller: controller)),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _AnimeGroupSection(
                controller: controller,
                group: groups[index],
                onFileTap: onFileTap,
              ),
              childCount: groups.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      );
    });
  }
}

class _AnimeGroupSection extends StatefulWidget {
  const _AnimeGroupSection({
    required this.controller,
    required this.group,
    required this.onFileTap,
  });

  final MediaController controller;
  final AnimeGroup group;
  final Future<void> Function(LocalMediaFile, List<LocalMediaFile>, MediaScrapeInfo?)
      onFileTap;

  @override
  State<_AnimeGroupSection> createState() => _AnimeGroupSectionState();
}

class _AnimeGroupSectionState extends State<_AnimeGroupSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = widget.group;
    final info = group.info;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 封面
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 56,
                    height: 78,
                    child: info != null && info.coverUrl.isNotEmpty
                        ? NetworkImgLayer(
                            src: info.coverUrl,
                            width: 56,
                            height: 78,
                          )
                        : Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.movie_outlined, size: 28),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                // 标题信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info?.displayName ?? '未匹配',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.fileCount} 个文件 · ${group.folders.length} 个文件夹',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (info != null && info.airDate.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            info.airDate,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                if (info != null && info.bangumiId != null)
                  TextButton(
                    onPressed: () => context.pushNamed(
                      '/info/',
                      arguments: info.toBangumiItem(),
                    ),
                    child: const Text('详情'),
                  ),
                if (info != null && info.bangumiId != null)
                  TextButton(
                    onPressed: () =>
                        _showMissingEpisodesSheet(context, widget.controller, group),
                    child: const Text('缺集'),
                  ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              children: [
                for (final folder in group.folders) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4, bottom: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_outlined, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                        if (info == null)
                          TextButton(
                            onPressed: () => _showManualMatchDialog(folder),
                            child: const Text('匹配'),
                          ),
                      ],
                    ),
                  ),
                  for (final file in folder.files)
                    _FileTile(
                      file: file,
                      onTap: () => widget.onFileTap(
                        file,
                        folder.files,
                        group.info,
                      ),
                      onMenu: () => _showFileActionSheet(
                        context,
                        widget.controller,
                        file,
                        folder.files,
                        group.info,
                        onPlay: widget.onFileTap,
                      ),
                    ),
                ],
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }

  void _showManualMatchDialog(LocalMediaFolder folder) {
    showDialog<void>(
      context: context,
      builder: (_) => _ManualMatchDialog(
        controller: widget.controller,
        folder: folder,
      ),
    );
  }
}

// ============ 网格视图 ============

class _GridView extends StatelessWidget {
  const _GridView({required this.controller, required this.onFileTap});

  final MediaController controller;
  final Future<void> Function(LocalMediaFile, List<LocalMediaFile>, MediaScrapeInfo?)
      onFileTap;

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      final items = controller.gridItems;
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _StatsBar(controller: controller)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverGrid.builder(
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                // 桌面宽屏下自动铺满，窄屏至少两列
                maxCrossAxisExtent: 168,
                mainAxisSpacing: 16,
                crossAxisSpacing: 14,
                childAspectRatio: 0.56,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => _GridCard(
                item: items[index],
                onTap: () => _showGridItemSheet(
                  context,
                  controller,
                  items[index],
                  onFileTap,
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// 网格海报卡片：悬停时轻微上浮放大，桌面端手感更接近原生媒体库应用。
class _GridCard extends StatefulWidget {
  const _GridCard({required this.item, required this.onTap});

  final MediaGridItem item;
  final VoidCallback onTap;

  @override
  State<_GridCard> createState() => _GridCardState();
}

class _GridCardState extends State<_GridCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final item = widget.item;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final h = constraints.maxHeight;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _hovered
                              ? [
                                  BoxShadow(
                                    color: colorScheme.shadow
                                        .withValues(alpha: 0.28),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ]
                              : null,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (item.coverUrl.isNotEmpty)
                              NetworkImgLayer(
                                src: item.coverUrl,
                                width: w,
                                height: h,
                              )
                            else
                              Container(
                                color: colorScheme.surfaceContainerHighest,
                                alignment: Alignment.center,
                                child: Icon(
                                  item.isMatched
                                      ? Icons.movie_outlined
                                      : Icons.help_outline_rounded,
                                  size: 34,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            // 底部渐变，保证角标与文字在浅色封面上依然可读
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: h * 0.4,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.62),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // 集数角标
                            Positioned(
                              right: 6,
                              top: 6,
                              child: _Badge(
                                text: '${item.fileCount}',
                                background:
                                    colorScheme.primary.withValues(alpha: 0.92),
                                foreground: colorScheme.onPrimary,
                              ),
                            ),
                            if (!item.isMatched)
                              Positioned(
                                left: 6,
                                top: 6,
                                child: _Badge(
                                  text: '未匹配',
                                  background:
                                      colorScheme.error.withValues(alpha: 0.92),
                                  foreground: colorScheme.onError,
                                ),
                              ),
                            if (item.airDate.isNotEmpty)
                              Positioned(
                                left: 8,
                                right: 8,
                                bottom: 6,
                                child: Text(
                                  item.airDate,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: _hovered ? colorScheme.primary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
      ),
    );
  }
}

/// 点击网格卡片后弹出的剧集列表。
/// 缺失集数检测底部面板：对比本地集数与 Bangumi 正片集数，
/// 点击缺失集数跳转磁力搜索（携带番剧信息，下载任务自动关联）。
Future<void> _showMissingEpisodesSheet(
  BuildContext context,
  MediaController controller,
  AnimeGroup group,
) async {
  final info = group.info;
  if (info == null) return;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final future = () async {
        final set = <int>{};
        for (final folder in group.folders) {
          set.addAll(await controller.detectMissingEpisodes(folder.path));
        }
        return set.toList()..sort();
      }();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: FutureBuilder<List<int>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final missing = snapshot.data ?? const <int>[];
            if (missing.isEmpty) {
              return SizedBox(
                height: 160,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        size: 40, color: theme.colorScheme.primary),
                    const SizedBox(height: 8),
                    const Text('未发现缺集'),
                    const SizedBox(height: 4),
                    Text(
                      '本地集数完整，或无法从 Bangumi 获取集数信息',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '「${info.displayName}」缺集（${missing.length}）',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '点击集数前往磁力搜索补集',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
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
                                  query: '${info.displayName} ${ep.toString().padLeft(2, '0')}',
                                  anime: info.toBangumiItem(),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

void _showGridItemSheet(
  BuildContext context,
  MediaController controller,
  MediaGridItem item,
  Future<void> Function(LocalMediaFile, List<LocalMediaFile>, MediaScrapeInfo?)
      onFileTap,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        final theme = Theme.of(context);
        final multiFolder = item.folders.length > 1;
        return CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 56,
                        height: 78,
                        child: item.coverUrl.isNotEmpty
                            ? NetworkImgLayer(
                                src: item.coverUrl,
                                width: 56,
                                height: 78,
                              )
                            : Container(
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.movie_outlined, size: 26),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.fileCount} 个文件'
                            '${multiFolder ? " · ${item.folders.length} 个文件夹" : ""}'
                            '${item.airDate.isNotEmpty ? " · ${item.airDate}" : ""}',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (item.isMatched &&
                              item.info != null &&
                              item.info!.id > 0)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 16,
                                children: [
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () {
                                      final info = item.info;
                                      if (info == null) return;
                                      Navigator.pop(context);
                                      sheetContext.pushNamed(
                                        '/info/',
                                        arguments: info.toBangumiItem(),
                                      );
                                    },
                                    icon: const Icon(Icons.info_outline_rounded,
                                        size: 18),
                                    label: const Text('番剧详情'),
                                  ),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () {
                                      final info = item.info;
                                      if (info == null) return;
                                      final folders = item.folders;
                                      final group = AnimeGroup(
                                        info: info,
                                        folders: folders,
                                      );
                                      Navigator.pop(context);
                                      _showMissingEpisodesSheet(
                                        sheetContext,
                                        controller,
                                        group,
                                      );
                                    },
                                    icon: const Icon(
                                        Icons.playlist_remove_rounded,
                                        size: 18),
                                    label: const Text('缺集检测'),
                                  ),
                                ],
                              ),
                            ),
                          if (!item.isMatched)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  showDialog<void>(
                                    context: sheetContext,
                                    builder: (_) => _ManualMatchDialog(
                                      controller: controller,
                                      folder: item.folders.first,
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.search_rounded, size: 18),
                                label: const Text('手动匹配番剧'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: Divider(height: 1)),
            for (final folder in item.folders) ...[
              if (multiFolder)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_outlined, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SliverList.builder(
                itemCount: folder.files.length,
                itemBuilder: (context, index) {
                  final file = folder.files[index];
                  return _FileTile(
                    file: file,
                    onTap: () {
                      Navigator.pop(context);
                      onFileTap(file, folder.files, item.info);
                    },
                    onMenu: () => _showFileActionSheet(
                      sheetContext,
                      controller,
                      file,
                      folder.files,
                      item.info,
                      onPlay: onFileTap,
                    ),
                  );
                },
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        );
      },
    ),
  );
}

// ============ 文件条目 ============

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.onTap,
    required this.onMenu,
  });

  final LocalMediaFile file;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading:
          const Icon(Icons.play_circle_outline_rounded, size: 28),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: file.size <= 0
          ? null
          : Text(
              '${file.sizeLabel} · ${_formatDate(file.modifiedAt)}',
              style: theme.textTheme.bodySmall,
            ),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert, size: 20),
        onPressed: onMenu,
      ),
      onTap: onTap,
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

// ============ 文件操作菜单 ============

/// [onPlay] 必须由调用方显式传入。
///
/// 不要退回 `findAncestorStateOfType<_MediaLibraryPageState>()` ——
/// 模态路由挂在 Navigator 下、不在页面子树里，从 sheet 内部往上找拿不到页面 State，
/// 会导致「播放」静默失效。
void _showFileActionSheet(
  BuildContext context,
  MediaController controller,
  LocalMediaFile file,
  List<LocalMediaFile> siblings,
  MediaScrapeInfo? info, {
  required Future<void> Function(
          LocalMediaFile, List<LocalMediaFile>, MediaScrapeInfo?)
      onPlay,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.play_arrow_rounded),
            title: const Text('播放'),
            onTap: () {
              Navigator.pop(context);
              if (Platform.isWindows) {
                onPlay(file, siblings, info);
              } else {
                OpenFilex.open(file.path);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('重命名'),
            onTap: () {
              Navigator.pop(context);
              _showRenameDialog(context, controller, file);
            },
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outline),
            title: const Text('移动到...'),
            onTap: () {
              Navigator.pop(context);
              _showMoveDialog(context, controller, file);
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: const Text('打开文件所在目录'),
            onTap: () {
              Navigator.pop(context);
              revealInFileManager(file.path).then((ok) {
                if (!ok) {
                  KazumiDialog.showToast(
                      message: '无法打开文件管理器或文件不存在');
                }
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('删除', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _confirmDelete(context, controller, file);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void _showRenameDialog(
  BuildContext context,
  MediaController controller,
  LocalMediaFile file,
) {
  final ext = p.extension(file.path);
  final nameController =
      TextEditingController(text: p.basenameWithoutExtension(file.path));
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('重命名'),
      content: TextField(
        controller: nameController,
        autofocus: true,
        decoration: InputDecoration(
          labelText: '文件名',
          suffixText: ext,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            final newName = nameController.text;
            Navigator.pop(dialogContext);
            controller.renameFile(file, newName);
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

void _showMoveDialog(
  BuildContext context,
  MediaController controller,
  LocalMediaFile file,
) async {
  final result = await FilePicker.platform.getDirectoryPath(
    dialogTitle: '选择目标文件夹',
  );
  if (result == null || result.isEmpty || !context.mounted) return;
  controller.moveFile(file, result);
}

void _confirmDelete(
  BuildContext context,
  MediaController controller,
  LocalMediaFile file,
) {
  KazumiDialog.show(
    builder: (dialogContext) => AlertDialog(
      title: const Text('删除文件'),
      content: Text('确定要删除「${file.name}」吗？此操作不可恢复。'),
      actions: [
        TextButton(
          onPressed: () => KazumiDialog.dismiss(),
          child: Text(
            '取消',
            style:
                TextStyle(color: Theme.of(dialogContext).colorScheme.outline),
          ),
        ),
        TextButton(
          onPressed: () {
            controller.deleteFile(file);
            KazumiDialog.dismiss();
          },
          child: Text(
            '删除',
            style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
          ),
        ),
      ],
    ),
  );
}

// ============ 手动匹配对话框 ============

class _ManualMatchDialog extends StatefulWidget {
  const _ManualMatchDialog({
    required this.controller,
    required this.folder,
  });

  final MediaController controller;
  final LocalMediaFolder folder;

  @override
  State<_ManualMatchDialog> createState() => _ManualMatchDialogState();
}

class _ManualMatchDialogState extends State<_ManualMatchDialog> {
  final _searchController = TextEditingController();
  List<BangumiItem> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // 预填清洗后的文件夹名
    _searchController.text = widget.folder.name;
    _search();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;
    setState(() => _loading = true);
    try {
      final results = await widget.controller.searchBangumi(keyword);
      if (mounted) setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('手动匹配番剧'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: '搜索关键词',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else if (_results.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无结果，请尝试其他关键词'),
              )
            else
              SizedBox(
                height: 300,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final item = _results[index];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 40,
                          height: 56,
                          child: item.images['large'] != null &&
                                  item.images['large']!.isNotEmpty
                              ? NetworkImgLayer(
                                  src: item.images['large']!,
                                  width: 40,
                                  height: 56,
                                )
                              : Container(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: const Icon(Icons.movie, size: 20),
                                ),
                        ),
                      ),
                      title: Text(
                        item.nameCn.isNotEmpty ? item.nameCn : item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      onTap: () {
                        widget.controller
                            .setFolderMatch(widget.folder.path, item);
                        Navigator.pop(context);
                        KazumiDialog.showToast(message: '已匹配');
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

// ============ 文件夹管理 ============

class _FolderManagerSheet extends StatelessWidget {
  const _FolderManagerSheet({
    required this.controller,
    required this.scrollController,
  });

  final MediaController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
          child: Row(
            children: [
              Text('文件夹管理', style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _pickFolder(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Observer(
            builder: (_) {
              if (controller.folders.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('还没有添加任何文件夹'),
                  ),
                );
              }
              return ListView.separated(
                controller: scrollController,
                itemCount: controller.folders.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final folder = controller.folders[index];
                  return ListTile(
                    leading: const Icon(Icons.folder_rounded),
                    title: Text(p.basename(folder).isEmpty
                        ? folder
                        : p.basename(folder)),
                    subtitle: Text(
                      folder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => controller.removeFolder(folder),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '按文件夹分组：${controller.groupByFolder ? "开启" : "关闭"}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Switch(
                value: controller.groupByFolder,
                onChanged: (value) => controller.setGroupByFolder(value),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickFolder(BuildContext context) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择视频文件夹',
    );
    if (result == null || result.isEmpty) return;
    await controller.addFolder(result);
    KazumiDialog.showToast(message: '已添加文件夹');
    if (Platform.isMacOS) {
      KazumiDialog.showToast(message: '若扫描无结果，请确认应用有访问该文件夹的权限');
    }
  }
}
