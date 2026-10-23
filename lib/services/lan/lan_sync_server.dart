import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:kazumi/services/lan/lan_collect_store.dart';
import 'package:kazumi/services/lan/lan_history_store.dart';
import 'package:kazumi/services/lan/lan_media_paths.dart';
import 'package:kazumi/services/lan/lan_sync_models.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 桌面端局域网服务：媒体库快照、观看进度合并、Range 流媒体与 UDP 发现。
class LanSyncServer {
  LanSyncServer({
    required this.serverId,
    required this.serverName,
    required this.token,
    required this.pairingCode,
    required this.port,
    required this.mediaController,
    required this.historyStore,
    required this.collectStore,
    this.onCollectChanged,
  });

  final String serverId;
  final String serverName;
  final MediaController mediaController;
  final LanHistoryStore historyStore;
  final LanCollectStore collectStore;
  final VoidCallback? onCollectChanged;

  String token;
  String pairingCode;
  int port;

  HttpServer? _httpServer;
  RawDatagramSocket? _udpSocket;
  StreamSubscription<RawSocketEvent>? _udpSubscription;
  final Map<String, List<DateTime>> _pairAttempts = {};

  bool get isRunning => _httpServer != null;

  int get actualPort => _httpServer?.port ?? port;

  LanServerInfo get info => LanServerInfo(
    protocol: kLanSyncProtocolVersion,
    serverId: serverId,
    name: serverName,
    version: lanSyncAppVersion(),
    httpPort: actualPort,
  );

  Future<void> start() async {
    if (_httpServer != null) return;
    var boundPort = port;
    HttpServer server;
    try {
      server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        boundPort,
        shared: false,
      );
    } on SocketException {
      // 固定端口被占用时退回临时端口；UDP 发现会带上真实端口，
      // 手动地址则可在设置页看到新端口。
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      boundPort = server.port;
    }
    port = boundPort;
    server.autoCompress = true;
    _httpServer = server;
    server.listen(
      _handleRequest,
      onError: (Object error, StackTrace stackTrace) {
        KazumiLogger().w(
          'LanSyncServer: HTTP server error',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );

    try {
      final udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kLanSyncDiscoveryPort,
      );
      udp.broadcastEnabled = true;
      _udpSocket = udp;
      _udpSubscription = udp.listen(_handleDatagram);
    } catch (e) {
      // 发现端口被占用时仍可手动填写地址连接。
      KazumiLogger().w('LanSyncServer: UDP discovery unavailable', error: e);
    }
    KazumiLogger().i(
      'LanSyncServer: started on port $actualPort '
      '(discovery ${_udpSocket == null ? "off" : "on"})',
      forceLog: true,
    );
  }

  Future<void> stop() async {
    await _udpSubscription?.cancel();
    _udpSubscription = null;
    _udpSocket?.close();
    _udpSocket = null;
    final server = _httpServer;
    _httpServer = null;
    if (server != null) {
      await server.close(force: true);
    }
    KazumiLogger().i('LanSyncServer: stopped');
  }

