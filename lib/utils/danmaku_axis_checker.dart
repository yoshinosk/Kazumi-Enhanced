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
    this.headGapSeconds = 0,
    this.tailGapSeconds = 0,
    this.headGapReliable = false,
    this.tailGapReliable = false,
    this.confidence = 0,
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

  /// 轴头空白（秒）：视频起点到首条有效弹幕的距离。
  final double headGapSeconds;

  /// 轴尾空白（秒）：末条有效弹幕到视频结尾的距离。
  final double tailGapSeconds;

  /// 轴头 / 轴尾空白是否为「硬边界」（通过密度形态校验）。
  ///
  /// false 表示边界附近弹幕呈自然衰减或突发后沉寂（典型如 ED 弹幕群后
  /// 的片尾滚铭），空白更可能来自内容本身而非轴偏移，不应据此推荐偏移。
  final bool headGapReliable;
  final bool tailGapReliable;

  /// 推荐偏移的置信度（0~1），仅在 [DanmakuAxisIssue.axisOffset] 时有意义。
  final double confidence;

  /// 轴错误时推荐应用的时间偏移（秒），正数延后、负数提前。
  final double recommendedOffsetSeconds;
}

/// 判断弹幕轴是否与视频对齐，并给出推荐偏移。
///
/// 旧方案仅比较「弹幕轴总长度 vs 视频时长」，默认轴尾应贴齐视频结尾，
/// 但 ED 弹幕群后的片尾滚铭、片头无人发弹幕等自然空窗都会被误判为轴偏移，
/// 推荐出错误的偏移量。
///
/// 新方案把弹幕时间分布拆成头、尾两端的「空白 / 越界」四类信号：
///
/// - 轴尾硬截断（内容持续到轴尾突然归零）→ 弹幕提前播完 → 延后；
/// - 轴尾越界（弹幕轴长于视频尾部）→ 提前；
/// - 轴头越界（弹幕早于视频起点）→ 延后；
/// - 轴头硬边界（轴整体后移）→ 提前。由于「片头安静开场」也会产生
///   同样的空白，该信号仅在轴尾同时越界（整轴平移的佐证）时才采信。
///
/// 空白是否可信由密度形态校验决定：边界前的弹幕密度相对前一窗口
/// 骤降（自然稀疏）或骤升（弹幕群后戛然而止）时视为自然空窗，不产生信号。
/// 同向信号按幅度加权融合为推荐偏移；正负信号同时显著说明头尾空白
/// 无法用单一偏移修复，判定为弹幕源错误。
///
/// 越界信号（轴尾越界 / 轴头越界）另有越界群采信校验：分位取值可能
/// 被单条或小簇离群弹幕拉高 / 拉低（如观众在更长版本视频里发言），
/// 仅当越界弹幕与弹幕主体连续延伸（无明显空隙）时才视为轴真实越界。
class DanmakuAxisChecker {
  /// 时间偏移可校准的最大范围（与弹幕时间偏移设置一致）。
  static const double maxAdjustableOffsetSeconds = 180;

  /// 弹幕轴跨度与视频时长比例超过该阈值判定为弹幕源错误。
  static const double sourceMismatchRatio = 1.6;

  /// 判定为对齐的最小固定容差（秒）。
  static const double alignedToleranceSeconds = 10;

  /// 判定为对齐的时长比例容差。
  static const double alignedToleranceRatio = 0.02;

  /// 弹幕落在视频时长之外的占比超过该阈值判定为弹幕源错误。
  static const double beyondFractionThreshold = 0.25;

  /// 有效弹幕样本数下限：样本过少时统计不可靠，不做检测。
  static const int minSampleCount = 30;

  /// 轴头 / 轴尾离群剔除分位。
  static const double _headPercentile = 0.005;
  static const double _tailPercentile = 0.995;

  /// 边界密度探查窗口：占视频时长的比例，限幅在 30~90 秒。
  static const double _edgeProbeWindowRatio = 0.05;
  static const double _edgeProbeMinWindowSeconds = 30;
  static const double _edgeProbeMaxWindowSeconds = 90;

  /// 探查窗口（贴近边界）与前一等宽窗口的密度比低于该值时，
  /// 判定为边界前自然衰减（稀疏尾），空白不可信。
  static const double _edgeDecayRatio = 0.4;

