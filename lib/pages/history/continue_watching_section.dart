import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_task.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/history/history_resume.dart';

/// 首页顶部的「继续观看」区域。
///
/// 最近一次观看以大卡片突出显示，点击直接恢复上次的集数和断点进度；
/// 更早的记录横向滑动展示，方便快速切换到其它在看的番剧。
class ContinueWatchingSection extends StatefulWidget {
  const ContinueWatchingSection({super.key});

  @override
  State<ContinueWatchingSection> createState() =>
      _ContinueWatchingSectionState();
}

class _ContinueWatchingSectionState extends State<ContinueWatchingSection>
    with KazumiDialogOwner {
  final HistoryController _historyController = inject<HistoryController>();

  static const int _recentLimit = 10;

  @override
  void initState() {
    super.initState();
    _historyController.init();
  }

  Future<void> _play(History history) async {
    if (dialogs.isRunning) return;
    await resumeHistoryPlayback(context, this, history);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      final recent = _historyController.histories.take(_recentLimit).toList();
      if (recent.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('继续观看',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context.pushNamed('/settings/history/'),
                icon: const Icon(Icons.history_rounded),
                label: const Text('历史记录'),
              ),
            ],
          ),
          _ResumeCard(
            history: recent.first,
            onPlay: () => _play(recent.first),
          ),
          if (recent.length > 1) ...[
            const SizedBox(height: 12),
            _RecentStrip(
              entries: recent.sublist(1),
              onPlay: _play,
            ),
          ],
        ],
      );
    });
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.history, required this.onPlay});

  final History history;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = history.bangumiItem.nameCn.isEmpty
        ? history.bangumiItem.name
        : history.bangumiItem.nameCn;
    final episode = history.lastWatchEpisodeName.isEmpty
        ? '第 ${history.lastWatchEpisode} 话'
        : history.lastWatchEpisodeName;
    final position = historyPositionLabel(history);
    final source = HistoryEntryKind.normalize(history.entryKind) ==
            HistoryEntryKind.offline
        ? '缓存'
        : '在线';
    final image = history.bangumiItem.images['large'] ?? '';

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: const BorderRadius.all(Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ExcludeSemantics(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: image.isEmpty
                        ? Container(
                            width: 88,
                            height: 88 * 1.4,
                            color: colors.surfaceContainerHighest,
                            child: Icon(Icons.movie_outlined,
                                color: colors.onSurfaceVariant),
                          )
                        : NetworkImgLayer(
                            src: image,
                            width: 88,
                            height: 88 * 1.4,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('上次看到 · $source',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(episode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant)),
                    if (position.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(position,
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('继续播放'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentStrip extends StatelessWidget {
  const _RecentStrip({required this.entries, required this.onPlay});

  final List<History> entries;
  final ValueChanged<History> onPlay;

  static const double _coverWidth = 104;
  static const double _coverHeight = _coverWidth * 1.4;
  static const double _textAreaHeight = 40;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: _coverHeight + _textAreaHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final history = entries[index];
          final title = history.bangumiItem.nameCn.isEmpty
              ? history.bangumiItem.name
              : history.bangumiItem.nameCn;
          final episode = history.lastWatchEpisodeName.isEmpty
              ? '第 ${history.lastWatchEpisode} 话'
              : history.lastWatchEpisodeName;
          final image = history.bangumiItem.images['large'] ?? '';
          return SizedBox(
            width: _coverWidth,
            child: InkWell(
              onTap: () => onPlay(history),
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: image.isEmpty
                            ? Container(
                                width: _coverWidth,
                                height: _coverHeight,
                                color: colors.surfaceContainerHighest,
                                child: Icon(Icons.movie_outlined,
                                    color: colors.onSurfaceVariant),
                              )
                            : NetworkImgLayer(
                                src: image,
                                width: _coverWidth,
                                height: _coverHeight,
                              ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: ExcludeSemantics(
                            child: Icon(Icons.play_arrow_rounded,
                                size: 40,
                                color: Colors.white.withValues(alpha: 0.9),
                                shadows: const [
                                  Shadow(
                                      blurRadius: 12,
                                      color: Colors.black54),
                                ]),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: _textAreaHeight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall),
                        Text(episode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                    color: colors.onSurfaceVariant)),
                      ],
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
