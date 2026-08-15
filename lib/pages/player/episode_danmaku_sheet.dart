import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/player/danmaku_offset_menu.dart';
import 'package:kazumi/pages/player/danmaku_switch_dialog.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/request/apis/danmaku_api.dart';
import 'package:kazumi/utils/device.dart';
import 'package:mobx/mobx.dart' as mobx;

/// 播放器侧边「弹幕」面板：展示当前弹幕池的弹幕列表（含弹幕时间轴
/// 快速调整），并可查看/切换当前番剧的弹幕分集。
class EpisodeDanmakuSheet extends StatefulWidget {
  const EpisodeDanmakuSheet({
    super.key,
    required this.playerController,
    required this.videoPageController,
  });

  final PlayerController playerController;
  final VideoPageController videoPageController;

  @override
  State<EpisodeDanmakuSheet> createState() => _EpisodeDanmakuSheetState();
}

class _EpisodeDanmakuSheetState extends State<EpisodeDanmakuSheet> {
  List<DanmakuEpisode> _episodes = [];
  bool _episodesLoading = false;
  bool _episodesFailed = false;

  int _bodyIndex = 0;

  PlayerController get playerController => widget.playerController;

  late final mobx.ReactionDisposer _bangumiIdReaction;

  @override
  void initState() {
    super.initState();
    _bangumiIdReaction = mobx.reaction<int>(
      (_) => playerController.danmaku.bangumiID,
      (_) => _loadEpisodes(),
    );
    _loadEpisodes();
  }

  @override
  void dispose() {
    _bangumiIdReaction();
    super.dispose();
  }

  Future<void> _loadEpisodes() async {
    final bangumiId = playerController.danmaku.bangumiID;
    if (bangumiId <= 0) {
      setState(() {
        _episodes = [];
        _episodesLoading = false;
        _episodesFailed = false;
      });
      return;
    }
    setState(() {
      _episodesLoading = true;
      _episodesFailed = false;
    });
    try {
      final response =
          await DanmakuApi.getDanDanEpisodesByDanDanBangumiID(bangumiId);
      if (!mounted || bangumiId != playerController.danmaku.bangumiID) {
        return;
      }
      setState(() {
        _episodes = response.episodes;
        _episodesLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _episodesLoading = false;
        _episodesFailed = true;
      });
    }
  }

  Future<void> _switchToEpisode(DanmakuEpisode episode) async {
    await bindDanmakuToEpisode(
      playerController: playerController,
      videoPageController: widget.videoPageController,
      animeTitle: playerController.danmaku.danmakuAnimeTitle,
      episode: episode,
    );
  }

  void _showSwitchDialog() {
    final danmaku = playerController.danmaku;
    if (danmaku.bangumiID > 0) {
      showDanmakuEpisodePickerDialog(
        playerController: playerController,
        videoPageController: widget.videoPageController,
        bangumiId: danmaku.bangumiID,
        animeTitle: danmaku.danmakuAnimeTitle.isNotEmpty
            ? danmaku.danmakuAnimeTitle
            : widget.videoPageController.title,
      );
      return;
    }
    showDanmakuSwitchDialog(
      playerController: playerController,
      videoPageController: widget.videoPageController,
      initialKeyword: widget.videoPageController.title,
    );
  }

  bool _isCurrentEpisode(DanmakuEpisode episode) {
    final danmaku = playerController.danmaku;
    return episode.episodeId == danmaku.danmakuEpisodeId ||
        (danmaku.danmakuEpisodeTitle.isNotEmpty &&
            episode.episodeTitle == danmaku.danmakuEpisodeTitle);
  }

  String get _bindingStatusText {
    final danmaku = playerController.danmaku;
    if (danmaku.danmakuLoading) {
      return '弹幕加载中';
    }
    if (danmaku.danmakuOn) {
      return '弹幕已开启';
    }
    if (danmaku.bangumiID <= 0 || danmaku.danDanmakus.isEmpty) {
      return '未绑定弹幕';
    }
    return '弹幕已关闭';
  }

