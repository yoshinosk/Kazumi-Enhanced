import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/crypto.dart';
import 'package:kazumi/utils/http_headers.dart';

class BangumiClient {
  BangumiClient._();

  static final BangumiClient instance = BangumiClient._();

  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
    String? accessToken,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await DioFactory.bangumiDio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          headers: _headers(
            requiresAuth: requiresAuth,
            accessToken: accessToken,
            url: url,
            method: 'GET',
          ),
        ),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  Future<dynamic> post(
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await DioFactory.bangumiDio.post(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          headers: _headers(
            requiresAuth: requiresAuth,
            url: url,
            method: 'POST',
            data: data,
          ),
        ),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  /// A Dio that reaches the official Bangumi API directly, bypassing the
  /// mirror proxy/signing interceptor. Used as a fallback for search when the
  /// mirror (which requires the private app signature) is unavailable: logged
  /// in users can still search via their personal token, routed through the
  /// app's configured proxy / Windows system proxy.
  static Dio? _directDio;
  static Dio get directDio => _directDio ??= DioFactory.createForConfig(
        NetworkConfig.fromSettings(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
        defaultHeaders: {
          'referer': '',
          'user-agent': getRandomUA(),
        },
      );

  Future<dynamic> postDirect(
    String url, {
    Object? data,
    bool requiresAuth = false,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await directDio.post(
        url,
        data: data,
        options: Options(
          headers: _directHeaders(requiresAuth: requiresAuth),
        ),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  Map<String, dynamic> _directHeaders({bool requiresAuth = false}) {
    final headers = <String, dynamic>{...bangumiHTTPHeader};
    final token = GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim();
    if (requiresAuth && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, dynamic> _headers({
    required bool requiresAuth,
    String? accessToken,
    required String url,
    required String method,
    Object? data,
  }) {
    final headers = <String, dynamic>{...bangumiHTTPHeader};
    final bangumiSyncEnable = GStorage.getSetting(
      SettingsKeys.bangumiSyncEnable,
    );
    final token =
        (accessToken ??
                GStorage.getSetting<String>(SettingsKeys.bangumiAccessToken))
            .trim();
    if ((requiresAuth || bangumiSyncEnable) && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (_shouldSignProtectedMirrorRequest(url, method)) {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final body = data == null ? '' : jsonEncode(data);
      headers['X-AppId'] = bangumiMirrorCredentials['id'];
      headers['X-Timestamp'] = timestamp;
      headers['X-Signature'] = generateBangumiMirrorSearchSignature(
        method: method,
        path: Uri.parse(url).path,
        body: body,
        timestamp: timestamp,
      );
    }
    return headers;
  }

  bool _shouldSignProtectedMirrorRequest(String url, String method) {
    // 本分支私有镜像凭据仅经 --dart-define=KAZUMI_APPID/KAZUMI_KEY 注入；
    // 缺失时无法产生有效签名，空签名只会被镜像拒收，故直接跳过。
    final mirrorId = bangumiMirrorCredentials['id'];
    if (mirrorId == null || mirrorId.isEmpty) {
      return false;
    }
    final uri = Uri.parse(url);
    // 私有镜像直连（bangumiAPIDomain）：沿用旧「Bangumi 镜像」开关；
    // 上游公共 API 域名：仅在镜像加速模式下签名。
    final isPrivateMirror =
        uri.host == Uri.parse(ApiEndpoints.bangumiAPIDomain).host;
    final signPrivateMirror =
        isPrivateMirror &&
        GStorage.getSetting(SettingsKeys.enableBangumiProxy);
    final signPublicMirror =
        BangumiAcceleration.current == BangumiAcceleration.mirror &&
        ApiEndpoints.bangumiPublicApiHosts.contains(uri.host);
    if (!signPrivateMirror && !signPublicMirror) {
      return false;
    }
    final path = uri.path;
    if (method == 'POST' && path == '/v0/search/subjects') {
      return true;
    }
    if (method != 'GET') {
      return false;
    }
    return path.startsWith('/p1/subjects/') && path.endsWith('/comments') ||
        path.startsWith('/p1/episodes/') && path.endsWith('/comments') ||
        path.startsWith('/p1/characters/') && path.endsWith('/comments');
  }
}
