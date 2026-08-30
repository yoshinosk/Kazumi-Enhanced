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

  /// 构造一条均匀分布的弹幕轴。
  ///
  /// count 取 101 使 P99.5 分位恰好落在轴尾、P0.5 分位落在首条弹幕之后，
  /// 且全程密度平稳，不会触发「自然空窗」的形态判别。
  List<DanmakuEntry> buildAxis(double axisLength, {int count = 101}) {
    final times = <double>[];
    for (var i = 0; i < count; i++) {
      times.add(axisLength * i / (count - 1));
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

    test('弹幕样本过少时不做判断', () {
      final result = DanmakuAxisChecker.check(
        danmakus: buildAxis(500, count: 20),
        videoDuration: const Duration(minutes: 24),
      );
      expect(result.issue, DanmakuAxisIssue.none);
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
      expect(result.confidence, inInclusiveRange(0, 1));
    });

    test('弹幕轴略短于视频判定为轴错误并推荐延后', () {
      final result = DanmakuAxisChecker.check(
        danmakus: buildAxis(1380),
        videoDuration: const Duration(minutes: 24),
      );
      expect(result.issue, DanmakuAxisIssue.axisOffset);
      expect(result.differenceSeconds, closeTo(-60, 0.01));
      expect(result.recommendedOffsetSeconds, closeTo(60, 0.01));
      expect(result.tailGapReliable, isTrue);
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

    group('密度形态与信号融合', () {
      test('片尾弹幕自然稀疏（衰减尾）不误报轴偏移', () {
        // 正片弹幕均匀分布到 1330s，最后 110s 只有零星几条且逐渐稀疏，
        // 模拟 ED 阶段无人发弹幕：轴尾空白属于自然空窗，不应推荐偏移。
        final times = <double>[];
        for (var i = 0; i < 390; i++) {
          times.add(1330 * i / 389);
        }
        for (final t in const [1330.0, 1352.0, 1374.0, 1396.0, 1418.0, 1440.0]) {
          times.add(t);
        }
        final result = DanmakuAxisChecker.check(
          danmakus: times.map(danmakuAt).toList(),
          videoDuration: const Duration(minutes: 24),
        );
        expect(result.issue, DanmakuAxisIssue.none);
        expect(result.tailGapReliable, isFalse);
      });

      test('ED 弹幕群后片尾沉寂（尖峰尾）不误报轴偏移', () {
        // 正片弹幕均匀分布到 1300s，ED 开始时出现一批弹幕群后彻底沉寂：
        // 尖峰后截断是典型的片尾形态，不应据此推荐延后。
        final times = <double>[];
        for (var i = 0; i < 360; i++) {
          times.add(1300 * i / 359);
        }
        for (var i = 0; i < 40; i++) {
          times.add(1350);
        }
        final result = DanmakuAxisChecker.check(
          danmakus: times.map(danmakuAt).toList(),
          videoDuration: const Duration(minutes: 24),
        );
        expect(result.issue, DanmakuAxisIssue.none);
        expect(result.tailGapReliable, isFalse);
      });

      test('片头安静开场不误报轴偏移', () {
        // 弹幕从 60s 才开始且轴尾贴齐视频结尾：安静开场不构成整轴平移
        // 的证据（轴尾无越界佐证），不应推荐提前。
        final times = <double>[];
        for (var i = 0; i < 101; i++) {
          times.add(60 + 1380 * i / 100);
        }
        final result = DanmakuAxisChecker.check(
          danmakus: times.map(danmakuAt).toList(),
          videoDuration: const Duration(minutes: 24),
        );
        expect(result.issue, DanmakuAxisIssue.none);
        expect(result.headGapSeconds, closeTo(73.8, 0.1));
      });

      test('整轴平移（轴头空白 + 轴尾越界互相印证）推荐提前', () {
        // 弹幕时间戳整体后移 60s：轴头出现硬空白、轴尾同时越界，
        // 两个同向信号互相印证，应融合出负偏移（提前）。
        final times = <double>[];
        for (var i = 0; i < 101; i++) {
          times.add(60 + 1440 * i / 100);
        }
        final result = DanmakuAxisChecker.check(
          danmakus: times.map(danmakuAt).toList(),
          videoDuration: const Duration(minutes: 24),
        );
        expect(result.issue, DanmakuAxisIssue.axisOffset);
        expect(result.recommendedOffsetSeconds, closeTo(-68, 1.5));
        expect(result.confidence, closeTo(1.0, 0.01));
      });

      test('头尾越界方向冲突判定为弹幕源错误', () {
        // 弹幕轴两端均超出视频范围：单一偏移无法同时修复头尾，
        // 应判定为弹幕源错误而非推荐偏移。
        final times = <double>[];
        for (var i = 0; i < 101; i++) {
          times.add(-60 + 1560 * i / 100);
        }
        final result = DanmakuAxisChecker.check(
          danmakus: times.map(danmakuAt).toList(),
          videoDuration: const Duration(minutes: 24),
        );
        expect(result.issue, DanmakuAxisIssue.sourceMismatch);
      });
    });
  });
}
