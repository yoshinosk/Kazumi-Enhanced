import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/magnet/magnet_download_service.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';

TorrentInfo _info({
  required int id,
  TorrentState state = TorrentState.finished,
  double progress = 0,
  int totalDone = 0,
  int totalWanted = 0,
  int downloadRate = 0,
  int uploadRate = 0,
  int totalUploaded = 0,
  bool hasMetadata = true,
  bool isFinished = false,
  bool isPaused = false,
  String name = '',
}) {
  return TorrentInfo(
    id: id,
    name: name,
    savePath: '',
    errorMsg: '',
    state: state,
    progress: progress,
    downloadRate: downloadRate,
    uploadRate: uploadRate,
    totalDone: totalDone,
    totalWanted: totalWanted,
    totalUploaded: totalUploaded,
    numPeers: 0,
    numSeeds: 0,
    isPaused: isPaused,
    isFinished: isFinished,
    hasMetadata: hasMetadata,
    queuePosition: 0,
  );
}

MagnetDownloadEntry _entry({
  int totalLength = 0,
  int completedLength = 0,
  int verifiedLength = 0,
  double? restartFloor,
}) {
  final e = MagnetDownloadEntry(
    sessionGid: '1',
    title: 'T',
    sourceUri: 'magnet:?xt=urn:btih:abc',
    addedAt: DateTime(2026, 1, 1),
    totalLength: totalLength,
    completedLength: completedLength,
    verifiedLength: verifiedLength,
  );
  e.restartFloorForTest = restartFloor;
  return e;
}

