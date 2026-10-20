import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kazumi/services/lan/lan_sync_models.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 局域网桌面端发现。
///
/// 采用 UDP 广播而不是 mDNS：不引入额外依赖，Android / Windows 双端
/// 行为一致；同时提供手动地址探测，广播被路由器隔离或防火墙拦截时
/// 仍可连接。
class LanDiscovery {
  LanDiscovery._();

  /// 广播发现（默认等待 1.6 秒）。
  static Future<List<LanDiscoveredServer>> discover({
    Duration timeout = const Duration(milliseconds: 1600),
  }) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    final found = <String, LanDiscoveredServer>{};
    final done = Completer<void>();

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        final server = _parseDatagram(datagram.data, datagram.address.address);
        if (server == null) return;
        found[server.serverId] = server;
      });

      final targets = await _broadcastTargets();
      final probe = utf8.encode(kLanSyncDiscoveryProbe);
      void sendProbe() {
        for (final target in targets) {
          try {
            socket?.send(probe, InternetAddress(target), kLanSyncDiscoveryPort);
          } catch (_) {
            // 单个网卡发送失败不影响其他地址。
          }
        }
      }

      sendProbe();
      final retry1 = Timer(const Duration(milliseconds: 350), sendProbe);
      final retry2 = Timer(const Duration(milliseconds: 850), sendProbe);
      final finish = Timer(timeout, () {
        if (!done.isCompleted) done.complete();
      });
      await done.future;
      retry1.cancel();
      retry2.cancel();
      finish.cancel();
    } catch (e) {
      KazumiLogger().w('LanDiscovery: broadcast failed', error: e);
    } finally {
      await subscription?.cancel();
      socket?.close();
    }

    final result = found.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    KazumiLogger().i('LanDiscovery: found ${result.length} server(s)');
    return result;
  }

  /// 直连探测指定地址（手动输入或上次连接记录）。
  static Future<LanDiscoveredServer?> probe(
    String host,
    int port, {
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/api/v1/info',
      );
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) return null;
      final json = jsonDecode(text);
      if (json is! Map) return null;
      final info = LanServerInfo.fromJson(Map<String, dynamic>.from(json));
      if (info.serverId.isEmpty || info.protocol != kLanSyncProtocolVersion) {
        return null;
      }
      return LanDiscoveredServer(host: host, info: info);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static LanDiscoveredServer? _parseDatagram(
    List<int> data,
    String sourceHost,
  ) {
    try {
      final text = utf8.decode(data);
      final json = jsonDecode(text);
      if (json is! Map) return null;
      if (json['type'] != 'kazumi-lan-server') return null;
      final info = LanServerInfo.fromJson(Map<String, dynamic>.from(json));
      if (info.serverId.isEmpty ||
          info.protocol != kLanSyncProtocolVersion ||
          sourceHost.isEmpty) {
        return null;
      }
      // 发现响应里的 host 由 UDP 源地址决定，服务端不需要自报 IP。
      return LanDiscoveredServer(host: sourceHost, info: info);
    } catch (_) {
      return null;
    }
  }

  /// 常见局域网广播地址：受限广播 + 每个私有网段猜测的 /24 广播。
  static Future<Set<String>> _broadcastTargets() async {
    final targets = <String>{'255.255.255.255'};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final octets = address.rawAddress;
          if (octets.length != 4) continue;
          final second = octets[1];
          final isPrivate =
              octets[0] == 10 ||
              (octets[0] == 192 && second == 168) ||
              (octets[0] == 172 && second >= 16 && second <= 31);
          if (!isPrivate) continue;
          targets.add('${octets[0]}.${octets[1]}.${octets[2]}.255');
        }
      }
    } catch (_) {}
    return targets;
  }
}
