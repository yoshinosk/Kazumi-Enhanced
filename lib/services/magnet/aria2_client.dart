import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/storage/storage.dart';

/// Aria2 JSON-RPC 客户端。
///
/// 仅实现磁力 / 种子下载所需的最小接口：addUri、tellStatus、getGlobalStat、
/// pause / unpause / remove。RPC 协议见
/// https://aria2.github.io/manual/en/html/aria2c.html#rpc-interface
class Aria2Client {
  Aria2Client();

  /// 内置引擎运行期注入的 RPC 端点；非空时优先于设置中的“RPC 地址/密钥”。
  static String? overrideRpcUrl;
  static String? overrideSecret;

  int _nextId = 1;

  String get _rpcUrl {
    final override = Aria2Client.overrideRpcUrl;
    if (override != null && override.trim().isNotEmpty) return override;
    final url = GStorage.getSetting(SettingsKeys.magnetAria2RpcUrl).trim();
    return url.isEmpty ? 'http://localhost:6800/jsonrpc' : url;
  }

  String get _secret {
    final override = Aria2Client.overrideSecret;
    if (override != null && override.isNotEmpty) return override;
    final secret = GStorage.getSetting(SettingsKeys.magnetAria2Secret).trim();
    return secret;
  }

  bool get isEnabled =>
      Aria2Client.overrideRpcUrl != null ||
      GStorage.getSetting(SettingsKeys.magnetAria2Enable);