  /// 桌面端当前可被访问的 IPv4 地址。
  Future<List<String>> localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      return [
        for (final interface in interfaces)
          for (final address in interface.addresses) address.address,
      ];
    } catch (_) {
      return const [];
    }
  }

  void _handleDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _udpSocket;
    final datagram = socket?.receive();
    if (socket == null || datagram == null) return;
    try {
      final text = utf8.decode(datagram.data).trim();
      final isProbe =
          text == kLanSyncDiscoveryProbe ||
          (text.startsWith('{') && text.contains('discover'));
      if (!isProbe) return;
      final payload = <String, dynamic>{
        'type': 'kazumi-lan-server',
        ...info.toJson(),
      };
      socket.send(
        utf8.encode(jsonEncode(payload)),
        datagram.address,
        datagram.port,
      );
    } catch (_) {
      // 非法广播包直接忽略。
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    try {
      if (request.method == 'GET' && path == '/api/v1/info') {
        await _json(request, HttpStatus.ok, {
          'type': 'kazumi-lan-server',
          ...info.toJson(),
        });
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/pair') {
        await _pair(request);
        return;
      }
      if (path == '/api/v1/stream') {
        await _stream(request);
        return;
      }
      if (!_authorized(request)) {
        await _json(request, HttpStatus.unauthorized, {
          'error': 'unauthorized',
        });
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/ping') {
        await _json(request, HttpStatus.ok, {
          'ok': true,
          'server': info.toJson(),
        });
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/sync') {
        await _sync(request);
        return;
      }
      await _json(request, HttpStatus.notFound, {'error': 'not found'});
    } catch (e, stackTrace) {
      KazumiLogger().w(
        'LanSyncServer: request failed $path',
        error: e,
        stackTrace: stackTrace,
      );
      try {
        await _json(request, HttpStatus.internalServerError, {
          'error': 'internal error',
        });
      } catch (_) {}
    }
  }

  bool _authorized(HttpRequest request) {
    if (token.isEmpty) return false;
    final header = request.headers.value('x-kazumi-token');
    if (header != null && _sameToken(header, token)) return true;
    final queryToken = request.uri.queryParameters['token'];
    return queryToken != null && _sameToken(queryToken, token);
  }

  static bool _sameToken(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> _pair(HttpRequest request) async {
    final remote = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    final now = DateTime.now();
    final attempts = _pairAttempts.putIfAbsent(remote, () => []);
    attempts.removeWhere(
      (time) => now.difference(time) > const Duration(minutes: 1),
    );
    if (attempts.length >= 10) {
      await _json(request, HttpStatus.tooManyRequests, {
        'error': 'too many attempts',
      });
      return;
    }
    attempts.add(now);

    final body = await _readJson(request);
    final code = body?['code']?.toString().trim() ?? '';
    if (pairingCode.isEmpty || code != pairingCode) {
      await _json(request, HttpStatus.forbidden, {'error': 'invalid code'});
      return;
    }
    final deviceName = body?['deviceName']?.toString() ?? 'Kazumi';
    KazumiLogger().i(
      'LanSyncServer: paired with $deviceName ($remote)',
      forceLog: true,
    );
    await _json(request, HttpStatus.ok, {
      'token': token,
      'server': info.toJson(),
    });
  }

  Future<void> _sync(HttpRequest request) async {
    // 桌面端刚启动 / 手机先于媒体库扫描完成连接：等待正在进行的扫描
    // 或补一次扫描，避免第一次配对拿到空媒体库。
    var waited = 0;
    while (mediaController.isScanning &&
        waited < 40 &&
        mediaController.folders.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      waited++;
    }
    if (mediaController.library.isEmpty &&
        mediaController.folders.isNotEmpty &&
        !mediaController.isScanning) {
      await mediaController.scan();
    }
    final body = await _readJson(request);
    if (body == null) {
      await _json(request, HttpStatus.badRequest, {'error': 'invalid body'});
      return;
    }
    final protocol = (body['protocol'] as num?)?.toInt();
    if (protocol != kLanSyncProtocolVersion) {
      await _json(request, HttpStatus.conflict, {
        'error': 'protocol mismatch',
        'protocol': kLanSyncProtocolVersion,
      });
      return;
    }
    final incoming = <LanHistoryEntry>[];
    var droppedHistory = 0;
    final rawHistory = body['history'];
    if (rawHistory is List) {
      for (final raw in rawHistory) {
        if (raw is! Map) continue;
        try {
          final entry = LanHistoryEntry.fromJson(
            Map<String, dynamic>.from(raw),
          );
          // 只接受媒体库根目录内的路径，避免已配对设备写入手工构造的
          // 任意本机路径到历史记录。
          if (entry.episodePageUrl.isNotEmpty &&
              !_isAllowedMediaPath(entry.episodePageUrl)) {
            droppedHistory++;
            continue;
          }
          incoming.add(entry);
        } catch (_) {
          droppedHistory++;
        }
      }
    }
    if (droppedHistory > 0) {
      // 静默丢弃会让「手机推了历史但电脑上没变化」无从排查。
      KazumiLogger().w(
        'LanSyncServer: dropped $droppedHistory history entries '
        '(path outside media roots or invalid)',
      );
    }

    final local = historyStore.exportLocalMediaHistory();
    final merged = mergeLanHistory(local, incoming);
    var appliedHistory = 0;
    if (incoming.isNotEmpty) {
      appliedHistory = await historyStore.applyEntries(merged);
    }
    KazumiLogger().i(
      'LanSyncServer: sync incoming=${incoming.length} '
      'local=${local.length} merged=${merged.length} '
      'applied=$appliedHistory',
      forceLog: true,
    );

    final collectEnabled = GStorage.getSetting(
      SettingsKeys.lanSyncCollectEnable,
    );
    LanCollectMergeResult collectResult = LanCollectMergeResult.empty;
    if (collectEnabled) {
      final incomingCollectibles = <LanCollectibleEntry>[];
      final incomingTombstones = <LanCollectTombstone>[];
      final rawCollectibles = body['collectibles'];
      if (rawCollectibles is List) {
        for (final raw in rawCollectibles) {
          if (raw is! Map) continue;
          try {
            incomingCollectibles.add(
              LanCollectibleEntry.fromJson(Map<String, dynamic>.from(raw)),
            );
          } catch (_) {}
        }
      }
      final rawTombstones = body['collectTombstones'];
      if (rawTombstones is List) {
        for (final raw in rawTombstones) {
          if (raw is! Map) continue;
          try {
            incomingTombstones.add(
              LanCollectTombstone.fromJson(Map<String, dynamic>.from(raw)),
            );
          } catch (_) {}
        }
      }
      collectResult = mergeLanCollectibles(
        localCollectibles: collectStore.exportCollectibles(),
        localTombstones: collectStore.exportTombstones(),
        remoteCollectibles: incomingCollectibles,
        remoteTombstones: incomingTombstones,
      );
      final applied = await collectStore.applyMerged(collectResult);
      if (applied > 0) onCollectChanged?.call();
    }

    final payload = buildPayload(history: merged, collectResult: collectResult);
    await _json(request, HttpStatus.ok, payload.toJson());
  }

  /// 构建当前媒体库快照。历史 / 收藏为可选覆盖（服务端合并后回传同一份）。
  LanSyncPayload buildPayload({
    List<LanHistoryEntry>? history,
    LanCollectMergeResult? collectResult,
  }) {
    final folders = <LanMediaFolderData>[];
    for (final folder in mediaController.library) {
      if (folder.isRemote) continue;
      final data = LanMediaFolderData.fromLocalMediaFolder(folder);
      if (data.files.isEmpty) continue;
      folders.add(data);
    }
    return LanSyncPayload(
      server: info,
      folders: folders,
      scrapeResults: {
        for (final entry in mediaController.scrapeResults.entries)
          if (!isLanMediaPath(entry.key)) entry.key: entry.value,
      },
      fileScrapeResults: {
        for (final entry in mediaController.fileScrapeResults.entries)
          if (!isLanMediaPath(entry.key)) entry.key: entry.value,
      },
      history: history ?? historyStore.exportLocalMediaHistory(),
      collectibles: collectResult?.collectibles ?? const [],
      collectTombstones: collectResult?.tombstones ?? const [],
      generatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _stream(HttpRequest request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      await _json(request, HttpStatus.methodNotAllowed, {
        'error': 'method not allowed',
      });
      return;
    }
    if (!_authorized(request)) {
      await _json(request, HttpStatus.unauthorized, {'error': 'unauthorized'});
      return;
    }
    final encodedPath = request.uri.queryParameters['path'];
    if (encodedPath == null || encodedPath.isEmpty) {
      await _json(request, HttpStatus.badRequest, {'error': 'missing path'});
      return;
    }
    final filePath = _decodeStreamPath(encodedPath);
    if (filePath == null || !_isAllowedMediaPath(filePath)) {
      await _json(request, HttpStatus.notFound, {'error': 'file not found'});
      return;
    }
    final file = File(filePath);
    int length;
    try {
      length = await file.length();
    } catch (_) {
      await _json(request, HttpStatus.notFound, {'error': 'file not found'});
      return;
    }
    if (length <= 0) {
      await _json(request, HttpStatus.notFound, {'error': 'empty file'});
      return;
    }

    final response = request.response;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final range = parseByteRange(rangeHeader, length);
    if (rangeHeader != null && range == null) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
      await response.close();
      return;
    }

    final start = range?.start ?? 0;
    final end = range?.end ?? (length - 1);
    response.statusCode = range == null
        ? HttpStatus.ok
        : HttpStatus.partialContent;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.contentTypeHeader, _contentType(filePath));
    response.headers.set('cache-control', 'no-store');
    response.headers.set(
      'content-disposition',
      'inline; filename*=UTF-8\'\'${Uri.encodeComponent(file.uri.pathSegments.last)}',
    );
    response.contentLength = end - start + 1;
    if (range != null) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$length',
      );
    }
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    try {
      await response.addStream(file.openRead(start, end + 1));
      await response.close();
    } catch (e) {
      // 播放器拖动进度时会主动断开旧连接，属于正常现象。
      KazumiLogger().d('LanSyncServer: stream aborted', error: e);
    }
  }

  String? _decodeStreamPath(String encoded) {
    try {
      final padded = encoded.padRight((encoded.length + 3) & ~3, '=');
      return utf8.decode(base64Url.decode(padded));
    } catch (_) {
      return null;
    }
  }

  bool _isAllowedMediaPath(String filePath) {
    if (!isSupportedVideoFile(filePath)) return false;
    for (final root in mediaController.folders) {
      if (isLocalMediaPathWithin(root, filePath)) return true;
    }
    return false;
  }

  static const Map<String, String> _contentTypes = {
    '.mp4': 'video/mp4',
    '.m4v': 'video/mp4',
    '.mkv': 'video/x-matroska',
    '.avi': 'video/x-msvideo',
    '.mov': 'video/quicktime',
    '.flv': 'video/x-flv',
    '.wmv': 'video/x-ms-wmv',
    '.webm': 'video/webm',
    '.ts': 'video/mp2t',
    '.m2ts': 'video/mp2t',
  };

  static String _contentType(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot).toLowerCase();
    return _contentTypes[ext] ?? 'application/octet-stream';
  }

  Future<Map<String, dynamic>?> _readJson(HttpRequest request) async {
    try {
      final text = await utf8.decoder.bind(request).join();
      if (text.trim().isEmpty) return null;
      final json = jsonDecode(text);
      return json is Map ? Map<String, dynamic>.from(json) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _json(
    HttpRequest request,
    int status,
    Map<String, dynamic> body,
  ) async {
    final response = request.response;
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.set('cache-control', 'no-store');
    response.write(jsonEncode(body));
    await response.close();
  }

  /// 生成随机十六进制密钥（token / server id）。
  static String randomHex(int bytes) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// 生成 6 位数字配对码。
  static String randomPairingCode() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }
}