  /// 密度比高于该值时，判定为「弹幕群后沉寂」（如 ED 弹幕群后的片尾），
  /// 空白不可信。
  static const double _edgeSpikeRatio = 2.0;

  /// 硬边界判定所需的近端最小弹幕数，防止低密度弹幕池误判。
  static const int _edgeProbeMinCount = 2;

  /// 轴尾覆盖判定：视频结尾容差窗口内存在的弹幕数达到该值时，视为
  /// 弹幕池已覆盖到视频结尾（自然稀疏尾），轴尾空白不构成轴偏移证据。
  ///
  /// 典型场景：故事与 ED 结束后视频还剩片尾滚铭 / 下集预告，观众极少发
  /// 弹幕，P99.5 分位的「轴尾空白」只是稀疏尾而非硬截断；此时池中往往
  /// 仍有零星弹幕落到视频结尾附近，据此可以排除「整轴提前播完」。
  static const int _tailCoverageMinCount = 2;

  /// 越界群采信的条数比例下限：越界弹幕条数需达到样本量的该比例
  /// （至少 1 条）才可能视为轴真实越界。真实整轴平移 / 合集轴的越界段
  /// 占比通常远高于此，孤立离群弹幕则难以达到。
  static const double _beyondMinFraction = 0.005;

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
    if (times.length < minSampleCount) {
      return DanmakuAxisCheckResult(
        issue: DanmakuAxisIssue.none,
        axisLengthSeconds: times.last,
        videoDurationSeconds: durationSeconds,
        differenceSeconds: times.last - durationSeconds,
        beyondFraction: 0,
      );
    }

    final headIndex = _percentileIndex(
      times.length,
      _headPercentile,
      roundUp: true,
    );
    final tailIndex = _percentileIndex(times.length, _tailPercentile);
    final head = times[headIndex];
    final tail = times[tailIndex];
    final span = max(0.0, tail - head);
    final difference = tail - durationSeconds;
    final tolerance = max(
      alignedToleranceSeconds,
      durationSeconds * alignedToleranceRatio,
    );

    final headGap = max(0.0, head);
    final tailGap = max(0.0, durationSeconds - tail);
    final headBeyond = max(0.0, -head);
    final tailBeyond = max(0.0, tail - durationSeconds);

    var beyondCount = 0;
    for (final t in times) {
      if (t < 0 || t > durationSeconds) beyondCount++;
    }
    final beyondFraction = beyondCount / times.length;

    // --- 边界密度形态校验：区分「硬截断」与「自然空窗」 ---
    final probeWindow = (durationSeconds * _edgeProbeWindowRatio).clamp(
      _edgeProbeMinWindowSeconds,
      _edgeProbeMaxWindowSeconds,
    );
    final headGapReliable =
        headGap > tolerance &&
        _isHardEdge(times, head, probeWindow, isTail: false);
    // 轴尾覆盖守卫：结尾容差窗口内仍有弹幕说明池覆盖到了视频结尾，
    // P99.5 的空白只是稀疏尾（ED / 预告阶段少有人发弹幕），不是轴偏移。
    final tailCoveredCount =
        times.length - _lowerBound(times, durationSeconds - tolerance);
    final tailCovered = tailCoveredCount >= _tailCoverageMinCount;
    final tailGapReliable =
        tailGap > tolerance &&
        !tailCovered &&
        _isHardEdge(times, tail, probeWindow, isTail: true);

    // --- 候选偏移信号（正 = 弹幕应延后，负 = 弹幕应提前）---
    final signals = <double>[];
    // 轴尾硬截断：内容持续到轴尾突然归零，弹幕提前播完 → 延后。
    if (tailGapReliable) signals.add(tailGap);
    // 轴尾越界：弹幕轴长于视频尾部 → 提前。需通过越界群采信校验，
    // 排除单条 / 小簇离群弹幕（观众在更长版本里发言）拉高分位尾的假象。
    final tailBeyondSupported =
        tailBeyond > tolerance &&
        _isBeyondClusterSupported(
          times,
          durationSeconds + tolerance,
          isTail: true,
          gapLimit: 2 * tolerance,
          quantileIndex: tailIndex,
        );
    if (tailBeyondSupported) signals.add(-tailBeyond);
    // 轴头越界：弹幕早于视频起点 → 延后。同样需越界群采信校验。
    final headBeyondSupported =
        headBeyond > tolerance &&
        _isBeyondClusterSupported(
          times,
          -tolerance,
          isTail: false,
          gapLimit: 2 * tolerance,
          quantileIndex: headIndex,
        );
    if (headBeyondSupported) signals.add(headBeyond);
    // 轴头硬边界：仅当轴尾同时越界（整轴平移的佐证）时才采信，
    // 避免把「片头安静开场」误判为轴偏移。
    if (headGapReliable && tailBeyondSupported) signals.add(-headGap);

