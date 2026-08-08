import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 弹弹 Play `/api/v2/match` 规定的文件哈希算法：
/// 取视频文件**前 16 MiB** 的 MD5（十六进制小写）。
/// 文件不足 16 MiB 时取整个文件。
const int kDandanHashBytes = 16 * 1024 * 1024;

/// 计算本地视频文件用于弹弹 Play 匹配的哈希。
///
/// 使用流式读取，避免把大文件整体载入内存。失败时返回 null。
Future<String?> calculateDandanFileHash(String filePath) async {
  if (filePath.isEmpty) return null;
  final file = File(filePath);
  try {
    if (!await file.exists()) return null;
    final length = await file.length();
    if (length <= 0) return null;

    final end = length < kDandanHashBytes ? length : kDandanHashBytes;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, end)) {
      builder.add(chunk);
      if (builder.length >= end) break;
    }
    var bytes = builder.takeBytes();
    if (bytes.length > end) {
      bytes = Uint8List.sublistView(bytes, 0, end);
    }
    return md5.convert(bytes).toString();
  } catch (e) {
    KazumiLogger()
        .w('DandanFileHash: failed to hash file $filePath', error: e);
    return null;
  }
}

/// 读取文件字节数，失败返回 0。
Future<int> readFileSize(String filePath) async {
  if (filePath.isEmpty) return 0;
  try {
    final file = File(filePath);
    if (!await file.exists()) return 0;
    return await file.length();
  } catch (_) {
    return 0;
  }
}