class LanByteRange {
  const LanByteRange({required this.start, required this.end});

  final int start;
  final int end;

  int get length => end - start + 1;
}

/// 解析单段 `Range: bytes=...`。无法满足时返回 null；
/// 调用方需用 `rangeHeader != null && result == null` 判定 416。
@visibleForTesting
LanByteRange? parseByteRange(String? header, int fileLength) {
  if (header == null || fileLength <= 0) return null;
  final trimmed = header.trim();
  if (!trimmed.toLowerCase().startsWith('bytes=')) return null;
  final spec = trimmed.substring(6).split(',').first.trim();
  if (spec.isEmpty) return null;
  final dash = spec.indexOf('-');
  if (dash < 0) return null;
  final startText = spec.substring(0, dash).trim();
  final endText = spec.substring(dash + 1).trim();
  if (startText.isEmpty) {
    final suffix = int.tryParse(endText);
    if (suffix == null || suffix <= 0) return null;
    final length = suffix.clamp(1, fileLength);
    return LanByteRange(start: fileLength - length, end: fileLength - 1);
  }
  final start = int.tryParse(startText);
  if (start == null || start < 0 || start >= fileLength) return null;
  final end = endText.isEmpty
      ? fileLength - 1
      : (int.tryParse(endText) ?? (fileLength - 1)).clamp(
          start,
          fileLength - 1,
        );
  return LanByteRange(start: start, end: end);
}
