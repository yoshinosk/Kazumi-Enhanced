import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/pages/player/danmaku_switch_dialog.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_time_offset_sheet.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/danmaku_axis_checker.dart';

/// 弹幕加载成功后执行弹幕轴对齐检测：
/// 结合接口返回的弹幕时间轴与播放的视频时长判断是否对齐，
/// 未对齐时弹窗提示；轴错误提供推荐偏移一键应用，弹幕源错误引导切换弹幕源。
Future<void> checkDanmakuAxisAlignment({
  required PlayerController playerController,
  required VideoPageController videoPageController,
  required List<DanmakuEntry> danmakus,
  bool Function()? shouldProceed,
}) async {
  if (danmakus.isEmpty) return;
  if (!GStorage.getSetting<bool>(SettingsKeys.danmakuAxisAutoCheck)) return;
  // 用户已手动调整过弹幕轴（全局偏移），或当前番剧 / 分集已有作用域
  // 偏移（此前单集检测已应用），视为已知晓偏差，不再打扰。
  // 作用域化存储保证其他番剧 / 分集仍会自动触发检测。
  if (DanmakuTimeOffsetStore.effectiveOffset(
        playerController.danmaku.bangumiID,
        playerController.danmaku.danmakuEpisodeId,
      ) !=
      0) {
    KazumiLogger().i(
        'DanmakuAxis: skipped by active offset '
        '${DanmakuTimeOffsetStore.effectiveOffset(playerController.danmaku.bangumiID, playerController.danmaku.danmakuEpisodeId)}s '
        'bangumiID=${playerController.danmaku.bangumiID} '
        'episodeId=${playerController.danmaku.danmakuEpisodeId}',
        forceLog: true);
    return;
  }

  final duration = await _waitForVideoDuration(playerController);
  if (duration == null || duration <= Duration.zero) return;
  if (shouldProceed != null && !shouldProceed()) return;

  final result = DanmakuAxisChecker.check(
    danmakus: danmakus,
    videoDuration: duration,
  );
  KazumiLogger().i(
      'DanmakuAxis: ${result.issue.name}, axis=${result.axisLengthSeconds.toStringAsFixed(1)}s, video=${result.videoDurationSeconds.toStringAsFixed(1)}s, head=${result.headGapSeconds.toStringAsFixed(1)}s(${result.headGapReliable ? 'hard' : 'soft'}), tail=${result.tailGapSeconds.toStringAsFixed(1)}s(${result.tailGapReliable ? 'hard' : 'soft'}), beyond=${result.beyondFraction.toStringAsFixed(3)}, confidence=${result.confidence.toStringAsFixed(2)}, offset=${result.recommendedOffsetSeconds.toStringAsFixed(1)}s',
      forceLog: true);
  if (result.issue == DanmakuAxisIssue.none) return;
  if (shouldProceed != null && !shouldProceed()) return;

  await showDanmakuAxisMismatchDialog(
    playerController: playerController,
    videoPageController: videoPageController,
    result: result,
  );
}

/// 弹幕轴未对齐提示弹窗：展示检测数据，并按异常类型提供处理入口。
Future<void> showDanmakuAxisMismatchDialog({
  required PlayerController playerController,
  required VideoPageController videoPageController,
  required DanmakuAxisCheckResult result,
}) {
  final bool axisError = result.issue == DanmakuAxisIssue.axisOffset;
  return KazumiDialog.show(
    clickMaskDismiss: true,
    builder: (context) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      return AlertDialog(
        title: Row(
          children: [
            Icon(
              axisError ? Icons.timelapse_rounded : Icons.warning_amber_rounded,
              color: axisError ? colorScheme.primary : colorScheme.error,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(axisError ? '弹幕轴与视频未对齐' : '弹幕源疑似不匹配'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              axisError
                  ? '检测到弹幕时间轴与当前视频时长存在偏差，可能导致弹幕与实际画面错位。'
                  : '检测到弹幕轴长度与当前视频时长差异过大，当前弹幕可能来自其他分集或合集。',
            ),
            const SizedBox(height: 12),
            _AxisInfoRow(
              label: '弹幕轴长度',
              value: _formatDuration(result.axisLengthSeconds),
            ),
            _AxisInfoRow(
              label: '视频时长',
              value: _formatDuration(result.videoDurationSeconds),
            ),
            if (axisError) ...[
              if (result.headGapSeconds > 0.5)
                _AxisInfoRow(
                  label: '轴头空白',
                  value:
                      '${_formatDuration(result.headGapSeconds)}'
                      '${result.headGapReliable ? '' : '（自然空窗）'}',
                ),
              if (result.tailGapSeconds > 0.5)
                _AxisInfoRow(
                  label: '轴尾空白',
                  value:
                      '${_formatDuration(result.tailGapSeconds)}'
                      '${result.tailGapReliable ? '' : '（自然空窗）'}',
                ),
              _AxisInfoRow(
                label: '推荐偏移',
                value: formatDanmakuTimeOffset(
                  result.recommendedOffsetSeconds,
                ),
              ),
              _AxisInfoRow(
                label: '推荐可信度',
                value: _confidenceLabel(result.confidence),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(),
            child: Text(
              '忽略',
              style: TextStyle(color: colorScheme.outline),
            ),
          ),
          if (axisError)
            FilledButton(
              onPressed: () {
                KazumiDialog.dismiss();
                // 推荐偏移写入当前番剧/分集作用域，不污染其他剧集；
                // 写入后重新调度当前弹幕立即生效。
                unawaited(DanmakuTimeOffsetStore.setScopedOffset(
                  playerController.danmaku.bangumiID,
                  playerController.danmaku.danmakuEpisodeId,
                  result.recommendedOffsetSeconds,
                ));
                playerController.danmaku.clearAndInvalidateScheduledDanmakus();
                KazumiDialog.showToast(
                  message:
                      '已应用推荐偏移 ${formatDanmakuTimeOffset(result.recommendedOffsetSeconds)}',
                );
              },
              child: const Text('应用推荐偏移'),
            )
          else
            FilledButton(
              onPressed: () {
                KazumiDialog.dismiss();
                showDanmakuEpisodePickerDialog(
                  playerController: playerController,
                  videoPageController: videoPageController,
                  bangumiId: playerController.danmaku.bangumiID,
                  animeTitle: playerController.danmaku.danmakuAnimeTitle,
                );
              },
              child: const Text('切换弹幕源'),
            ),
        ],
      );
    },
  );
}

class _AxisInfoRow extends StatelessWidget {
  const _AxisInfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(double totalSeconds) {
  final seconds = totalSeconds.round();
  final minutes = seconds ~/ Duration.secondsPerMinute;
  final remainder = seconds % Duration.secondsPerMinute;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainder.toString().padLeft(2, '0')}';
}

/// 推荐偏移可信度的展示文案：多信号互相印证且幅度足够时为高。
String _confidenceLabel(double confidence) {
  if (confidence >= 0.85) {
    return '高';
  }
  if (confidence >= 0.6) {
    return '中';
  }
  return '低';
}

/// 等待播放器解析出视频时长（视频初始化后才有），超时返回 null。
Future<Duration?> _waitForVideoDuration(
  PlayerController playerController, {
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 500),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final duration = playerController.playback.duration;
    if (duration > Duration.zero) {
      return duration;
    }
    await Future.delayed(interval);
  }
  final duration = playerController.playback.duration;
  return duration > Duration.zero ? duration : null;
}
