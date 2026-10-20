import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/lan/lan_collect_store.dart';
import 'package:kazumi/services/lan/lan_history_store.dart';
import 'package:kazumi/services/lan/lan_sync_models.dart';
import 'package:kazumi/services/lan/lan_sync_server.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  late Directory tempDir;
  late File videoFile;
  late LanSyncServer server;
  late HttpClient client;
  late BangumiItem collectBangumi;

  const token = 'test-token';
  const pairingCode = '123456';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // 测试绑定默认用 HttpOverrides 拦截所有网络请求（返回 400），
    // 本地局域网集成测试需要真实 loopback 连接。
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('kazumi_lan_server_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    Hive.init('${tempDir.path}/hive');
    await GStorage.init();

    final mediaDir = Directory('${tempDir.path}/media');
    await mediaDir.create(recursive: true);
    videoFile = File('${mediaDir.path}/01.mp4');
    await videoFile.writeAsBytes(List<int>.generate(1024, (i) => i % 256));

    collectBangumi = BangumiItem(
      id: 9001,
      type: 2,
      name: 'Collect Test',
      nameCn: '收藏测试',
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
    await GStorage.putCollectible(
      CollectedBangumi(
        collectBangumi,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
        5,
      ),
    );

    final controller = MediaController()
      ..folders = ObservableList.of([mediaDir.path])
      ..library = ObservableList.of([
        LocalMediaFolder(
          path: mediaDir.path,
          name: 'media',
          files: [
            LocalMediaFile(
              path: videoFile.path,
              name: '01.mp4',
              size: 1024,
              modifiedAt: DateTime(2026, 1, 1),
            ),
          ],
        ),
      ]);

    server = LanSyncServer(
      serverId: 'test-server',
      serverName: 'Test Desktop',
      token: token,
      pairingCode: pairingCode,
      port: 0,
      mediaController: controller,
      historyStore: LanHistoryStore(HistoryRepository()),
      collectStore: LanCollectStore(),
    );
    await server.start();
    client = HttpClient()..findProxy = (_) => 'DIRECT';
  });

  tearDownAll(() async {
    client.close(force: true);
    await server.stop();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<HttpClientResponse> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? authToken,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}$path');
    final req = await client.openUrl(method, uri);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (authToken != null) {
      req.headers.set('x-kazumi-token', authToken);
    }
    headers?.forEach(req.headers.set);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    return req.close();
  }

  test('info endpoint is public and reports the actual port', () async {
    final response = await request('GET', '/api/v1/info');
    expect(response.statusCode, 200);
    final json = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    expect(json['serverId'], 'test-server');
    expect(json['httpPort'], server.actualPort);
  });

  test(
    'pairing rejects a wrong code and accepts the configured code',
    () async {
      final wrong = await request(
        'POST',
        '/api/v1/pair',
        body: {'code': '000000', 'deviceName': 'test'},
      );
      expect(wrong.statusCode, 403);
      await wrong.drain();

      final ok = await request(
        'POST',
        '/api/v1/pair',
        body: {'code': pairingCode, 'deviceName': 'test'},
      );
      expect(ok.statusCode, 200);
      final json = jsonDecode(await utf8.decoder.bind(ok).join()) as Map;
      expect(json['token'], token);
    },
  );

  test('sync requires auth and merges library / collect payload', () async {
    final unauthorized = await request(
      'POST',
      '/api/v1/sync',
      body: {'protocol': kLanSyncProtocolVersion, 'history': const []},
    );
    expect(unauthorized.statusCode, 401);
    await unauthorized.drain();

    final clientCollect = LanCollectibleEntry(
      bangumiItem: collectBangumi,
      type: 4, // 看过，比桌面端的抛弃更新
      timeMs: 1800000000000,
    );
    final response = await request(
      'POST',
      '/api/v1/sync',
      authToken: token,
      body: {
        'protocol': kLanSyncProtocolVersion,
        'history': const [],
        'collectibles': [clientCollect.toJson()],
        'collectTombstones': const [],
      },
    );
    expect(response.statusCode, 200);
    final payload = LanSyncPayload.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(response).join()) as Map,
      ),
    );
    expect(payload.server.serverId, 'test-server');
    expect(payload.folders, hasLength(1));
    expect(payload.folders.single.files.single.path, videoFile.path);
    expect(payload.collectibles.single.type, 4);
    expect(GStorage.collectibles.get(9001)?.type, 4);
  });

  test('collect tombstone removes the collection on the server', () async {
    final response = await request(
      'POST',
      '/api/v1/sync',
      authToken: token,
      body: {
        'protocol': kLanSyncProtocolVersion,
        'history': const [],
        'collectibles': const [],
        'collectTombstones': [
          const LanCollectTombstone(
            bangumiId: 9001,
            updatedAtMs: 1900000000000,
          ).toJson(),
        ],
      },
    );
    expect(response.statusCode, 200);
    final payload = LanSyncPayload.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(response).join()) as Map,
      ),
    );
    expect(payload.collectibles, isEmpty);
    expect(payload.collectTombstones.single.bangumiId, 9001);
    expect(GStorage.collectibles.get(9001), isNull);
  });

  test(
    'stream serves byte ranges and rejects files outside the library',
    () async {
      final encoded = base64Url
          .encode(utf8.encode(videoFile.path))
          .replaceAll('=', '');
      final uriPath = '/api/v1/stream?path=$encoded&token=$token';
      final response = await request(
        'GET',
        uriPath,
        headers: {HttpHeaders.rangeHeader: 'bytes=2-5'},
      );
      expect(response.statusCode, 206);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 2-5/1024',
      );
      final bytes = await response.fold<List<int>>(
        <int>[],
        (a, b) => a..addAll(b),
      );
      expect(bytes, [2, 3, 4, 5]);

      final outside = File('${tempDir.path}/outside.mp4');
      await outside.writeAsBytes([1, 2, 3]);
      final outsideEncoded = base64Url
          .encode(utf8.encode(outside.path))
          .replaceAll('=', '');
      final rejected = await request(
        'GET',
        '/api/v1/stream?path=$outsideEncoded&token=$token',
      );
      expect(rejected.statusCode, 404);
      await rejected.drain();
    },
  );
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);

  final Directory _root;

  @override
  Future<String?> getApplicationSupportPath() async =>
      '${_root.path}/app_support';
  @override
  Future<String?> getTemporaryPath() async => '${_root.path}/temp';
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      '${_root.path}/documents';
  @override
  Future<String?> getApplicationCachePath() async => '${_root.path}/cache';
  @override
  Future<String?> getDownloadsPath() async => '${_root.path}/downloads';
}