void main() {
  final now = DateTime(2026, 1, 1, 12);

  group('applyTorrentStatus - pre-metadata', () {
    test('preserves totalLength and progress when metadata missing', () {
      final e =
          _entry(totalLength: 1000, completedLength: 500, verifiedLength: 500);
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
          id: 1,
          state: TorrentState.downloading, // 原生 downloading_metadata
          hasMetadata: false,
        ),
        'metadata',
        now,
      );
      expect(e.status, 'metadata');
      expect(e.totalLength, 1000);
      expect(e.completedLength, 500);
      expect(e.verifiedLength, 500);
      expect(e.progress, closeTo(0.5, 1e-9));
    });

    test('fresh task stays at zero before metadata', () {
      final e = _entry();
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, hasMetadata: false),
        'metadata',
        now,
      );
      expect(e.totalLength, 0);
      expect(e.completedLength, 0);
    });
  });

  group('applyTorrentStatus - active download (same session)', () {
    test('verifiedLength tracks engine totalDone, smoothing advances', () {
      final e =
          _entry(totalLength: 1000, completedLength: 0, verifiedLength: 0);
      // 第一次采样：对齐 verified
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, totalDone: 100, totalWanted: 1000, downloadRate: 100),
        'active',
        now,
      );
      expect(e.verifiedLength, 100);
      expect(e.completedLength, 100);
      // 第二次采样：按速度推进，且不越过「已验证 + 在途窗口」
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 100,
            totalWanted: 1000,
            downloadRate: 100,
            progress: 0.1),
        'active',
        now.add(const Duration(seconds: 1)),
      );
      expect(e.completedLength, greaterThan(100));
      expect(e.completedLength, lessThanOrEqualTo(100 + 100 * 3));
    });

    test('adopts totalWanted once metadata arrives', () {
      final e =
          _entry(totalLength: 1000, completedLength: 500, verifiedLength: 500);
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            state: TorrentState.finished, // 原生 downloading
            totalDone: 0,
            totalWanted: 2000,
            hasMetadata: true),
        'active',
        now,
      );
      expect(e.totalLength, 2000);
      expect(e.verifiedLength, 0);
    });
  });

  group('applyTorrentStatus - complete', () {
    test('pins progress to totalLength', () {
      final e =
          _entry(totalLength: 1000, completedLength: 999, verifiedLength: 990)
            ..totalUploaded = 2000; // 做种率 ≥ 1 → 已完成
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            totalUploaded: 2000,
            isFinished: true,
            progress: 1.0),
        'complete',
        now,
      );
      expect(e.status, 'complete');
      expect(e.completedLength, 1000);
      expect(e.verifiedLength, 1000);
      expect(e.progress, 1.0);
    });

    test('zeroes residual download speed on completion', () {
      final e =
          _entry(totalLength: 1000, completedLength: 999, verifiedLength: 990)
            ..downloadSpeed = 5242880
            ..uploadSpeed = 1024
            ..totalUploaded = 1000; // 做种率 ≥ 1 → 已完成
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            downloadRate: 5311492,
            uploadRate: 2048,
            totalUploaded: 1000,
            isFinished: true,
            progress: 1.0),
        'complete',
        now,
      );
      expect(e.downloadSpeed, 0);
      // 已完成任务已从引擎移除停止做种，上传速度一并清零
      expect(e.uploadSpeed, 0);
      expect(e.etaSeconds, -1);
    });

    test('finished download with ratio below 1 becomes seeding', () {
      final e =
          _entry(totalLength: 1000, completedLength: 999, verifiedLength: 990)
            ..downloadSpeed = 5242880
            ..uploadSpeed = 1024
            ..totalUploaded = 500; // 做种率 0.5 < 1 → 做种中
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            downloadRate: 5311492,
            uploadRate: 2048,
            totalUploaded: 500,
            isFinished: true,
            progress: 1.0),
        'complete',
        now,
      );
      expect(e.status, 'seeding');
      expect(e.progress, 1.0); // 下载已完成，进度对齐 100%
      expect(e.completedLength, 1000);
      expect(e.downloadSpeed, 0);
      expect(e.uploadSpeed, 2048); // 做种上传速度保留展示
      expect(e.isSeeding, isTrue);
      expect(e.isActive, isTrue);
      expect(e.isCompleted, isFalse);
    });

    test('seeding flips to complete when ratio reaches 1', () {
      final e =
          _entry(totalLength: 1000, completedLength: 1000, verifiedLength: 1000)
            ..totalUploaded = 500;
      // 做种中：做种率 0.5
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            totalUploaded: 500,
            isFinished: true,
            progress: 1.0),
        'complete',
        now,
      );
      expect(e.status, 'seeding');
      // 做种率达标后切换为已完成
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            totalUploaded: 1000,
            isFinished: true,
            progress: 1.0),
        'complete',
        now.add(const Duration(seconds: 1)),
      );
      expect(e.status, 'complete');
      expect(e.isCompleted, isTrue);
      expect(e.isSeeding, isFalse);
    });

    test('keeps accumulated upload ratio across engine restarts', () {
      final e =
          _entry(totalLength: 1000, completedLength: 1000, verifiedLength: 1000)
            ..totalUploaded = 800; // 持久化的累计上传量
      // 引擎新会话从 0 起计，不能覆盖累计上传量（否则做种率消失）
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            totalUploaded: 0,
            isFinished: true,
            progress: 1.0),
        'complete',
        now,
      );
      expect(e.totalUploaded, 800);
      expect(e.seedRatio, closeTo(0.8, 1e-9));
      // 本会话内上传继续累计
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            totalUploaded: 950,
            isFinished: true,
            progress: 1.0),
        'complete',
        now.add(const Duration(seconds: 1)),
      );
      expect(e.totalUploaded, 950);
      expect(e.status, 'seeding'); // 做种率 0.95 < 1
    });

    test('zeroes both speeds on error', () {
      final e =
          _entry(totalLength: 1000, completedLength: 100, verifiedLength: 100)
            ..downloadSpeed = 1024
            ..uploadSpeed = 512;
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, totalDone: 100, totalWanted: 1000, downloadRate: 1024),
        'error',
        now,
      );
      expect(e.downloadSpeed, 0);
      expect(e.uploadSpeed, 0);
    });
  });

  group('applyTorrentStatus - restart blend', () {
    test('progress stays at floor when engine restarts from zero', () {
      final e =
          _entry(totalLength: 1000, completedLength: 500, verifiedLength: 500);
      e.restartFloorForTest = 0.5;
      // 元数据阶段：引擎 totalDone=0
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, hasMetadata: false),
        'metadata',
        now,
      );
      expect(e.progress, closeTo(0.5, 1e-9));
      // 引擎开始重新下载（从 0 起）
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, totalDone: 0, totalWanted: 1000),
        'active',
        now,
      );
      expect(e.progress, closeTo(0.5, 1e-9));
    });

    test('blends floor with engine progress (no freeze, no wipe)', () {
      final e =
          _entry(totalLength: 1000, completedLength: 500, verifiedLength: 500);
      e.restartFloorForTest = 0.5;
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, totalDone: 100, totalWanted: 1000),
        'active',
        now,
      );
      // 0.5 + 0.5 * 0.1 = 0.55
      expect(e.progress, closeTo(0.55, 1e-9));
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, totalDone: 500, totalWanted: 1000),
        'active',
        now.add(const Duration(seconds: 1)),
      );
      // 0.5 + 0.5 * 0.5 = 0.75
      expect(e.progress, closeTo(0.75, 1e-9));
    });

    test('blend completes at 100% and pins on complete', () {
      final e =
          _entry(totalLength: 1000, completedLength: 500, verifiedLength: 500);
      e.restartFloorForTest = 0.5;
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            isFinished: true,
            progress: 1.0),
        'complete',
        now,
      );
      expect(e.progress, 1.0);
      expect(e.completedLength, 1000);
    });

    test('blended verifiedLength is persisted for next restart floor', () {
      final e =
          _entry(totalLength: 1000, completedLength: 500, verifiedLength: 500);
      e.restartFloorForTest = 0.5;
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, totalDone: 300, totalWanted: 1000),
        'active',
        now,
      );
      // 0.5 + 0.5 * 0.3 = 0.65 → verifiedLength 650
      expect(e.verifiedLength, 650);
      final restored = MagnetDownloadEntry.fromJson(
        Map<String, dynamic>.from(e.toJson()),
      );
      expect(restored.completedLength, 650);
      expect(restored.progress, closeTo(0.65, 1e-9));
    });

    test('caps persisted value below totalLength (no fake 100%)', () {
      final e =
          _entry(totalLength: 1000, completedLength: 500, verifiedLength: 500);
      e.restartFloorForTest = 0.5;
      // engineRatio = 1.0 → blended = 1.0 → round → 1000 → 封顶 999
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, totalDone: 1000, totalWanted: 1000),
        'active',
        now,
      );
      expect(e.verifiedLength, 999);
      expect(e.progress, lessThan(1.0));
      // 持久化往返后仍 < 100%，重启 floor 永不等于 1
      final restored = MagnetDownloadEntry.fromJson(
        Map<String, dynamic>.from(e.toJson()),
      );
      expect(restored.progress, lessThan(1.0));
      // 引擎真正完成后 complete 分支对齐 100%
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            isFinished: true,
            progress: 1.0),
        'complete',
        now,
      );
      expect(e.progress, 1.0);
    });

    test('hides download speed during recovery phase, shows after catch-up',
        () {
      final e =
          _entry(totalLength: 1000, completedLength: 600, verifiedLength: 600)
            ..restartFloorForTest = 0.6;
      // 恢复期：floor=0.6，引擎才下到 10% → blended 0.64，差 0.54 > 0.1
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, totalDone: 100, totalWanted: 1000, downloadRate: 5242880),
        'active',
        now,
      );
      expect(e.downloadSpeed, 0);
      // 引擎追近：E=0.9 → blended 0.96，差 0.06 ≤ 0.1 → 恢复显示速度
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, totalDone: 900, totalWanted: 1000, downloadRate: 5242880),
        'active',
        now.add(const Duration(seconds: 1)),
      );
      expect(e.downloadSpeed, 5242880);
    });

    test('blend branch smooths progress between samples', () {
      final e =
          _entry(totalLength: 1000, completedLength: 500, verifiedLength: 500);
      e.restartFloorForTest = 0.5;
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, totalDone: 100, totalWanted: 1000, downloadRate: 100),
        'active',
        now,
      );
      // 首次采样：对齐 target = 550
      expect(e.completedLength, 550);
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, totalDone: 100, totalWanted: 1000, downloadRate: 100),
        'active',
        now.add(const Duration(seconds: 1)),
      );
      // 按速度推进 100B，且不超过 target + rate×3s 在途窗口
      expect(e.completedLength, greaterThan(550));
      expect(e.completedLength, lessThanOrEqualTo(550 + 100 * 3));
    });
  });

  group('applyTorrentStatus - totalLength', () {
    test('only increases totalLength (no percent jump on shrink)', () {
      final e = _entry();
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, totalDone: 0, totalWanted: 2000, hasMetadata: true),
        'active',
        now,
      );
      expect(e.totalLength, 2000);
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, totalDone: 0, totalWanted: 1500, hasMetadata: true),
        'active',
        now,
      );
      expect(e.totalLength, 2000);
    });
  });

  group('MagnetDownloadEntry progress', () {
    test('progress is 0 when totalLength is unknown (pre-metadata)', () {
      final entry = MagnetDownloadEntry(
        sessionGid: '1',
        title: 'T',
        sourceUri: 'magnet:?xt=urn:btih:abc',
        addedAt: DateTime(2026, 1, 1),
        totalLength: 0,
        completedLength: 0,
      );
      expect(entry.progress, 0.0);
    });

    test('etaSeconds returns -1 when totalLength unknown even with speed', () {
      final entry = MagnetDownloadEntry(
        sessionGid: '1',
        title: 'T',
        sourceUri: 'magnet:?xt=urn:btih:abc',
        addedAt: DateTime(2026, 1, 1),
        status: 'metadata',
        totalLength: 0,
        completedLength: 0,
        downloadSpeed: 5242880, // 元数据下载流量
      );
      // 修复前 remaining = 0 - 0 = 0，会返回 0，UI 误显示「剩余 0 秒」
      expect(entry.etaSeconds, -1);
      expect(entry.isActive, isTrue);
    });

    test('etaSeconds is 0 when download just finished', () {
      final entry = MagnetDownloadEntry(
        sessionGid: '1',
        title: 'T',
        sourceUri: 'magnet:?xt=urn:btih:abc',
        addedAt: DateTime(2026, 1, 1),
        totalLength: 1000,
        completedLength: 1000,
        verifiedLength: 1000,
        downloadSpeed: 10,
      );
      expect(entry.etaSeconds, 0);
    });

    test('progress keeps persisted ratio when totalLength retained', () {
      final entry = MagnetDownloadEntry(
        sessionGid: '1',
        title: 'T',
        sourceUri: 'magnet:?xt=urn:btih:abc',
        addedAt: DateTime(2026, 1, 1),
        totalLength: 1000,
        completedLength: 500,
        verifiedLength: 500,
        downloadSpeed: 10,
      );
      expect(entry.progress, closeTo(0.5, 1e-9));
      expect(entry.etaSeconds, 50); // 500 / 10
    });

    test('seedRatio uses verified (real) bytes, not smoothed estimate', () {
      final entry = MagnetDownloadEntry(
        sessionGid: '1',
        title: 'T',
        sourceUri: 'magnet:?xt=urn:btih:abc',
        addedAt: DateTime(2026, 1, 1),
        totalLength: 1000,
        completedLength: 250,
        verifiedLength: 200,
        totalUploaded: 100,
      );
      // 100 / 200 = 0.5，而非偏乐观的 100 / 250 = 0.4
      expect(entry.seedRatio, closeTo(0.5, 1e-9));
    });
  });

  group('applyTorrentStatus - reseed (remounted seeding)', () {
    test('keeps 100% during disk check, ignores engine totalDone climb', () {
      final e =
          _entry(totalLength: 1000, completedLength: 1000, verifiedLength: 1000)
            ..reseedForTest = true;
      // 校验期：引擎 totalDone 从 0 爬升（校验进度）
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            state: TorrentState.downloadingMetadata, // 原生 checking_files
            totalDone: 300,
            totalWanted: 1000,
            downloadRate: 5242880,
            hasMetadata: true),
        'checking',
        now,
      );
      expect(e.completedLength, 1000);
      expect(e.verifiedLength, 1000);
      expect(e.progress, 1.0);
      expect(e.downloadSpeed, 0); // 校验期不显示下载速度
    });

    test('clears reseed and resumes normal logic after check', () {
      final e =
          _entry(totalLength: 1000, completedLength: 1000, verifiedLength: 1000)
            ..reseedForTest = true
            ..totalUploaded = 500;
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            totalUploaded: 0,
            isFinished: true,
            progress: 1.0),
        'complete',
        now,
      );
      // 校验结束 → 做种中（做种率 0.5 < 1），_reseed 清除
      expect(e.status, 'seeding');
      expect(e.completedLength, 1000);
    });

    test('accumulates uploads from historical base plus this session', () {
      final e =
          _entry(totalLength: 1000, completedLength: 1000, verifiedLength: 1000)
            ..uploadBaseForTest = 800 // 历史上传基数（reconcile 时记录）
            ..totalUploaded = 800;
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(id: 1, totalDone: 1000, totalWanted: 1000, totalUploaded: 100),
        'active',
        now,
      );
      expect(e.totalUploaded, 900); // 800 基数 + 100 本会话新增
      expect(e.seedRatio, closeTo(0.9, 1e-9));
    });
  });

  group('applyTorrentStatus - seeding stop criteria', () {
    test('ratio mode with custom threshold', () {
      final e =
          _entry(totalLength: 1000, completedLength: 1000, verifiedLength: 1000)
            ..totalUploaded = 400; // 分享率 0.4
      // 阈值 0.5：0.4 < 0.5 → 做种中
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            totalUploaded: 400,
            isFinished: true,
            progress: 1.0),
        'complete',
        now,
        seedingStopRatio: 0.5,
      );
      expect(e.status, 'seeding');
      // 上传到 0.6 ≥ 0.5 → 已完成
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            totalUploaded: 600,
            isFinished: true,
            progress: 1.0),
        'complete',
        now.add(const Duration(seconds: 1)),
        seedingStopRatio: 0.5,
      );
      expect(e.status, 'complete');
    });

    test('time mode: seeds within duration, completes after', () {
      final e =
          _entry(totalLength: 1000, completedLength: 1000, verifiedLength: 1000)
            ..seedingStartedAtForTest = now;
      // 做种 1 小时后停止；当前未满 → 做种中
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            isFinished: true,
            progress: 1.0),
        'complete',
        now.add(const Duration(minutes: 30)),
        seedingStopMode: 'time',
        seedingStopHours: 1,
      );
      expect(e.status, 'seeding');
      // 已满 1 小时 → 已完成
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            isFinished: true,
            progress: 1.0),
        'complete',
        now.add(const Duration(hours: 1, minutes: 1)),
        seedingStopMode: 'time',
        seedingStopHours: 1,
      );
      expect(e.status, 'complete');
    });

    test('time mode without start time stays seeding until recorded', () {
      final e = _entry(
          totalLength: 1000, completedLength: 1000, verifiedLength: 1000);
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            isFinished: true,
            progress: 1.0),
        'complete',
        now,
        seedingStopMode: 'time',
        seedingStopHours: 1,
      );
      expect(e.status, 'seeding');
    });

    test('none mode never completes automatically', () {
      final e =
          _entry(totalLength: 1000, completedLength: 1000, verifiedLength: 1000)
            ..totalUploaded = 2000; // 分享率已达标也不停
      MagnetDownloadService.applyTorrentStatus(
        e,
        _info(
            id: 1,
            totalDone: 1000,
            totalWanted: 1000,
            totalUploaded: 2000,
            isFinished: true,
            progress: 1.0),
        'complete',
        now,
        seedingStopMode: 'none',
      );
      expect(e.status, 'seeding');
    });

    test('seedingStartedAt persists across restart', () {
      final e =
          _entry(totalLength: 1000, completedLength: 1000, verifiedLength: 1000)
            ..seedingStartedAtForTest = now
            ..status = 'seeding';
      final restored = MagnetDownloadEntry.fromJson(
        Map<String, dynamic>.from(e.toJson()),
      );
      expect(restored.status, 'seeding');
      expect(restored.seedingStartedAt, now);
    });
  });

  group('MagnetDownloadService file guard', () {
    test('isFileIntact detects existing and missing files', () {
      final dir = Directory.systemTemp.createTempSync('kazumi_guard');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}${Platform.pathSeparator}ep01.mkv');
      f.writeAsBytesSync(List<int>.filled(16, 1));

      final existing = _entry();
      existing
        ..savePath = dir.path
        ..fileName = 'ep01.mkv';
      expect(MagnetDownloadService.isFileIntactForTest(existing), isTrue);

      final missing = _entry();
      missing
        ..savePath = dir.path
        ..fileName = 'ep02.mkv';
      expect(MagnetDownloadService.isFileIntactForTest(missing), isFalse);

      final empty = _entry();
      expect(MagnetDownloadService.isFileIntactForTest(empty), isFalse);
    });

    test('checks every selected file in a multi-file torrent', () {
      final dir = Directory.systemTemp.createTempSync('kazumi_multi_guard');
      addTearDown(() => dir.delete(recursive: true));
      final season = Directory('${dir.path}${Platform.pathSeparator}Season 1')
        ..createSync();
      File('${season.path}${Platform.pathSeparator}01.mkv')
          .writeAsBytesSync(List<int>.filled(4, 1));
      File('${season.path}${Platform.pathSeparator}02.mkv')
          .writeAsBytesSync(List<int>.filled(8, 1));

      final entry = _entry()
        ..savePath = dir.path
        ..fileName = 'Season 1'
        ..files = const [
          MagnetDownloadFile(
            index: 0,
            name: '01.mkv',
            path: 'Season 1/01.mkv',
            size: 4,
            isStreamable: true,
          ),
          MagnetDownloadFile(
            index: 1,
            name: '02.mkv',
            path: 'Season 1/02.mkv',
            size: 8,
            isStreamable: true,
          ),
        ];
      expect(MagnetDownloadService.isFileIntactForTest(entry), isTrue);

      File('${season.path}${Platform.pathSeparator}02.mkv').deleteSync();
      expect(MagnetDownloadService.isFileIntactForTest(entry), isFalse);

      entry.selectedFileIndexes = [0];
      expect(MagnetDownloadService.isFileIntactForTest(entry), isTrue);
    });
  });

  group('MagnetDownloadService state mapping', () {
    test('uses native libtorrent state values without an offset', () {
      expect(
        MagnetDownloadService.mapStatusForTest(_info(
          id: 1,
          state: TorrentState.downloadingMetadata,
          hasMetadata: false,
        )),
        'metadata',
      );
      expect(
        MagnetDownloadService.mapStatusForTest(_info(
          id: 1,
          state: TorrentState.checkingFiles,
          hasMetadata: true,
        )),
        'checking',
      );
      expect(
        MagnetDownloadService.mapStatusForTest(_info(
          id: 1,
          state: TorrentState.downloading,
          hasMetadata: true,
        )),
        'active',
      );
    });
  });

  group('MagnetDownloadEntry hasCompleteFiles', () {
    MagnetDownloadEntry mk(String status,
        {int totalLength = 0, int verifiedLength = 0}) {
      return MagnetDownloadEntry(
        sessionGid: '1',
        title: 'T',
        sourceUri: 'magnet:?xt=urn:btih:abc',
        addedAt: DateTime(2026, 1, 1),
        status: status,
        totalLength: totalLength,
        verifiedLength: verifiedLength,
      );
    }

    test('complete and seeding tasks are always playable', () {
      expect(mk('complete').hasCompleteFiles, isTrue);
      expect(mk('seeding').hasCompleteFiles, isTrue);
    });

    test('paused after download finished is playable', () {
      // 做种中被暂停：进入完成态时 verifiedLength 已对齐总量并持久化。
      final e = mk('paused', totalLength: 1000, verifiedLength: 1000);
      expect(e.hasCompleteFiles, isTrue);
    });

    test('paused mid-download is not playable locally', () {
      final e = mk('paused', totalLength: 1000, verifiedLength: 400);
      expect(e.hasCompleteFiles, isFalse);
    });

    test('active / queued / error tasks without full data are not playable',
        () {
      expect(
          mk('active', totalLength: 1000, verifiedLength: 999).hasCompleteFiles,
          isFalse);
      expect(mk('queued').hasCompleteFiles, isFalse);
      expect(mk('error').hasCompleteFiles, isFalse);
    });

    test('unknown total size never counts as finished', () {
      expect(mk('waiting').hasCompleteFiles, isFalse);
    });
  });

  group('MagnetDownloadEntry persistence', () {
    test('toJson persists verifiedLength as completedLength for resume', () {
      final entry = MagnetDownloadEntry(
        sessionGid: '1',
        title: 'Test Episode',
        sourceUri: 'magnet:?xt=urn:btih:abc',
        addedAt: DateTime(2026, 1, 1),
        savePath: r'C:\Downloads',
        status: 'active',
        totalLength: 1000,
        completedLength: 500,
        verifiedLength: 400,
        downloadSpeed: 10,
      );
      final json = entry.toJson();
      expect(json['completedLength'], 400);
      expect(json['verifiedLength'], 400);
    });

    test('fromJson restores progress from verifiedLength', () {
      final restored = MagnetDownloadEntry.fromJson({
        'gid': '1',
        'title': 'Test Episode',
        'sourceUri': 'magnet:?xt=urn:btih:abc',
        'addedAt': '2026-01-01T00:00:00.000',
        'savePath': r'C:\Downloads',
        'status': 'active',
        'totalLength': 1000,
        'completedLength': 500,
        'verifiedLength': 400,
      });
      expect(restored.completedLength, 400);
      expect(restored.verifiedLength, 400);
      expect(restored.progress, closeTo(0.4, 1e-9));
    });

    test('fromJson falls back to legacy completedLength', () {
      final restored = MagnetDownloadEntry.fromJson({
        'gid': '1',
        'title': 'Legacy',
        'sourceUri': 'magnet:?xt=urn:btih:abc',
        'addedAt': '2026-01-01T00:00:00.000',
        'status': 'active',
        'totalLength': 1000,
        'completedLength': 250,
      });
      expect(restored.completedLength, 250);
      expect(restored.progress, closeTo(0.25, 1e-9));
    });

    test('restart round-trip keeps progress and total size', () {
      final entry = MagnetDownloadEntry(
        sessionGid: '3',
        title: 'Episode 5',
        sourceUri: 'magnet:?xt=urn:btih:def',
        addedAt: DateTime(2026, 2, 2, 12),
        savePath: r'D:\Anime',
        status: 'active',
        totalLength: 8 * 1024 * 1024 * 1024,
        completedLength: 4 * 1024 * 1024 * 1024,
        verifiedLength: 4 * 1024 * 1024 * 1024,
      );
      final restored = MagnetDownloadEntry.fromJson(
        Map<String, dynamic>.from(entry.toJson()),
      );
      expect(restored.taskId, entry.taskId);
      expect(restored.sessionGid, isNull);
      expect(restored.totalLength, entry.totalLength);
      expect(restored.completedLength, entry.verifiedLength);
      expect(restored.progress, closeTo(0.5, 1e-9));
    });

    test('legacy gid is never restored as a current engine handle', () {
      final restored = MagnetDownloadEntry.fromJson({
        'gid': '3',
        'title': 'Legacy',
        'sourceUri': 'magnet:?xt=urn:btih:legacy',
        'addedAt': '2026-01-01T00:00:00.000',
      });
      expect(restored.taskId, isNot('3'));
      expect(restored.sessionGid, isNull);
      expect(restored.toJson().containsKey('gid'), isFalse);
    });

    test('file manifest round-trips without persisting session gid', () {
      final entry = MagnetDownloadEntry(
        taskId: 'task-stable',
        sessionGid: '9',
        title: 'Season',
        sourceUri: 'magnet:?xt=urn:btih:season',
        addedAt: DateTime(2026, 2, 2),
        importedPath: r'D:\Library\Season',
        files: const [
          MagnetDownloadFile(
            index: 0,
            name: '01.mkv',
            path: 'Season/01.mkv',
            size: 42,
            isStreamable: true,
          ),
        ],
      );
      final restored = MagnetDownloadEntry.fromJson(entry.toJson());
      expect(restored.taskId, 'task-stable');
      expect(restored.sessionGid, isNull);
      expect(restored.files, hasLength(1));
      expect(restored.files.single.path, 'Season/01.mkv');
      expect(restored.files.single.size, 42);
      expect(restored.importedPath, r'D:\Library\Season');
    });

    test('file manifest path cannot escape the download directory', () {
      final entry = MagnetDownloadEntry(
        taskId: 'task-safe-path',
        title: 'Season',
        sourceUri: 'magnet:?xt=urn:btih:safe',
        savePath: Directory.systemTemp.path,
        addedAt: DateTime(2026, 2, 2),
      );
      const escaped = MagnetDownloadFile(
        index: 0,
        name: 'outside.mkv',
        path: '../outside.mkv',
        size: 1,
        isStreamable: true,
      );
      expect(entry.absolutePathFor(escaped), isNull);
    });

    test('scrapeInfo round-trips and marks task as scraped', () {
      final entry = MagnetDownloadEntry(
        sessionGid: '4',
        title: '[Fansub] Anime S2 [01-12]',
        sourceUri: 'magnet:?xt=urn:btih:def',
        addedAt: DateTime(2026, 2, 2, 12),
        scrapeInfo: const MediaScrapeInfo(
          id: 123,
          name: 'Anime',
          nameCn: '动画',
          summary: 'desc',
          airDate: '2026-01-01',
          coverUrl: 'https://example.com/cover.jpg',
        ),
      );
      expect(entry.isScraped, isTrue);
      final restored = MagnetDownloadEntry.fromJson(
        Map<String, dynamic>.from(entry.toJson()),
      );
      expect(restored.isScraped, isTrue);
      expect(restored.scrapeInfo!.id, 123);
      expect(restored.scrapeInfo!.displayName, '动画');
      expect(restored.scrapeInfo!.coverUrl, 'https://example.com/cover.jpg');
    });

    test('scrapeInfo stays null for unscraped legacy entries', () {
      final restored = MagnetDownloadEntry.fromJson({
        'gid': '5',
        'title': 'Legacy',
        'sourceUri': 'magnet:?xt=urn:btih:abc',
        'addedAt': '2026-01-01T00:00:00.000',
        'status': 'active',
      });
      expect(restored.isScraped, isFalse);
      expect(restored.scrapeInfo, isNull);
    });

    test('scrape confidence and attempted flags round-trip', () {
      final entry = MagnetDownloadEntry(
        taskId: 'task-scrape-state',
        title: '[Fansub] Anime',
        sourceUri: 'magnet:?xt=urn:btih:state',
        addedAt: DateTime(2026, 2, 2),
        scrapeAttempted: true,
        scrapeConfidence: 0.72,
      );
      final restored = MagnetDownloadEntry.fromJson(entry.toJson());
      expect(restored.scrapeAttempted, isTrue);
      expect(restored.scrapeConfidence, closeTo(0.72, 1e-9));
      expect(restored.scrapeInfo, isNull);
      expect(restored.scrapePending, isTrue);
    });

    test('legacy entries default to unscraped and not attempted', () {
      final restored = MagnetDownloadEntry.fromJson({
        'title': 'Legacy',
        'sourceUri': 'magnet:?xt=urn:btih:abc',
        'addedAt': '2026-01-01T00:00:00.000',
      });
      expect(restored.scrapeAttempted, isFalse);
      expect(restored.scrapeConfidence, 0);
      expect(restored.scrapePending, isFalse);
    });

    test('scraped entry is not pending even when attempted', () {
      final entry = MagnetDownloadEntry(
        taskId: 'task-scraped',
        title: 'Anime',
        sourceUri: 'magnet:?xt=urn:btih:done',
        addedAt: DateTime(2026, 2, 2),
        scrapeAttempted: true,
        scrapeConfidence: 0.9,
        scrapeInfo: const MediaScrapeInfo(
          id: 1,
          name: 'Anime',
          nameCn: '动画',
          summary: '',
          airDate: '2026-01-01',
          coverUrl: '',
        ),
      );
      final restored = MagnetDownloadEntry.fromJson(entry.toJson());
      expect(restored.isScraped, isTrue);
      expect(restored.scrapePending, isFalse);
      expect(restored.scrapeConfidence, closeTo(0.9, 1e-9));
    });
  });

  group('MagnetDownloadService computeQueueChanges', () {
    MagnetDownloadEntry mk(String id, String status, DateTime addedAt) {
      return MagnetDownloadEntry(
        taskId: id,
        title: id,
        sourceUri: 'magnet:?xt=urn:btih:$id',
        addedAt: addedAt,
        status: status,
      );
    }

    test('no limit leaves queue untouched', () {
      final entries = [
        mk('a', 'active', DateTime(2026, 1, 1)),
        mk('b', 'queued', DateTime(2026, 1, 2)),
      ];
      final changes = MagnetDownloadService.computeQueueChanges(entries, 0);
      expect(changes.promote, isEmpty);
      expect(changes.demote, isEmpty);
    });

    test('promotes queued tasks in added order while slots remain', () {
      final entries = [
        mk('a', 'active', DateTime(2026, 1, 1)),
        mk('b', 'queued', DateTime(2026, 1, 2)),
        mk('c', 'queued', DateTime(2026, 1, 3)),
      ];
      final changes = MagnetDownloadService.computeQueueChanges(entries, 2);
      expect(changes.promote, ['b']);
      expect(changes.demote, isEmpty);
    });

    test('demotes newest active tasks when over the limit', () {
      final entries = [
        mk('a', 'active', DateTime(2026, 1, 1)),
        mk('b', 'active', DateTime(2026, 1, 2)),
        mk('c', 'active', DateTime(2026, 1, 3)),
      ];
      final changes = MagnetDownloadService.computeQueueChanges(entries, 2);
      expect(changes.promote, isEmpty);
      expect(changes.demote, ['c']);
    });

    test('paused, seeding, complete and queued tasks do not count as active',
        () {
      final entries = [
        mk('a', 'active', DateTime(2026, 1, 1)),
        mk('b', 'active', DateTime(2026, 1, 2)),
        mk('p', 'paused', DateTime(2026, 1, 3)),
        mk('s', 'seeding', DateTime(2026, 1, 4)),
        mk('c', 'complete', DateTime(2026, 1, 5)),
        mk('q', 'queued', DateTime(2026, 1, 6)),
      ];
      final changes = MagnetDownloadService.computeQueueChanges(entries, 3);
      expect(changes.promote, ['q']);
      expect(changes.demote, isEmpty);
    });

    test('queued status round-trips through persistence', () {
      final entry = MagnetDownloadEntry(
        taskId: 'task-queued',
        title: 'Queued',
        sourceUri: 'magnet:?xt=urn:btih:queue',
        addedAt: DateTime(2026, 2, 2),
        status: 'queued',
      );
      final restored = MagnetDownloadEntry.fromJson(entry.toJson());
      expect(restored.status, 'queued');
      expect(restored.isQueued, isTrue);
      expect(restored.isDownloading, isFalse);
    });
  });

  group('MagnetDownloadService scheduled limit window', () {
    test('parses HH:mm strings', () {
      expect(MagnetDownloadService.parseHmForTest('23:00'), 23 * 60);
      expect(MagnetDownloadService.parseHmForTest('08:30'), 8 * 60 + 30);
      expect(MagnetDownloadService.parseHmForTest('bad'), isNull);
      expect(MagnetDownloadService.parseHmForTest('25:00'), isNull);
    });

    test('same-day window', () {
      expect(MagnetDownloadService.inWindowForTest(8 * 60, 8 * 60, 18 * 60),
          isTrue);
      expect(MagnetDownloadService.inWindowForTest(18 * 60, 8 * 60, 18 * 60),
          isFalse);
      expect(MagnetDownloadService.inWindowForTest(7 * 60, 8 * 60, 18 * 60),
          isFalse);
    });

    test('overnight window', () {
      expect(
          MagnetDownloadService.inWindowForTest(
              23 * 60 + 30, 23 * 60, 8 * 60),
          isTrue);
      expect(MagnetDownloadService.inWindowForTest(3 * 60, 23 * 60, 8 * 60),
          isTrue);
      expect(MagnetDownloadService.inWindowForTest(12 * 60, 23 * 60, 8 * 60),
          isFalse);
    });
  });

  group('MagnetDownloadService dedup key', () {
    test('normalizes btih case and ignores tracker / dn differences', () {
      expect(
        MagnetDownloadService.dedupKeyForTest('magnet:?xt=urn:btih:ABC123DEF456'),
        'btih:abc123def456',
      );
      expect(
        MagnetDownloadService.dedupKeyForTest(
            'magnet:?xt=urn:btih:ABC123DEF456&dn=Name&tr=udp://tracker.a/announce'),
        'btih:abc123def456',
      );
      expect(
        MagnetDownloadService.dedupKeyForTest('magnet:?xt=urn:btih:XYZ789'),
        'btih:xyz789',
      );
    });

    test('trims whitespace and falls back to raw uri for non-magnet', () {
      expect(
        MagnetDownloadService.dedupKeyForTest('   magnet:?xt=urn:btih:aaa   '),
        'btih:aaa',
      );
      expect(
        MagnetDownloadService.dedupKeyForTest('http://example.com/a.torrent'),
        'uri:http://example.com/a.torrent',
      );
      expect(MagnetDownloadService.dedupKeyForTest(''), isNull);
    });
  });

  group('MagnetDownloadService decideCompletionStatus', () {
    test('non-complete status passes through unchanged', () {
      final r = MagnetDownloadService.decideCompletionStatus(
        status: 'active',
        completionTrusted: false,
        pendingVerification: false,
      );
      expect(r.status, 'active');
      expect(r.completionTrusted, isFalse);
      expect(r.pendingVerification, isFalse);
    });

    test('suspicious instant complete downgrades to checking and requests '
        'recheck', () {
      final r = MagnetDownloadService.decideCompletionStatus(
        status: 'seeding',
        completionTrusted: false,
        pendingVerification: false,
      );
      expect(r.status, 'checking');
      expect(r.completionTrusted, isFalse);
      expect(r.pendingVerification, isTrue);
    });

    test('pending recheck that reports complete again is trusted', () {
      final r = MagnetDownloadService.decideCompletionStatus(
        status: 'complete',
        completionTrusted: false,
        pendingVerification: true,
      );
      expect(r.status, 'complete');
      expect(r.completionTrusted, isTrue);
      expect(r.pendingVerification, isFalse);
    });

    test('already trusted completion stays as-is', () {
      final r = MagnetDownloadService.decideCompletionStatus(
        status: 'seeding',
        completionTrusted: true,
        pendingVerification: false,
      );
      expect(r.status, 'seeding');
      expect(r.completionTrusted, isTrue);
      expect(r.pendingVerification, isFalse);
    });
  });

  group('MagnetDownloadService completionCoversExpected', () {
    // 真实尺度字节数（MB 级）：覆盖校验的容差为 1MB，过小的数值会让
    // 「expected - slack」变负而失去判定意义。
    const mb = 1024 * 1024;
    const sizeA = 900 * mb;
    const sizeB = 100 * mb;
    const sizeAll = sizeA + sizeB;

    MagnetDownloadEntry entryWithFiles({List<int>? selected}) {
      return MagnetDownloadEntry(
        sessionGid: '1',
        title: 'T',
        sourceUri: 'magnet:?xt=urn:btih:abc',
        addedAt: DateTime(2026, 1, 1),
        totalLength: sizeAll,
        files: const [
          MagnetDownloadFile(
            index: 0,
            name: 'f0',
            path: 'f0',
            size: sizeA,
            isStreamable: true,
          ),
          MagnetDownloadFile(
            index: 1,
            name: 'f1',
            path: 'f1',
            size: sizeB,
            isStreamable: true,
          ),
        ],
        selectedFileIndexes: selected,
      );
    }

    test('stream-window finish (narrowed wanted) is not real completion', () {
      // 边下边播：流窗口（约 32MB）下完，引擎按 wanted 子集上报 finished。
      final e = entryWithFiles();
      final t = _info(
        id: 1,
        state: TorrentState.finished,
        isFinished: true,
        progress: 1.0,
        totalWanted: 32 * mb,
        totalDone: 32 * mb,
      );
      expect(MagnetDownloadService.completionCoversExpected(e, t), isFalse);
    });

    test('full-size finish covers expected bytes', () {
      final e = entryWithFiles();
      final t = _info(
        id: 1,
        state: TorrentState.seeding,
        isFinished: true,
        progress: 1.0,
        totalWanted: sizeAll,
        totalDone: sizeAll,
      );
      expect(MagnetDownloadService.completionCoversExpected(e, t), isTrue);
    });

    test('finish with zero verified bytes never covers expected', () {
      // 引擎谎报完成（磁盘无数据）时 wanted 可能为满但 totalDone 为 0。
      final e = entryWithFiles();
      final t = _info(
        id: 1,
        state: TorrentState.seeding,
        isFinished: true,
        progress: 1.0,
        totalWanted: sizeAll,
        totalDone: 0,
      );
      expect(MagnetDownloadService.completionCoversExpected(e, t), isFalse);
    });

    test('file selection: finish of selected subset is covered', () {
      final e = entryWithFiles(selected: [1]);
      final t = _info(
        id: 1,
        state: TorrentState.finished,
        isFinished: true,
        progress: 1.0,
        totalWanted: sizeB,
        totalDone: sizeB,
      );
      expect(MagnetDownloadService.completionCoversExpected(e, t), isTrue);
    });

    test('file selection: stream window below selected set is not covered',
        () {
      final e = entryWithFiles(selected: [1]);
      final t = _info(
        id: 1,
        state: TorrentState.finished,
        isFinished: true,
        progress: 1.0,
        totalWanted: 20 * mb,
        totalDone: 20 * mb,
      );
      expect(MagnetDownloadService.completionCoversExpected(e, t), isFalse);
    });

    test('unknown manifest falls back to totalLength', () {
      final e = _entry(totalLength: 500 * mb);
      // 无文件清单：按 totalLength 判定，流窗口完成被拒绝。
      expect(
        MagnetDownloadService.completionCoversExpected(
          e,
          _info(
            id: 1,
            totalWanted: 32 * mb,
            totalDone: 32 * mb,
            isFinished: true,
            progress: 1.0,
          ),
        ),
        isFalse,
      );
      expect(
        MagnetDownloadService.completionCoversExpected(
          e,
          _info(
            id: 1,
            totalWanted: 500 * mb,
            totalDone: 500 * mb,
            isFinished: true,
            progress: 1.0,
          ),
        ),
        isTrue,
      );
    });

    test('unknown expected size keeps legacy behavior (true)', () {
      final e = _entry(totalLength: 0);
      expect(
        MagnetDownloadService.completionCoversExpected(
          e,
          _info(id: 1, totalWanted: 0, totalDone: 0),
        ),
        isTrue,
      );
    });

    test('expectedDownloadBytes respects file selection', () {
      final all = entryWithFiles();
      expect(MagnetDownloadService.expectedDownloadBytes(all), sizeAll);
      final selected = entryWithFiles(selected: [1]);
      expect(MagnetDownloadService.expectedDownloadBytes(selected), sizeB);
    });
  });

  group('MagnetDownloadService state mapping - pre-metadata guard', () {
    test('metadata-less finished/seeding report is never complete', () {
      expect(
        MagnetDownloadService.mapStatusForTest(_info(
          id: 1,
          state: TorrentState.finished,
          isFinished: true,
          progress: 1.0,
          hasMetadata: false,
        )),
        'waiting',
      );
      expect(
        MagnetDownloadService.mapStatusForTest(_info(
          id: 1,
          state: TorrentState.seeding,
          isFinished: true,
          progress: 1.0,
          hasMetadata: false,
        )),
        'waiting',
      );
    });

    test('metadata-less error surfaces as error', () {
      expect(
        MagnetDownloadService.mapStatusForTest(_info(
          id: 1,
          state: TorrentState.error,
          hasMetadata: false,
        )),
        'error',
      );
    });
  });
}
