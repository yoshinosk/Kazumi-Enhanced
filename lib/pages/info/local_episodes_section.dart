import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/download/download_module.dart'
    show DownloadEpisode;
import 'package:kazumi/modules/history/history_module.dart'
    show kLocalMediaAdapterName;
import 'package:kazumi/pages/magnet/magnet_page.dart'
    show MagnetSearchRouteArgs;
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/services/media/local_availability_service.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/utils/local_episode_parser.dart';
import 'package:path/path.dart' as p;

/// 本地可播放内容区块：媒体库文件 + 离线缓存剧集。
///
/// 仅当本番剧存在本地内容时渲染；点击条目直接用应用内播放器播放
/// （携带 Bangumi 关联以便弹幕 / 进度联动）。[onPlay] 在导航前触发，
/// 供弹窗场景先关闭自身。
class LocalEpisodesSection extends StatelessWidget {
  const LocalEpisodesSection({
    super.key,
    required this.bangumiItem,
    this.onPlay,
  });

  final BangumiItem bangumiItem;

  /// 播放 / 跳转前先执行的回调（例如关闭弹窗）。
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final bangumiId = bangumiItem.id;
        if (bangumiId <= 0) return const SizedBox.shrink();
        final availability =
            inject<LocalAvailabilityService>().availabilityFor(bangumiId);
        if (availability.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final children = <Widget>[];

        // 媒体库文件：按目录分组，每组分目录标题 + 集数 chips。
        if (availability.files.isNotEmpty) {
          final byDir = <String, List<LocalMediaFile>>{};
          for (final file in availability.files) {
            (byDir[p.dirname(file.path)] ??= []).add(file);
          }
          children.add(_GroupLabel(
            icon: Icons.video_library_outlined,
            text: '本地媒体库 · ${availability.localFileCount} 个文件',
          ));
          for (final entry in byDir.entries) {
            final files = entry.value;
            children.add(_FolderChips(
              folderName: p.basename(entry.key),
              files: files,
              onFileTap: (index) {
                onPlay?.call();
                context.pushNamed(
                  '/video/',
                  arguments: LocalMediaVideoPlaybackArgs(
                    bangumiItem: bangumiItem,
                    files: files,
                    selectedIndex: index,
                    pluginName: kLocalMediaAdapterName,
                    bangumiSyncId: bangumiId,
                  ),
                );
              },
            ));
          }
        }

        // 离线缓存：按插件聚合，每组插件名 + 集数 chips。
        if (availability.cachedByPlugin.isNotEmpty) {
          children.add(_GroupLabel(
            icon: Icons.offline_pin_outlined,
            text: '离线缓存 · ${availability.cachedCount} 集',
          ));
          for (final entry in availability.cachedByPlugin.entries) {
            children.add(_CachedChips(
              pluginName: entry.key,
              episodes: entry.value,
              onEpisodeTap: (episode) {
                onPlay?.call();
                context.pushNamed(
                  '/video/',
                  arguments: OfflineVideoPlaybackArgs(
                    bangumiItem: bangumiItem,
                    pluginName: entry.key,
                    episodeNumber: episode.episodeNumber,
                    road: episode.road,
                    downloadedEpisodes: entry.value,
                  ),
                );
              },
            ));
          }
        }

        children.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    onPlay?.call();
                    context.pushNamed(
                      '/magnet/',
                      arguments: MagnetSearchRouteArgs(
                        query: bangumiItem.nameCn.isNotEmpty
                            ? bangumiItem.nameCn
                            : bangumiItem.name,
                        anime: bangumiItem,
                      ),
                    );
                  },
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('搜索磁力补集'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    onPlay?.call();
                    context.pushNamed('/tab/media/');
                  },
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('打开媒体库'),
                ),
              ),
            ],
          ),
        ));

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.25),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.play_circle_fill_rounded,
                        size: 18, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('本地播放', style: theme.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 6),
                ...children,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 本地分组小标题（媒体库 / 离线缓存）。
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个本地媒体库目录的集数 chips，点击播放对应文件。
class _FolderChips extends StatelessWidget {
  const _FolderChips({
    required this.folderName,
    required this.files,
    required this.onFileTap,
  });

  final String folderName;
  final List<LocalMediaFile> files;
  final void Function(int index) onFileTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            folderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < files.length; i++)
                ActionChip(
                  label: Text(_chipLabel(files[i].name)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onFileTap(i),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _chipLabel(String fileName) {
    final ep = parseLocalEpisodeNumber(fileName);
    final kind = localEpisodeKindLabel(classifyLocalEpisode(fileName));
    if (ep > 0) return '第$ep集';
    if (kind.isNotEmpty) return kind;
    return p.basenameWithoutExtension(fileName);
  }
}

/// 一个离线缓存插件的已缓存剧集 chips，点击播放对应剧集。
class _CachedChips extends StatelessWidget {
  const _CachedChips({
    required this.pluginName,
    required this.episodes,
    required this.onEpisodeTap,
  });

  final String pluginName;
  final List<DownloadEpisode> episodes;
  final void Function(DownloadEpisode episode) onEpisodeTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = List<DownloadEpisode>.of(episodes)
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pluginName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final episode in sorted)
                ActionChip(
                  label: Text('第${episode.episodeNumber}集'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onEpisodeTap(episode),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
