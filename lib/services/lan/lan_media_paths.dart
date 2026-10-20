import 'dart:convert';

/// 局域网媒体库路径使用的伪协议前缀。
///
/// 手机端不保存桌面端的真实绝对路径：把桌面文件映射为
/// `kazumi-lan://<serverId>/f/<base64(真实路径)>`，既能让历史记录、
/// 续播点、搜刮结果继续按「路径」作为稳定标识，也不会与手机本地
/// 文件路径混淆。真实路径只在请求桌面端流媒体时还原。
const String kLanMediaScheme = 'kazumi-lan';
const String kLanMediaPathPrefix = '$kLanMediaScheme://';

bool isLanMediaPath(String path) => path.startsWith(kLanMediaPathPrefix);

String _encodePathSegment(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

String? _decodePathSegment(String value) {
  try {
    final padded = value.padRight((value.length + 3) & ~3, '=');
    return utf8.decode(base64Url.decode(padded));
  } catch (_) {
    return null;
  }
}

/// 桌面端目录在手机端的稳定标识。
String lanFolderPath(String serverId, String remotePath) =>
    '$kLanMediaPathPrefix${Uri.encodeComponent(serverId)}/d/'
    '${_encodePathSegment(remotePath)}';

/// 桌面端文件在手机端的稳定标识。
String lanFilePath(String serverId, String remotePath) =>
    '$kLanMediaPathPrefix${Uri.encodeComponent(serverId)}/f/'
    '${_encodePathSegment(remotePath)}';

/// 解析伪路径；[isFolder] 区分目录级与文件级标识。
({String serverId, String remotePath, bool isFolder})? parseLanMediaPath(
  String path,
) {
  if (!isLanMediaPath(path)) return null;
  final rest = path.substring(kLanMediaPathPrefix.length);
  final slash = rest.indexOf('/');
  if (slash <= 0 || slash + 3 > rest.length) return null;
  final serverId = Uri.decodeComponent(rest.substring(0, slash));
  final tail = rest.substring(slash + 1);
  if (tail.length < 3 || tail[1] != '/') return null;
  final kind = tail[0];
  if (kind != 'd' && kind != 'f') return null;
  final remotePath = _decodePathSegment(tail.substring(2));
  if (remotePath == null) return null;
  return (serverId: serverId, remotePath: remotePath, isFolder: kind == 'd');
}

/// 伪路径的服务器 ID（非局域网路径返回 null）。
String? lanServerIdOf(String path) => parseLanMediaPath(path)?.serverId;

/// 伪路径对应的桌面端真实路径（非局域网路径返回 null）。
String? lanRemotePathOf(String path) => parseLanMediaPath(path)?.remotePath;

/// 判断路径是否属于指定桌面端。
bool isLanPathOfServer(String path, String serverId) =>
    lanServerIdOf(path) == serverId;

/// 日志 / 错误提示用：隐藏局域网流地址中的 token。
String redactLanStreamToken(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.queryParameters.containsKey('token')) return url;
  final query = Map<String, String>.from(uri.queryParameters);
  query['token'] = '***';
  return uri.replace(queryParameters: query).toString();
}

/// 生成桌面端流媒体地址（token 放在 query，media_kit / mpv 无需额外请求头）。
String buildLanStreamUrl({
  required String host,
  required int port,
  required String token,
  required String remotePath,
}) {
  final encoded = base64Url.encode(utf8.encode(remotePath)).replaceAll('=', '');
  return Uri(
    scheme: 'http',
    host: host,
    port: port,
    path: '/api/v1/stream',
    queryParameters: {'path': encoded, 'token': token},
  ).toString();
}
