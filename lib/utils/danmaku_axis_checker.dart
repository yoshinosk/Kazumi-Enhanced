import 'dart:math';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';

/// 弹幕轴与视频时长对齐检测结果分类。
enum DanmakuAxisIssue {
  /// 弹幕轴与视频时长吻合，无需处理
  none,

  /// 弹幕轴整体偏移（轴错误），可通过时间偏移校准
  axisOffset,

  /// 弹幕轴与视频时长差异过大（弹幕源错误），应切换弹幕源
  sourceMismatch,
}

/// 弹幕轴检测结果。
class DanmakuAxisCheckResult {
  const DanmakuAxisCheckResult({
    required this.issue,
    required this.axisLengthSeconds,
    required this.videoDurationSeconds,
    required this.differenceSeconds,
    required this.beyondFraction,
    this.recommendedOffsetSeconds = 0,
  });

  final DanmakuAxisIssue issue;

  /// 弹幕轴长度（秒），取弹幕时间分布的高百分位以剔除离群弹幕。
  final double axisLengthSeconds;

  /// 播放的视频时长（秒）。
  final double videoDurationSeconds;

  /// 弹幕轴长度 - 视频时长（秒），正数表示弹幕轴更长。
  final double differenceSeconds;

  /// 时间落在视频时长之外的弹幕占比。
  final double beyondFraction;

  /// 轴错误时推荐应用的时间偏移（秒），正数延后、负数提前。
  final double recommendedOffsetSeconds;
}

/// 依据弹幕时间轴与视频时长判断弹幕是否与视频源对齐。
///
/// 弹幕时间戳构成弹幕轴：同一集的正版弹幕轴长度应接近视频时长。
/// 轴明显长于视频（合集 / 其他分集弹幕）判定为弹幕源错误；
/// 差异处于可校准范围内判定为轴错误，并给出按轴尾对齐的推荐偏移。
class DanmakuAxisChecker {
  /// 时间偏移可校准的最大范围（与弹幕时间偏移设置一致）。
  static const double maxAdjustableOffsetSeconds = 180;

  /// 弹幕轴与视频时长比例超过该阈值判定为弹幕源错误。
  static const double sourceMismatchRatio = 1.6;

  /// 判定为对齐的最小固定容差（秒）。
  static const double alignedToleranceSeconds = 10;

  /// 判定为对齐的时长比例容差。
  static const double alignedToleranceRatio = 0.02;

  /// 弹幕轴尾部超出视频时长且占比超过该阈值判定为弹幕源错误。
  static const double beyondFractionThreshold = 0.25;

  static DanmakuAxisCheckResult check({
    required List<DanmakuEntry> danmakus,
    required Duration videoDuration,
  }) {
    final durationSeconds = videoDuration.inMilliseconds / 1000.0;
    if (danmakus.isEmpty || durationSeconds <= 0) {
      return const DanmakuAxisCheckResult(
        issue: DanmakuAxisIssue.none,
        axisLengthSeconds: 0,
        videoDurationSeconds: 0,
        differenceSeconds: 0,
        beyondFraction: 0,
      );
    }

    final times = danmakus.map((e) => e.time).toList()..sort();
    final axisLengthSeconds = _percentile(times, 0.995);
    final difference = axisLengthSeconds - durationSeconds;
    final absoluteDifference = difference.abs();
    final tolerance =
        max(alignedToleranceSeconds, durationSeconds * alignedToleranceRatio);

    if (absoluteDifference <= tolerance) {
      return DanmakuAxisCheckResult(
        issue: DanmakuAxisIssue.none,
        axisLengthSeconds: axisLengthSeconds,
        videoDurationSeconds: durationSeconds,
        differenceSeconds: difference,
        beyondFraction: 0,
      );
    }

    final beyondCount = danmakus.where((e) => e.time > durationSeconds).length;
    final beyondFraction = beyondCount / danmakus.length;
    final ratio = axisLengthSeconds / durationSeconds;

    final bool sourceMismatch =
        absoluteDifference > maxAdjustableOffsetSeconds ||
            ratio >= sourceMismatchRatio ||
            ratio <= 1 / sourceMismatchRatio ||
            (difference > 0 && beyondFraction >= beyondFractionThreshold);

    if (sourceMismatch) {
      return DanmakuAxisCheckResult(
        issue: DanmakuAxisIssue.sourceMismatch,
        axisLengthSeconds: axisLengthSeconds,
        videoDurationSeconds: durationSeconds,
        differenceSeconds: difference,
        beyondFraction: beyondFraction,
      );
    }

    return DanmakuAxisCheckResult(
      issue: DanmakuAxisIssue.axisOffset,
      axisLengthSeconds: axisLengthSeconds,
      videoDurationSeconds: durationSeconds,
      differenceSeconds: difference,
      beyondFraction: beyondFraction,
      // 按轴尾对齐：视频结束时恰好播完最后一条弹幕。
      // 弹幕轴更长（difference > 0）时推荐提前，更短时推荐延后。
      recommendedOffsetSeconds: (-difference).clamp(
        -maxAdjustableOffsetSeconds,
        maxAdjustableOffsetSeconds,
      ),
    );
  }

  static double _percentile(List<double> sorted, double percentile) {
    final index =
        ((sorted.length - 1) * percentile).round().clamp(0, sorted.length - 1);
    return sorted[index];
  }
}
