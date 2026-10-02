String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
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
