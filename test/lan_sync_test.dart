import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/lan/lan_media_paths.dart';
import 'package:kazumi/services/lan/lan_sync_models.dart';
import 'package:kazumi/services/lan/lan_sync_server.dart';
import 'package:kazumi/services/lan/lan_sync_service.dart';
import 'package:kazumi/services/media/local_media_models.dart';

void main() {
  group('LAN media paths', () {
    test('folder and file paths round-trip', () {
      final folder = lanFolderPath('abc123', r'E:\Anime\葬送的芙莉莲');
      final file = lanFilePath('abc123', r'E:\Anime\葬送的芙莉莲\01.mkv');

      expect(isLanMediaPath(folder), isTrue);
      expect(parseLanMediaPath(folder)?.isFolder, isTrue);
      expect(parseLanMediaPath(folder)?.remotePath, r'E:\Anime\葬送的芙莉莲');
      expect(parseLanMediaPath(file)?.isFolder, isFalse);
      expect(parseLanMediaPath(file)?.remotePath, r'E:\Anime\葬送的芙莉莲\01.mkv');
      expect(lanServerIdOf(file), 'abc123');
      expect(isLanPathOfServer(file, 'abc123'), isTrue);
      expect(isLanPathOfServer(file, 'other'), isFalse);
    });

    test('path identity keeps LAN pseudo paths untouched', () {
      final path = lanFilePath('abc123', r'E:\Anime\01.mkv');
      expect(localMediaPathKey(path), path);
      expect(isLocalMediaPathWithin(path, path), isTrue);
      expect(
        isLocalMediaPathWithin(path, lanFilePath('abc123', r'E:\Anime\02.mkv')),
        isFalse,
      );
    });

    test('stream url carries encoded path and token', () {
      final url = buildLanStreamUrl(
        host: '192.168.1.2',
        port: 45870,
        token: 'secret',
        remotePath: r'E:\Anime\01.mkv',
      );
      final uri = Uri.parse(url);
      expect(uri.path, '/api/v1/stream');
      expect(uri.queryParameters['token'], 'secret');
      final encoded = uri.queryParameters['path']!;
      final padded = encoded.padRight((encoded.length + 3) & ~3, '=');
      expect(utf8.decode(base64Url.decode(padded)), r'E:\Anime\01.mkv');
    });
  });

  group('byte range', () {
    test('parses common forms', () {
      expect(parseByteRange(null, 1000), isNull);
      expect(parseByteRange('bytes=0-99', 1000)?.start, 0);
      expect(parseByteRange('bytes=0-99', 1000)?.end, 99);
      expect(parseByteRange('bytes=100-', 1000)?.end, 999);
      expect(parseByteRange('bytes=-100', 1000)?.start, 900);
      expect(parseByteRange('bytes=-100', 1000)?.end, 999);
      expect(parseByteRange('bytes=900-2000', 1000)?.end, 999);
    });

    test('rejects unsatisfiable ranges', () {
      expect(parseByteRange('bytes=1000-', 1000), isNull);
      expect(parseByteRange('bytes=abc-def', 1000), isNull);
      expect(parseByteRange('bytes=-0', 1000), isNull);
      expect(parseByteRange('items=0-10', 1000), isNull);
    });
  });

  group('history merge', () {
    final bangumi = BangumiItem(
      id: 42,
      type: 2,
      name: 'Test',
      nameCn: '测试番剧',
      summary: '',
      airDate: '2024-01-01',
      airWeekday: 1,
      rank: 0,
      images: const {},
      tags: const [],
      alias: const [],
      ratingScore: 0,
      votes: 0,
      votesCount: const [],
      info: '',
    );

    LanHistoryEntry entry({
      required DateTime watchTime,
      required int episode,
      required int progressMs,
      required int updatedAtMs,
    }) => LanHistoryEntry(
      bangumiItem: bangumi,
      lastWatchEpisode: episode,
      lastWatchTime: watchTime,
      lastSrc: '',
      lastWatchEpisodeName: 'EP$episode',
      adapterName: kLocalMediaAdapterName,
      entryKind: HistoryEntryKind.offline,
      episodePageUrl: r'E:\Anime\01.mkv',
      progresses: [
        LanProgressData(
          episode: episode,
          road: 0,
          progressMs: progressMs,
          updatedAtMs: updatedAtMs,
        ),
      ],
    );

    test('keeps latest watch state and newer per-episode progress', () {
      final older = entry(
        watchTime: DateTime(2026, 1, 1),
        episode: 1,
        progressMs: 1000,
        updatedAtMs: 1000,
      );
      final newer = entry(
        watchTime: DateTime(2026, 1, 2),
        episode: 2,
        progressMs: 500,
        updatedAtMs: 2000,
      );

      final merged = mergeLanHistory([older, newer], const []);
      expect(merged, hasLength(1));
      expect(merged.single.lastWatchEpisode, 2);
      expect(merged.single.lastWatchTime, DateTime(2026, 1, 2));
      final progress = merged.single.progresses.firstWhere(
        (item) => item.episode == 1,
      );
      expect(progress.progressMs, 1000);
      expect(
        merged.single.progresses
            .firstWhere((item) => item.episode == 2)
            .progressMs,
        500,
      );
    });

    test('merge keeps the non-empty episode path', () {
      final withoutPath = LanHistoryEntry(
        bangumiItem: bangumi,
        lastWatchEpisode: 2,
        lastWatchTime: DateTime(2026, 1, 2),
        lastSrc: '',
        lastWatchEpisodeName: 'EP2',
        adapterName: kLocalMediaAdapterName,
        entryKind: HistoryEntryKind.offline,
        episodePageUrl: '',
        progresses: const [],
      );
      final local = entry(
        watchTime: DateTime(2026, 1, 1),
        episode: 2,
        progressMs: 500,
        updatedAtMs: 1000,
      );

      // 时间更新的条目没有路径时，不能用空路径覆盖已有路径。
      final merged = withoutPath.merge(local);
      expect(merged.episodePageUrl, local.episodePageUrl);
      expect(merged.lastWatchTime, DateTime(2026, 1, 2));
    });

    test('merge aligns last watched episode with per-episode progress', () {
      final broken = LanHistoryEntry(
        bangumiItem: bangumi,
        lastWatchEpisode: 38,
        lastWatchTime: DateTime(2026, 10, 4),
        lastSrc: '',
        lastWatchEpisodeName: 'EP38',
        adapterName: kLocalMediaAdapterName,
        entryKind: HistoryEntryKind.offline,
        episodePageUrl: r'E:\Anime\38.mkv',
        progresses: const [],
      );
      final remote = entry(
        watchTime: DateTime(2026, 9, 2),
        episode: 37,
        progressMs: 900,
        updatedAtMs: 2000,
      );

      // 最后观看集没有对应进度时按最新进度回填，历史页才会显示「看到」。
      final merged = broken.merge(remote);
      expect(merged.lastWatchEpisode, 37);
      expect(merged.progresses, hasLength(1));
    });

    test('serializes and restores history entry', () {
      final original = entry(
        watchTime: DateTime(2026, 1, 2, 3, 4, 5),
        episode: 3,
        progressMs: 1234,
        updatedAtMs: 5678,
      );
      final restored = LanHistoryEntry.fromJson(original.toJson());
      expect(restored.key, original.key);
      expect(restored.bangumiItem.nameCn, '测试番剧');
      expect(restored.lastWatchTime, original.lastWatchTime);
      expect(restored.progresses.single.progressMs, 1234);
      expect(restored.toHistory().key, original.key);
    });

    test('legacy progress without timestamp loses to fresh remote progress', () {
      final legacy = History(
        bangumi,
        1,
        kLocalMediaAdapterName,
        DateTime(2026, 10, 1),
        '',
        'EP1',
        entryKind: HistoryEntryKind.offline,
        episodePageUrl: r'E:\Anime\01.mkv',
      )..progresses[1] = Progress(1, 0, 300000);

      // 旧条目的分集进度没有 updatedAtMs：不能拿条目时间冒充分集时间。
      final exported = LanHistoryEntry.fromHistory(legacy);
      expect(exported.progresses.single.updatedAtMs, 0);

      final remote = exported.copyWith(
        progresses: [
          const LanProgressData(
            episode: 1,
            road: 0,
            progressMs: 1200000,
            updatedAtMs: 1790000000000,
          ),
        ],
      );
      final merged = mergeLanHistory([exported], [remote]);
      expect(merged.single.progresses.single.progressMs, 1200000);
    });

    test('syncs online history but skips device-bound entries', () {
      LanHistoryEntry withAdapter(String adapter, String kind) =>
          LanHistoryEntry(
            bangumiItem: bangumi,
            lastWatchEpisode: 1,
            lastWatchTime: DateTime(2026, 1, 1),
            lastSrc: 'https://example.com/bangumi/42',
            lastWatchEpisodeName: 'EP1',
            adapterName: adapter,
            entryKind: kind,
            episodePageUrl: 'https://example.com/ep/1',
            progresses: const [],
          );

      // 在线观看：插件源地址与设备无关，两端都能继续看。
      final online = withAdapter('AGE', HistoryEntryKind.online);
      expect(
        isLanSyncableHistory(adapterName: 'AGE', entryKind: 'online'),
        isTrue,
      );
      expect(mergeLanHistory([online], const []), hasLength(1));

      // 磁力边下边播：流地址随引擎生命周期存活，换设备无意义。
      expect(
        isLanSyncableHistory(
          adapterName: kMagnetStreamAdapterName,
          entryKind: HistoryEntryKind.offline,
        ),
        isFalse,
      );
      expect(
        mergeLanHistory(
          [withAdapter(kMagnetStreamAdapterName, HistoryEntryKind.offline)],
          const [],
        ),
        isEmpty,
      );

      // 插件下载缓存：绑定单端文件路径。
      expect(
        isLanSyncableHistory(adapterName: 'AGE', entryKind: 'offline'),
        isFalse,
      );
      expect(
        mergeLanHistory(
          [withAdapter('AGE', HistoryEntryKind.offline)],
          const [],
        ),
        isEmpty,
      );
    });
  });

  group('collect merge', () {
    final item = BangumiItem(
      id: 7,
      type: 2,
      name: 'Collect',
      nameCn: '收藏',
      summary: '',
      airDate: '2026-01-01',
      airWeekday: 1,
      rank: 0,
      images: const {},
      tags: const [],
      alias: const [],
      ratingScore: 0,
      votes: 0,
      votesCount: const [],
      info: '',
    );

    LanCollectibleEntry live(int type, int timeMs) =>
        LanCollectibleEntry(bangumiItem: item, type: type, timeMs: timeMs);

    test('newer status wins over older status', () {
      final result = mergeLanCollectibles(
        localCollectibles: [live(5, 1000)],
        localTombstones: const [],
        remoteCollectibles: [live(4, 2000)],
        remoteTombstones: const [],
      );
      expect(result.tombstones, isEmpty);
      expect(result.collectibles.single.type, 4);
      expect(result.collectibles.single.timeMs, 2000);
    });

    test('same time uses deterministic status priority', () {
      final result = mergeLanCollectibles(
        localCollectibles: [live(5, 1000)],
        localTombstones: const [],
        remoteCollectibles: [live(4, 1000)],
        remoteTombstones: const [],
      );
      expect(result.collectibles.single.type, 4);
    });

    test('newer tombstone deletes; newer re-add wins back', () {
      final deleted = mergeLanCollectibles(
        localCollectibles: [live(4, 1000)],
        localTombstones: const [],
        remoteCollectibles: const [],
        remoteTombstones: const [
          LanCollectTombstone(bangumiId: 7, updatedAtMs: 2000),
        ],
      );
      expect(deleted.collectibles, isEmpty);
      expect(deleted.tombstones.single.bangumiId, 7);

      final readded = mergeLanCollectibles(
        localCollectibles: const [],
        localTombstones: deleted.tombstones,
        remoteCollectibles: [live(4, 3000)],
        remoteTombstones: const [],
      );
      expect(readded.tombstones, isEmpty);
      expect(readded.collectibles.single.type, 4);
    });

    test('tombstone payload round-trips', () {
      final entry = live(4, 123456);
      final restored = LanCollectibleEntry.fromJson(entry.toJson());
      expect(restored.bangumiId, 7);
      expect(restored.type, 4);
      expect(restored.timeMs, 123456);
      expect(restored.bangumiItem.nameCn, '收藏');

      const tombstone = LanCollectTombstone(bangumiId: 7, updatedAtMs: 999);
      final restoredTombstone = LanCollectTombstone.fromJson(
        tombstone.toJson(),
      );
      expect(restoredTombstone.bangumiId, 7);
      expect(restoredTombstone.updatedAtMs, 999);
    });
  });

  group('manual address parsing', () {
    test('accepts host, host:port and url forms', () {
      expect(LanSyncService.parseManualAddress('192.168.1.2'), (
        '192.168.1.2',
        45870,
      ));
      expect(LanSyncService.parseManualAddress('192.168.1.2:1234'), (
        '192.168.1.2',
        1234,
      ));
      expect(LanSyncService.parseManualAddress('http://10.0.0.5:9999'), (
        '10.0.0.5',
        9999,
      ));
      expect(LanSyncService.parseManualAddress(''), isNull);
      expect(LanSyncService.parseManualAddress('   '), isNull);
    });
  });
}
