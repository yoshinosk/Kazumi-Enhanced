String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

/// 解析体积文案（`1.2 GB` / `800MB` / `1,234 MB` / `1.5 TiB`）为字节数。
///
/// 搜索结果里的体积是站点给出的自由文本，格式并不统一；无法识别或
/// 数值非法时返回 null，由调用方决定跳过还是按未知处理。
int? parseSizeToBytes(String label) {
  if (label.trim().isEmpty) return null;
  final match = RegExp(
    r'([\d.,]+)\s*([KMGT]?i?B)',
    caseSensitive: false,
  ).firstMatch(label.trim());
  if (match == null) return null;
  final raw = match.group(1)!.replaceAll(',', '');
  final value = double.tryParse(raw);
  if (value == null || value < 0) return null;
  final unit = match.group(2)!.toUpperCase().replaceAll('I', '');
  const mult = {
    'B': 1,
    'KB': 1024,
    'MB': 1048576,
    'GB': 1073741824,
    'TB': 1099511627776,
  };
  final m = mult[unit];
  if (m == null) return null;
  return (value * m).round();
}

String formatSpeed(double bytesPerSec) {
  if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)} B/s';
  if (bytesPerSec < 1024 * 1024) {
    return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
  }
  return '${(bytesPerSec / 1024 / 1024).toStringAsFixed(1)} MB/s';
}

String durationToString(Duration duration) {
  String pad(int n) => n.toString().padLeft(2, '0');
  final hours = pad(duration.inHours % 24);
  final minutes = pad(duration.inMinutes % 60);
  final seconds = pad(duration.inSeconds % 60);
  if (hours == '00') {
    return '$minutes:$seconds';
  }
  return '$hours:$minutes:$seconds';
}

/// 相对时间文案（按自然日对齐）：今天 / 昨天 / N 天前 / N 周前 /
/// N 个月前 / N 年前。未来时间（时钟偏差）按今天处理。
String formatTimeAgo(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return '今天';
  if (days == 1) return '昨天';
  if (days < 7) return '$days 天前';
  if (days < 30) return '${days ~/ 7} 周前';
  if (days < 365) return '${days ~/ 30} 个月前';
  return '${days ~/ 365} 年前';
}