  /// 不经过设置、直接探测指定 RPC 端点是否可用（引擎启动时用于等待就绪）。
  static Future<bool> rpcProbe(String url, String secret) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      headers: {'content-type': 'application/json'},
    ));
    final token = secret.isEmpty ? <String>[] : <String>['token:$secret'];
    try {
      final response = await dio.post<String>(
        url,
        data: jsonEncode({
          'jsonrpc': '2.0',
          'id': 'kazumi-probe',
          'method': 'aria2.getVersion',
          'params': token,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      final decoded = jsonDecode(response.data ?? '');
      return decoded is Map && decoded.containsKey('result');
    } catch (_) {
      return false;
    }
  }

  /// 便捷方法：修改单个全局选项。
  Future<bool> changeGlobalOptionValue(String key, String value) {
    return changeGlobalOption({key: value});
  }

  Dio get _dio {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      headers: {'content-type': 'application/json'},
    ));
    return dio;
  }

  Future<Map<String, dynamic>?> _call(
    String method, {
    List<dynamic>? params,
  }) async {
    final id = 'kazumi-${_nextId++}';
    final tokenParams = <dynamic>[];
    if (_secret.isNotEmpty) {
      tokenParams.add('token:$_secret');
    }
    if (params != null) {
      tokenParams.addAll(params);
    }
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': tokenParams,
    });
    try {
      final response = await _dio.post<String>(
        _rpcUrl,
        data: body,
        options: Options(responseType: ResponseType.plain),
      );
      final data = response.data ?? '';
      if (data.isEmpty) return null;
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded.containsKey('error')) {
        KazumiLogger().w('Aria2Client: RPC error on $method: ${decoded['error']}');
        return null;
      }
      return decoded;
    } on DioException catch (e) {
      KazumiLogger().w('Aria2Client: RPC transport failed: $method', error: e);
      return null;
    } catch (e) {
      KazumiLogger().w('Aria2Client: RPC parse failed: $method', error: e);
      return null;
    }
  }

  /// 测试 RPC 连接是否可用。返回版本号或 null。
  Future<String?> ping() async {
    final result = await _call('aria2.getVersion');
    if (result == null) return null;
    final version = result['result'];
    if (version is Map && version['version'] is String) {
      return version['version'] as String;
    }
    return null;
  }

  /// 添加磁力链 / 种子直链下载，返回 GID 或 null。
  Future<String?> addUri(
    String uri, {
    Map<String, String>? options,
  }) async {
    final optList = <String>[];
    if (options != null) {
      options.forEach((key, value) {
        optList.add('$key=$value');
      });
    }
    final result = await _call('aria2.addUri', params: [
      [uri],
      optList,
    ]);
    if (result == null) return null;
    final gid = result['result'];
    if (gid is String && gid.isNotEmpty) return gid;
    return null;
  }

  /// 查询任务状态。
  Future<MagnetDownloadTask?> tellStatus(String gid) async {
    final result = await _call('aria2.tellStatus', params: [
      gid,
      [
        'gid',
        'status',
        'totalLength',
        'completedLength',
        'downloadSpeed',
        'files',
      ],
    ]);
    if (result == null) return null;
    final status = result['result'];
    if (status is! Map) return null;
    final files = status['files'];
    String fileName = '';
    if (files is List && files.isNotEmpty) {
      final firstFile = files.first;
      if (firstFile is Map) {
        final path = firstFile['path'];
        if (path is String && path.isNotEmpty) {
          fileName = path;
        }
      }
    }
    return MagnetDownloadTask(
      gid: gid,
      status: (status['status'] as String?) ?? 'unknown',
      totalLength: _parseInt(status['totalLength']),
      completedLength: _parseInt(status['completedLength']),
      downloadSpeed: _parseInt(status['downloadSpeed']),
      fileName: fileName,
    );
  }

  /// 暂停任务。
  Future<bool> pause(String gid) async {
    final result = await _call('aria2.pause', params: [gid]);
    return result?['result'] == gid;
  }

  /// 恢复任务。
  Future<bool> unpause(String gid) async {
    final result = await _call('aria2.unpause', params: [gid]);
    return result?['result'] == gid;
  }

  /// 删除任务（包括已下载文件需调用 aria2.removeDownloadResult）。
  Future<bool> remove(String gid) async {
    final result = await _call('aria2.remove', params: [gid]);
    return result?['result'] == gid;
  }

  /// 获取某个 BitTorrent 任务的当前对等节点列表（用于吸血/异常检测）。
  Future<List<MagnetPeer>> getPeers(String gid) async {
    final result = await _call('aria2.getPeers', params: [gid]);
    final list = result?['result'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => MagnetPeer.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// 动态修改某个任务的选项（bt-max-peers / bt-request-peer-speed-limit
  /// 等可在运行期直接修改且不触发重启）。
  Future<bool> changeOption(String gid, Map<String, String> options) async {
    final result = await _call('aria2.changeOption', params: [gid, options]);
    return result?['result'] == 'OK';
  }

  /// 动态修改全局选项（max-overall-upload-limit、bt-tracker 等）。
  Future<bool> changeGlobalOption(Map<String, String> options) async {
    final result = await _call('aria2.changeGlobalOption', params: [options]);
    return result?['result'] == 'OK';
  }

  /// 获取全局统计（下载/上传速度、任务数）。
  Future<MagnetGlobalStat?> getGlobalStat() async {
    final result = await _call('aria2.getGlobalStat');
    if (result == null) return null;
    final stat = result['result'];
    if (stat is! Map) return null;
    return MagnetGlobalStat.fromJson(Map<String, dynamic>.from(stat));
  }

  /// 获取会话 ID，用于确认当前连接的确实是应用自带的引擎实例。
  Future<String?> getSessionInfo() async {
    final result = await _call('aria2.getSessionInfo');
    final info = result?['result'];
    if (info is Map) return info['sessionId'] as String?;
    return null;
  }

  /// 优雅关闭引擎（等待任务结束），随后进程自行退出。
  Future<bool> shutdown() async {
    final result = await _call('aria2.shutdown');
    return result != null;
  }

  /// 强制关闭引擎。
  Future<bool> forceShutdown() async {
    final result = await _call('aria2.forceShutdown');
    return result != null;
  }

  /// 获取活动任务列表。
  Future<List<MagnetDownloadTask>> tellActive() async {
    final result = await _call('aria2.tellActive', params: [
      [
        'gid',
        'status',
        'totalLength',
        'completedLength',
        'downloadSpeed',
        'files',
      ],
    ]);
    final list = result?['result'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => MagnetDownloadTask(
              gid: (m['gid'] as String?) ?? '',
              status: (m['status'] as String?) ?? 'unknown',
              totalLength: _parseInt(m['totalLength']),
              completedLength: _parseInt(m['completedLength']),
              downloadSpeed: _parseInt(m['downloadSpeed']),
              fileName: _extractFileName(m['files']),
            ))
        .where((t) => t.gid.isNotEmpty)
        .toList();
  }

  String _extractFileName(dynamic files) {
    if (files is List && files.isNotEmpty) {
      final firstFile = files.first;
      if (firstFile is Map) {
        final path = firstFile['path'];
        if (path is String && path.isNotEmpty) return path;
      }
    }
    return '';
  }

  /// aria2 RPC 返回的数值字段可能是 int 或字符串，统一解析为 int。
  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