    // --- 弹幕源错误判定 ---
    // 跨度（头尾分位之差）比「轴尾位置」更能反映轴的真实长度：
    // 跨度与时长比例失衡、差异超出可校准范围、大量弹幕越界、
    // 或正负信号同时显著（头尾空白无法用单一偏移同时修复）均判定换源。
    final spanRatio = span / durationSeconds;
    final hasPositive = signals.any((s) => s > 0);
    final hasNegative = signals.any((s) => s < 0);
    final bool sourceMismatch =
        (hasPositive && hasNegative) ||
        spanRatio >= sourceMismatchRatio ||
        spanRatio <= 1 / sourceMismatchRatio ||
        (span - durationSeconds).abs() > maxAdjustableOffsetSeconds ||
        beyondFraction >= beyondFractionThreshold;

    if (sourceMismatch) {
      return DanmakuAxisCheckResult(
        issue: DanmakuAxisIssue.sourceMismatch,
        axisLengthSeconds: tail,
        videoDurationSeconds: durationSeconds,
        differenceSeconds: difference,
        beyondFraction: beyondFraction,
        headGapSeconds: headGap,
        tailGapSeconds: tailGap,
        headGapReliable: headGapReliable,
        tailGapReliable: tailGapReliable,
      );
    }

    if (signals.isEmpty) {
      return DanmakuAxisCheckResult(
        issue: DanmakuAxisIssue.none,
        axisLengthSeconds: tail,
        videoDurationSeconds: durationSeconds,
        differenceSeconds: difference,
        beyondFraction: beyondFraction,
        headGapSeconds: headGap,
        tailGapSeconds: tailGap,
        headGapReliable: headGapReliable,
        tailGapReliable: tailGapReliable,
      );
    }

    // --- 同向信号按幅度加权融合为推荐偏移 ---
    var weightedSum = 0.0;
    var weightTotal = 0.0;
    for (final s in signals) {
      weightedSum += s * s.abs();
      weightTotal += s.abs();
    }
    final offset = (weightedSum / weightTotal).clamp(
      -maxAdjustableOffsetSeconds,
      maxAdjustableOffsetSeconds,
    );

    final maxAbs = signals.map((s) => s.abs()).reduce(max);
    final strength = (maxAbs / 45).clamp(0.0, 1.0);
    // 多个同向信号互相印证（如整轴平移会同时产生头空白 + 尾越界）
    // 时提升置信度；单一信号保持适度保守。
    final agreement = signals.length >= 2 ? 1.0 : 0.8;
    final confidence = ((0.55 + 0.45 * strength) * agreement).clamp(0.0, 1.0);

