import 'dart:math';

/// 版本号分段，兼容 release tag 常见的「v」前缀（如 v1.0.1）。
List<String> _versionSegments(String version) {
  var v = version.trim();
  if (v.startsWith('v') || v.startsWith('V')) {
    v = v.substring(1);
  }
  return v.split('.');
}

bool needUpdate(String localVersion, String remoteVersion) {
  final localVersionList = _versionSegments(localVersion);
  final remoteVersionList = _versionSegments(remoteVersion);
  final maxLength = max(localVersionList.length, remoteVersionList.length);
  for (var i = 0; i < maxLength; i++) {
    final localSegment =
        i < localVersionList.length ? int.parse(localVersionList[i]) : 0;
    final remoteSegment =
        i < remoteVersionList.length ? int.parse(remoteVersionList[i]) : 0;
    if (remoteSegment > localSegment) {
      return true;
    } else if (remoteSegment < localSegment) {
      return false;
    }
  }
  return false;
}
