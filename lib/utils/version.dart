import 'dart:math';

/// 版本号分段。
///
/// 兼容 release tag 常见的写法：`v1.0.1` 这类「v」前缀、`1.0.6-beta`
/// 这类预发布后缀，以及 `1.0.5+1` 这类带 build number 的形式。每段只取
/// 开头的数字，其余部分忽略，避免 `int.parse` 遇到非数字时抛异常导致
/// 更新检查直接失败。
List<int> _versionSegments(String version) {
  var v = version.trim();
  if (v.startsWith('v') || v.startsWith('V')) {
    v = v.substring(1);
  }
  if (v.isEmpty) {
    return const [];
  }
  return [for (final segment in v.split('.')) _leadingNumber(segment)];
}

int _leadingNumber(String segment) {
  final match = RegExp(r'\d+').firstMatch(segment);
  if (match == null) {
    return 0;
  }
  return int.tryParse(match.group(0)!) ?? 0;
}

bool needUpdate(String localVersion, String remoteVersion) {
  final localVersionList = _versionSegments(localVersion);
  final remoteVersionList = _versionSegments(remoteVersion);
  final maxLength = max(localVersionList.length, remoteVersionList.length);
  for (var i = 0; i < maxLength; i++) {
    final localSegment =
        i < localVersionList.length ? localVersionList[i] : 0;
    final remoteSegment =
        i < remoteVersionList.length ? remoteVersionList[i] : 0;
    if (remoteSegment > localSegment) {
      return true;
    } else if (remoteSegment < localSegment) {
      return false;
    }
  }
  return false;
}
