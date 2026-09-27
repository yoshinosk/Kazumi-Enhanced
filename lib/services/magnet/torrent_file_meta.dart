import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 从 .torrent 文件（bencode）解析出的元数据摘要。
///
/// [infoHashHex] 为 info 字典原始字节的 SHA-1（小写 hex），即磁力链
/// `xt=urn:btih:` 使用的 v1 info-hash；[name] 为种子内建名称
/// （info.name，UTF-8）；[totalLength] 为全部文件字节总数。
class TorrentFileMeta {
  const TorrentFileMeta({
    required this.infoHashHex,
    required this.name,
    required this.totalLength,
  });

  final String infoHashHex;
  final String name;
  final int totalLength;

  /// 解析 .torrent 文件字节；损坏或缺少 info 字典时返回 null。
  ///
  /// info-hash 必须对文件中 info 字典的**原始字节切片**做 SHA-1，
  /// 不能重新编码，因此这里只做扫描定位而不重建 bencode 结构。
  static TorrentFileMeta? parse(List<int> bytes) {
    try {
      final root = _BencodeScanner(bytes).scan();
      if (root == null || root.value is! Map<String, _BencodeNode>) return null;
      final info = (root.value as Map<String, _BencodeNode>)['info'];
      if (info == null || info.value is! Map<String, _BencodeNode>) return null;
      final infoMap = info.value as Map<String, _BencodeNode>;
      final hash = sha1
          .convert(Uint8List.sublistView(
            bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
            info.start,
            info.end,
          ))
          .toString();
      final name = _decodeUtf8(infoMap['name']?.value);
      var total = 0;
      final length = infoMap['length']?.value;
      if (length is int) {
        total = length;
      } else {
        // 多文件种子：累加 info.files[].length。
        final files = infoMap['files']?.value;
        if (files is List<_BencodeNode>) {
          for (final fileNode in files) {
            final fileMap = fileNode.value;
            if (fileMap is Map<String, _BencodeNode>) {
              final fileLength = fileMap['length']?.value;
              if (fileLength is int) total += fileLength;
            }
          }
        }
      }
      return TorrentFileMeta(
        infoHashHex: hash,
        name: name,
        totalLength: total,
      );
    } catch (_) {
      return null;
    }
  }

  static String _decodeUtf8(Object? value) {
    if (value is List<int>) {
      return utf8.decode(value, allowMalformed: true);
    }
    return '';
  }
}

/// 一个 bencode 节点：解析出的值 + 它在原始字节中的切片范围。
class _BencodeNode {
  _BencodeNode(this.value, this.start, this.end);

  /// 字节串为原始 List<int>，整数为 int，列表 / 字典为对应节点容器。
  final Object? value;
  final int start;
  final int end;
}

/// 最小 bencode 扫描器：只为定位 info 字典切片，不求完整容错。
class _BencodeScanner {
  _BencodeScanner(this._bytes);

  static const int _maxDepth = 64;

  final List<int> _bytes;
  int _pos = 0;

  _BencodeNode? scan() {
    final node = _scanNode(0);
    if (node == null) return null;
    return node;
  }

  _BencodeNode? _scanNode(int depth) {
    if (depth > _maxDepth || _pos >= _bytes.length) return null;
    final start = _pos;
    final b = _bytes[_pos];
    if (b == 0x69) {
      // i<digits>e（种子内长度均为非负，负数直接判为损坏）
      _pos++;
      var value = 0;
      var hasDigits = false;
      while (_pos < _bytes.length && _bytes[_pos] != 0x65) {
        final c = _bytes[_pos];
        if (c < 0x30 || c > 0x39) return null;
        value = value * 10 + (c - 0x30);
        hasDigits = true;
        _pos++;
      }
      if (!hasDigits || _pos >= _bytes.length) return null;
      _pos++; // 'e'
      return _BencodeNode(value, start, _pos);
    }
    if (b >= 0x30 && b <= 0x39) {
      // `<length>:<bytes>`
      var length = 0;
      while (_pos < _bytes.length && _bytes[_pos] != 0x3a) {
        final c = _bytes[_pos];
        if (c < 0x30 || c > 0x39) return null;
        length = length * 10 + (c - 0x30);
        if (length < 0 || length > _bytes.length) return null;
        _pos++;
      }
      if (_pos >= _bytes.length) return null;
      _pos++; // ':'
      if (length < 0 || _pos + length > _bytes.length) return null;
      final value = Uint8List.sublistView(
        _bytes is Uint8List ? _bytes : Uint8List.fromList(_bytes),
        _pos,
        _pos + length,
      );
      _pos += length;
      return _BencodeNode(List<int>.unmodifiable(value), start, _pos);
    }
    if (b == 0x6c) {
      // l<values>e
      _pos++;
      final items = <_BencodeNode>[];
      while (_pos < _bytes.length && _bytes[_pos] != 0x65) {
        final item = _scanNode(depth + 1);
        if (item == null) return null;
        items.add(item);
      }
      if (_pos >= _bytes.length) return null;
      _pos++; // 'e'
      return _BencodeNode(items, start, _pos);
    }
    if (b == 0x64) {
      // d<key><value>e
      _pos++;
      final entries = <String, _BencodeNode>{};
      while (_pos < _bytes.length && _bytes[_pos] != 0x65) {
        final keyNode = _scanNode(depth + 1);
        if (keyNode == null || keyNode.value is! List<int>) return null;
        final key = latin1.decode(keyNode.value as List<int>, allowInvalid: true);
        final valueNode = _scanNode(depth + 1);
        if (valueNode == null) return null;
        entries[key] = valueNode;
      }
      if (_pos >= _bytes.length) return null;
      _pos++; // 'e'
      return _BencodeNode(entries, start, _pos);
    }
    return null;
  }
}
