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

      test('ED 后稀疏尾延伸到视频结尾不误报轴偏移', () {
        // 真实场景（药屋 EP35/36）：正片弹幕到 ~1330s，ED 附近有弹幕群，
        // 之后仅零星几条（<0.5%）落到视频结尾甚至略超出（更长版本的
        // 观众）。P99.5 轴尾空白只是自然稀疏尾，不应推荐延后。
        final times = <double>[];
        for (var i = 0; i < 960; i++) {
          times.add(1330 * i / 959);
        }
        // ED 弹幕群
        for (var i = 0; i < 40; i++) {
          times.add(1280 + i * 2.0);
        }
        // 稀疏尾：零星弹幕一直延伸到结尾及略超出（更长版本的观众）
        times.addAll([1415.0, 1446.0, 1545.0, 2095.0]);
        final result = DanmakuAxisChecker.check(
          danmakus: times.map(danmakuAt).toList(),
          videoDuration: const Duration(minutes: 24),
        );
        expect(result.issue, DanmakuAxisIssue.none);
        expect(result.tailGapReliable, isFalse);
      });

      test('真实短轴（硬截断）仍推荐延后', () {
        // 弹幕均匀分布到 1380s 后彻底消失（无结尾覆盖），只有一条离群
        // 弹幕在 1500s：轴尾空白是硬截断，应推荐延后 60s。
        final times = <double>[];
        for (var i = 0; i < 101; i++) {
          times.add(1380 * i / 100);
        }
        times.add(1500.0);
        final result = DanmakuAxisChecker.check(
          danmakus: times.map(danmakuAt).toList(),
          videoDuration: const Duration(minutes: 24),
        );
        expect(result.issue, DanmakuAxisIssue.axisOffset);
        expect(result.recommendedOffsetSeconds, closeTo(60, 0.01));
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

      test('尾部单条离群弹幕不触发越界推荐', () {
        // 弹幕池贴齐视频结尾，仅一条弹幕落在结尾之外 120s（观众在更长
        // 版本里发言）：分位尾被拉高，但越界群与主体间空隙明显，不应
        // 推荐提前。
        final axis = buildAxis(1440, count: 80);
        axis.add(danmakuAt(1560));
        final result = DanmakuAxisChecker.check(
          danmakus: axis,
          videoDuration: const Duration(minutes: 24),
        );
        expect(result.issue, DanmakuAxisIssue.none);
      });

      test('头部单条离群弹幕不触发越界推荐', () {
        // 弹幕池从视频起点铺到结尾，仅一条 -120s 的负时间戳弹幕：
        // P0.5 分位至少剔除一条后轴头贴齐起点，不应推荐延后。
        final axis = buildAxis(1440, count: 80);
        axis.add(danmakuAt(-120));
        final result = DanmakuAxisChecker.check(
          danmakus: axis,
          videoDuration: const Duration(minutes: 24),
        );
        expect(result.issue, DanmakuAxisIssue.none);
      });

      test('尾部离群簇（与主体存在空隙）不触发越界推荐', () {
        // 弹幕池贴齐视频结尾，60s 空隙后出现一小簇越界弹幕（下一集
        // 片头弹幕混入的典型形态）：空隙超过 2 倍容差不采信。
        final times = <double>[
          ...List.generate(75, (i) => 1440 * i / 74),
          1500, 1512, 1530, 1545, 1560,
        ];
        final result = DanmakuAxisChecker.check(
          danmakus: times.map(danmakuAt).toList(),
          videoDuration: const Duration(minutes: 24),
        );
        expect(result.issue, DanmakuAxisIssue.none);
      });

      test('轴连续延伸越界的小样本仍推荐提前', () {
        // 61 条弹幕均匀铺满 [0, 1500]：轴整体长于视频 60s，越界段与
        // 主体连续（无空隙），应采信并推荐提前 60s。
        final times = List.generate(61, (i) => 1500 * i / 60);
        final result = DanmakuAxisChecker.check(
          danmakus: times.map(danmakuAt).toList(),
          videoDuration: const Duration(minutes: 24),
        );
        expect(result.issue, DanmakuAxisIssue.axisOffset);
        expect(result.recommendedOffsetSeconds, closeTo(-60, 0.01));
      });

      test('小样本整轴平移仍推荐提前', () {
        // 冷门番 40 条弹幕整体后移 60s：越界段仅含 1 条弹幕，但与主体
        // 连续，应采信越界信号并结合轴头空白给出提前修正。
        final times = List.generate(40, (i) => 60 + 1440 * i / 39);
        final result = DanmakuAxisChecker.check(
          danmakus: times.map(danmakuAt).toList(),
          videoDuration: const Duration(minutes: 24),
        );
        expect(result.issue, DanmakuAxisIssue.axisOffset);
        expect(result.recommendedOffsetSeconds, inInclusiveRange(-95, -60));
      });

      test('头部连续越界段仍推荐延后', () {
        // 弹幕池头部含 -60~0 的连续越界段（长版本片头的典型形态）：
        // 越界群与主体连续，应采信并推荐延后修正。
        final times = List.generate(101, (i) => -60 + 1500 * i / 100);
        final result = DanmakuAxisChecker.check(
          danmakus: times.map(danmakuAt).toList(),
          videoDuration: const Duration(minutes: 24),
        );
        expect(result.issue, DanmakuAxisIssue.axisOffset);
        expect(result.recommendedOffsetSeconds, inInclusiveRange(30, 60));
      });
    });
  });
}