  Widget get _bindingInfo {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          const Text(' 当前弹幕  '),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Observer(builder: (context) {
                  final danmaku = playerController.danmaku;
                  final animeTitle = danmaku.danmakuAnimeTitle.isNotEmpty
                      ? danmaku.danmakuAnimeTitle
                      : widget.videoPageController.title;
                  return Text(
                    animeTitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  );
                }),
                Observer(builder: (context) {
                  final danmaku = playerController.danmaku;
                  final episodeTitle = danmaku.danmakuEpisodeTitle.isNotEmpty
                      ? danmaku.danmakuEpisodeTitle
                      : '未绑定分集';
                  return Text(
                    episodeTitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  );
                }),
                Observer(builder: (context) {
                  return Text(
                    _bindingStatusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(width: 10),
          DanmakuOffsetMenu(
            onChanged:
                playerController.danmaku.clearAndInvalidateScheduledDanmakus,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          SizedBox(
            height: 34,
            child: TextButton(
              style: ButtonStyle(
                padding: WidgetStateProperty.all(
                  const EdgeInsets.only(left: 4.0, right: 4.0),
                ),
              ),
              onPressed: _showSwitchDialog,
              child: const Text(
                '手动切换',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
          SizedBox(
            height: 34,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '刷新分集列表',
              icon: const Icon(Icons.refresh_rounded, size: 18),
              onPressed: () => _loadEpisodes(),
            ),
          ),
        ],
      ),
    );
  }

  Widget get _episodeListBody {
    if (playerController.danmaku.bangumiID <= 0) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.subtitles_off_rounded, size: 48),
            SizedBox(height: 12),
            Text('当前未绑定弹幕'),
            SizedBox(height: 4),
            Text(
              '点击上方「手动切换」检索并绑定弹幕',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      );
    }
    if (_episodesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_episodesFailed) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('分集列表获取失败'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _loadEpisodes(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_episodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.subtitles_off_rounded, size: 48),
            const SizedBox(height: 12),
            const Text('该番剧暂无可用的弹幕分集'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _showSwitchDialog,
              child: const Text('切换其他弹幕'),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _episodes.length,
      itemBuilder: (context, index) {
        final episode = _episodes[index];
        final bool isCurrent = _isCurrentEpisode(episode);
        return ListTile(
          dense: true,
          selected: isCurrent,
          title: Text(
            episode.episodeTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: isCurrent
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          trailing: isCurrent
              ? Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
          onTap: () => _switchToEpisode(episode),
        );
      },
    );
  }

  Widget _buildSubTab(int index, String label) {
    final bool selected = _bodyIndex == index;
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        if (selected) {
          return;
        }
        setState(() {
          _bodyIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colorScheme.secondaryContainer : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : null,
            color: selected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget get _subTabBar {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _buildSubTab(0, '弹幕池'),
          const SizedBox(width: 8),
          _buildSubTab(1, '切换分集'),
        ],
      ),
    );
  }

  Widget get _danmakuPoolBody {
    final danmaku = playerController.danmaku;
    if (danmaku.bangumiID <= 0 || danmaku.danDanmakus.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              danmaku.bangumiID <= 0
                  ? Icons.subtitles_off_rounded
                  : Icons.inbox_rounded,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(danmaku.bangumiID <= 0 ? '当前未绑定弹幕' : '当前弹幕池为空'),
            const SizedBox(height: 4),
            Text(
              '弹幕加载完成后可在此查看弹幕池内容',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }
    final offset = danmaku.timelineOffsetSeconds;
    final items = <_DanmakuPoolItem>[];
    danmaku.danDanmakus.forEach((second, list) {
      for (final entry in list) {
        items.add(_DanmakuPoolItem(second: second, entry: entry));
      }
    });
    items.sort((a, b) {
      final timeCompare = a.second.compareTo(b.second);
      if (timeCompare != 0) {
        return timeCompare;
      }
      return a.entry.message.compareTo(b.entry.message);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            '共 ${items.length} 条弹幕',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        Divider(height: isDesktop() ? 0.5 : 0.2),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final colorScheme = Theme.of(context).colorScheme;
              return ListTile(
                dense: true,
                leading: SizedBox(
                  width: 52,
                  child: Text(
                    _formatPoolTime(item.second + offset),
                    style: TextStyle(
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: colorScheme.outline,
                    ),
                  ),
                ),
                title: Text(
                  item.entry.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface,
                  ),
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _typeColor(colorScheme, item.entry.type)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _typeLabel(item.entry.type),
                    style: TextStyle(
                      fontSize: 11,
                      color: _typeColor(colorScheme, item.entry.type),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _typeLabel(int type) {
    switch (type) {
      case 4:
        return '底部';
      case 5:
        return '顶部';
      default:
        return '滚动';
    }
  }

  Color _typeColor(ColorScheme colorScheme, int type) {
    switch (type) {
      case 4:
        return colorScheme.secondary;
      case 5:
        return colorScheme.tertiary;
      default:
        return colorScheme.primary;
    }
  }

  String _formatPoolTime(double seconds) {
    final total = seconds.round().clamp(0, 1 << 31);
    final hours = total ~/ Duration.secondsPerHour;
    final minutes =
        (total % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
    final rest = total % Duration.secondsPerMinute;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = rest.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bindingInfo,
          Divider(height: isDesktop() ? 0.5 : 0.2),
          _subTabBar,
          const SizedBox(height: 4),
          Expanded(
            child: _bodyIndex == 0 ? _danmakuPoolBody : _episodeListBody,
          ),
        ],
      ),
    );
  }
}

class _DanmakuPoolItem {
  const _DanmakuPoolItem({
    required this.second,
    required this.entry,
  });

  final int second;
  final DanmakuEntry entry;
}
