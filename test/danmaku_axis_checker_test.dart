import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/utils/danmaku_axis_checker.dart';

void main() {
  DanmakuEntry danmakuAt(double time) {
    return DanmakuEntry(
      message: '测试',
      time: time,
      type: 1,
      color: Colors.white,
      source: '',
    );
  }

  /// 构造一条弹幕轴：主体均匀散布到 [axisLength]，末尾聚集一批弹幕
  /// （模拟 ED 弹幕群），使轴尾贴近真实时长。
  List<DanmakuEntry> buildAxis(double axisLength, {int count = 200}) {
    final times = <double>[];
    final body = count - 20;
    for (var i = 0; i < body; i++) {
      times.add(axisLength * i / (body - 1));
    }
    for (var i = 0; i < 20; i++) {
      times.add(axisLength);
    }
    return times.map(danmakuAt).toList();
  }

  group('DanmakuAxisChecker', () {
    test('空弹幕或未知时长不做判断', () {
      final empty = DanmakuAxisChecker.check(
        danmakus: const [],
        videoDuration: const Duration(minutes: 24),
      );
      expect(empty.issue, DanmakuAxisIssue.none);

      final unknownDuration = DanmakuAxisChecker.check(
        danmakus: buildAxis(1400),
        videoDuration: Duration.zero,
      );
      expect(unknownDuration.issue, DanmakuAxisIssue.none);
    });

    test('弹幕轴与视频时长吻合时判定为对齐', () {
      final result = DanmakuAxisChecker.check(
        danmakus: buildAxis(1438),
        videoDuration: const Duration(minutes: 24),
      );
      expect(result.issue, DanmakuAxisIssue.none);
    });

    test('弹幕轴在容差范围内不误报', () {
      final result = DanmakuAxisChecker.check(
        danmakus: buildAxis(1440 + 8),
        videoDuration: const Duration(minutes: 24),
      );
      expect(result.issue, DanmakuAxisIssue.none);
    });

    test('弹幕轴略长于视频判定为轴错误并推荐提前', () {
      final result = DanmakuAxisChecker.check(
        danmakus: buildAxis(1500),
        videoDuration: const Duration(minutes: 24),
      );
      expect(result.issue, DanmakuAxisIssue.axisOffset);
      expect(result.differenceSeconds, closeTo(60, 0.01));
      expect(result.recommendedOffsetSeconds, closeTo(-60, 0.01));
    });

    test('弹幕轴略短于视频判定为轴错误并推荐延后', () {
      final result = DanmakuAxisChecker.check(
        danmakus: buildAxis(1380),
        videoDuration: const Duration(minutes: 24),
      );
      expect(result.issue, DanmakuAxisIssue.axisOffset);
      expect(result.differenceSeconds, closeTo(-60, 0.01));
      expect(result.recommendedOffsetSeconds, closeTo(60, 0.01));
    });

    test('弹幕轴远长于视频（合集弹幕）判定为弹幕源错误', () {
      final result = DanmakuAxisChecker.check(
        danmakus: buildAxis(2880),
        videoDuration: const Duration(minutes: 24),
      );
      expect(result.issue, DanmakuAxisIssue.sourceMismatch);
      expect(result.axisLengthSeconds, closeTo(2880, 0.01));
    });

    test('差异超过可校准范围判定为弹幕源错误', () {
      final result = DanmakuAxisChecker.check(
        danmakus: buildAxis(1440 + 200),
        videoDuration: const Duration(minutes: 24),
      );
      expect(result.issue, DanmakuAxisIssue.sourceMismatch);
    });

    test('弹幕轴远短于视频判定为弹幕源错误', () {
      final result = DanmakuAxisChecker.check(
        danmakus: buildAxis(500),
        videoDuration: const Duration(minutes: 24),
      );
      expect(result.issue, DanmakuAxisIssue.sourceMismatch);
    });

    test('离群弹幕时间戳不放大轴长度', () {
      final axis = buildAxis(1500);
      axis.add(danmakuAt(999999));
      final result = DanmakuAxisChecker.check(
        danmakus: axis,
        videoDuration: const Duration(minutes: 24),
      );
      expect(result.issue, DanmakuAxisIssue.axisOffset);
      expect(result.axisLengthSeconds, closeTo(1500, 0.01));
    });
  });
}
