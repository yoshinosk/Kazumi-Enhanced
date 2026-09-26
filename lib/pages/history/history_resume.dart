import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/dialog/dialog_task.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/magnet/magnet_page.dart' show MagnetSearchRouteArgs;
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
/// [dialogOwner] 是调用方的 State（需 mixin [KazumiDialogOwner]），
/// 用于加载对话框的生命周期管理。
Future<void> resumeHistoryPlayback(
  BuildContext context,
  KazumiDialogOwner dialogOwner,
  History history,
) async {
  final playbackService = inject<HistoryPlaybackService>();
  String? unavailableReason;
  await dialogOwner.dialogs.run((task) async {
    final cancelToken = RuleCancelToken();
    final result = await task.loading(
      message: '获取中',
      barrierDismissible: isDesktop(),
      onCancel: cancelToken.cancel,
      action: () => playbackService.open(history, cancelToken: cancelToken),
    );
    switch (result) {
      case HistoryPlaybackReady(:final args):
        task.withContext(
            (context) => context.pushNamed('/video/', arguments: args));
      case HistoryPlaybackUnavailable(:final reason):
        // 引导弹窗须等加载对话框关闭后再弹，因此延后到 dialogs.run 之外处理。
        unavailableReason = reason;
    }
  }, errorMessage: '暂时无法继续播放，请稍后重试');
  final reason = unavailableReason;
  if (!context.mounted || reason == null) return;
  if (isLocalMediaHistory(history)) {
    await showMissingLocalFileDialog(context, reason, history);
  } else {
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