    return DanmakuAxisCheckResult(
      issue: DanmakuAxisIssue.axisOffset,
      axisLengthSeconds: tail,
      videoDurationSeconds: durationSeconds,
      differenceSeconds: difference,
      beyondFraction: beyondFraction,
      headGapSeconds: headGap,
      tailGapSeconds: tailGap,
      headGapReliable: headGapReliable,
      tailGapReliable: tailGapReliable,
      confidence: confidence,
      recommendedOffsetSeconds: offset,
    );
  }

  /// 判断边界附近是否为「硬边界」。
  ///
  /// 比较贴近边界的探查窗口与相邻等宽窗口（沿弹幕主体内部方向）的
  /// 弹幕数：
  /// - 近端密度骤降（比值 < [_edgeDecayRatio]）→ 自然稀疏尾；
  /// - 近端密度骤升（比值 > [_edgeSpikeRatio]）→ 弹幕群后戛然而止；
  /// - 密度平稳 → 内容持续到边界被截断，空白是轴偏移的可靠信号。
  ///
  /// [isTail] 为 false（轴头）时窗口方向翻转：近端窗口为
  /// [edge, edge + window]，相邻窗口为 [edge + window, edge + 2 * window)。
  /// 轴头方向相邻窗口若完全无弹幕，说明头部弹幕突发后沉寂（自然空窗
  /// 形态），不视为硬边界；轴尾方向池较短时相邻窗口可能为空，保留
  /// 「近端有实质弹幕即视为硬边界」的兜底。
  static bool _isHardEdge(
    List<double> sorted,
    double edge,
    double window, {
    required bool isTail,
  }) {
    final int nearStart, nearEnd, farStart, farEnd;
    if (isTail) {
      nearStart = _lowerBound(sorted, edge - window);
      nearEnd = _upperBound(sorted, edge);
      farStart = _lowerBound(sorted, edge - 2 * window);
      farEnd = nearStart;
    } else {
      nearStart = _lowerBound(sorted, edge);
      nearEnd = _upperBound(sorted, edge + window);
      farStart = nearEnd;
      farEnd = _upperBound(sorted, edge + 2 * window);
    }
    final nearCount = nearEnd - nearStart;
    final farCount = farEnd - farStart;
    if (nearCount < _edgeProbeMinCount) {
      return false;
    }
    if (farCount <= 0) {
      return isTail;
    }
    final ratio = nearCount / farCount;
    return ratio >= _edgeDecayRatio && ratio <= _edgeSpikeRatio;
  }

  /// 判断分位头部 / 尾部的越界是否为可信的「轴真实越界」。
  ///
  /// 分位取值可能被单条或小簇离群弹幕拉高 / 拉低（如观众在更长版本
  /// 视频里发的弹幕）。真实越界的形态是弹幕从主体边界连续延伸出视频
  /// 范围；孤立离群簇与主体之间存在明显空隙。判定条件：
  ///
  /// - 越界弹幕条数达到下限（至少 1 条，大样本按 [_beyondMinFraction]
  ///   比例提高门槛）；
  /// - 从弹幕主体到分位定义元素（[quantileIndex]）之间的相邻弹幕均
  ///   无明显空隙（单段间隔超过 [gapLimit] 视为孤立离群，不采信）。
  ///   仅检查最近一条越界弹幕会漏掉「近端桥接 + 远端离群」的组合，
  ///   使推荐幅度仍由远端离群决定。
  static bool _isBeyondClusterSupported(
    List<double> sorted,
    double boundary, {
    required bool isTail,
    required double gapLimit,
    required int quantileIndex,
  }) {
    final minCount = max(1, (sorted.length * _beyondMinFraction).ceil());
    final beyondCount = isTail
        ? sorted.length - _upperBound(sorted, boundary)
        : _lowerBound(sorted, boundary);
    if (beyondCount < minCount) {
      return false;
    }
    if (isTail) {
      final bodyEnd = _upperBound(sorted, boundary);
      if (bodyEnd <= 0) {
        // 整池越界：无空隙可算，交由弹幕源错误判定处理。
        return true;
      }
      for (var i = bodyEnd; i <= quantileIndex; i++) {
        if (sorted[i] - sorted[i - 1] > gapLimit) {
          return false;
        }
      }
      return true;
    } else {
      final bodyStart = _lowerBound(sorted, boundary);
      if (bodyStart >= sorted.length) {
        return true;
      }
      for (var i = quantileIndex + 1; i <= bodyStart; i++) {
        if (sorted[i] - sorted[i - 1] > gapLimit) {
          return false;
        }
      }
      return true;
    }
  }

  static int _lowerBound(List<double> sorted, double value) {
    var lo = 0;
    var hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid] < value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static int _upperBound(List<double> sorted, double value) {
    var lo = 0;
    var hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid] <= value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// 取排序数组的分位索引（[percentile] ∈ [0, 1]）。
  ///
  /// [roundUp] 为 true 时索引向上取整（用于轴头 P0.5）：保证小样本下
  /// 至少剔除首条弹幕，单条负时间戳离群不再直接成为轴头。轴尾 P99.5
  /// 保持四舍五入：保证「轴略长」场景的推荐幅度精度，分位被离群拉高
  /// 的假象由越界群采信校验（[_isBeyondClusterSupported]）兜底。
  static int _percentileIndex(
    int count,
    double percentile, {
    bool roundUp = false,
  }) {
    final raw = (count - 1) * percentile;
    return (roundUp ? raw.ceil() : raw.round()).clamp(0, count - 1);
  }
}
