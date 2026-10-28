import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/history/history_list_query.dart';
import 'package:kazumi/pages/magnet/magnet_page.dart' show MagnetSearchRouteArgs;
import 'package:kazumi/services/lan/lan_media_paths.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/utils/device.dart';

/// 「上次看到 h:mm:ss」进度文案；无有效进度时返回空串。
String historyPositionLabel(History history) {
  final progress = history.progresses[history.lastWatchEpisode]?.progress;
  if (progress == null || progress.inSeconds <= 0) return '';
  final seconds = (progress.inSeconds % 60).toString().padLeft(2, '0');
  final minutes = (progress.inMinutes % 60).toString().padLeft(2, '0');
  final position = progress.inHours > 0
      ? '${progress.inHours}:$minutes:$seconds'
      : '${progress.inMinutes}:$seconds';
  return '看到 $position';
}

/// 从历史记录恢复播放的统一入口，历史页卡片与首页「继续观看」共用。
///
/// 同一番剧用多个来源观看过时，按最近观看顺序依次尝试：首选来源失效
/// （插件被删、在线页面解析失败、缓存/本地文件缺失等）会自动改用其它
/// 来源续播并提示切换结果；全部不可用才按首条记录的原因提示。
///
/// [dialogOwner] 是调用方的 State（需 mixin [KazumiDialogOwner]），
/// 用于加载对话框的生命周期管理。
Future<void> resumeHistoryPlayback(
  BuildContext context,
  KazumiDialogOwner dialogOwner,
  HistoryGroup group,
) async {
  final playbackService = inject<HistoryPlaybackService>();
  String? unavailableReason;
  await dialogOwner.dialogs.run((task) async {
    final cancelToken = RuleCancelToken();
    final result = await task.loading(
      message: '获取中',
      barrierDismissible: isDesktop(),
      onCancel: cancelToken.cancel,
      action: () =>
          playbackService.openGroup(group.entries, cancelToken: cancelToken),
    );
    final args = result.args;
    if (args != null) {
      final usedHistory = result.history;
      if (result.usedFallback && usedHistory != null) {
        KazumiDialog.showToast(
          message:
              '当前来源不可用，已切换到${historySourceLabel(usedHistory)}继续播放',
        );
      }
      task.withContext(
          (context) => context.pushNamed('/video/', arguments: args));
    } else {
      unavailableReason = result.unavailableReason;
    }
  }, errorMessage: '暂时无法继续播放，请稍后重试');
  final reason = unavailableReason;
  if (!context.mounted || reason == null) return;
  final primary = group.primary;
  if (isLocalMediaHistory(primary) && !isLanMediaPath(primary.episodePageUrl)) {
    await showMissingLocalFileDialog(context, reason, primary);
  } else {
    // 桌面端媒体库条目不可用通常是电脑离线 / 配对失效，不需要引导用户
    // 去本机找文件或重新下载。
    KazumiDialog.showToast(message: reason);
  }
}

/// 本地媒体库文件缺失时的引导：提供「详情页 / 磁力搜索」两个去向。
Future<void> showMissingLocalFileDialog(
  BuildContext context,
  String reason,
  History history,
) async {
  final bangumiItem = history.bangumiItem;
  final theme = Theme.of(context);
  final action = await KazumiDialog.show<String>(
    builder: (dialogContext) => AlertDialog(
      title: const Text('本地文件不可用'),
      content: Text(
        '$reason\n\n可以选择回到番剧详情页重新匹配本地文件，'
        '或直接搜索磁力资源补下该番剧。',
        style: theme.textTheme.bodyMedium,
      ),
      actions: [
        TextButton(
          onPressed: () => KazumiDialog.dismiss(popWith: 'close'),
          child: Text(
            '取消',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),
        TextButton(
          onPressed: () => KazumiDialog.dismiss(popWith: 'magnet'),
          child: const Text('搜索磁力'),
        ),
        FilledButton(
          onPressed: () => KazumiDialog.dismiss(popWith: 'info'),
          child: const Text('去详情页'),
        ),
      ],
    ),
  );
  if (!context.mounted || action == null || action == 'close') return;
  if (action == 'info') {
    context.pushNamed('/info/', arguments: bangumiItem);
  } else {
    context.pushNamed(
      '/magnet/',
      arguments: MagnetSearchRouteArgs(
        query: bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name,
        anime: bangumiItem,
      ),
    );
  }
}
