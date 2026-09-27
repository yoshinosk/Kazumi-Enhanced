import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/magnet/torrent_file_meta.dart';

/// 测试用最小 bencode 编码器：保证 info 字典切片与真实种子一致。
List<int> _bString(String s) =>
    [...utf8.encode('${utf8.encode(s).length}:'), ...utf8.encode(s)];

List<int> _bBytes(List<int> bytes) => [...utf8.encode('${bytes.length}:'), ...bytes];

List<int> _bInt(int v) => utf8.encode('i${v}e');

List<int> _bList(List<List<int>> items) =>
    [0x6c, ...items.expand((e) => e), 0x65];

List<int> _bDict(Map<List<int>, List<int>> entries) => [
      0x64,
      ...entries.entries.expand((e) => [...e.key, ...e.value]),
      0x65,
    ];

Uint8List _singleFileTorrent({
  required List<int> infoBytes,
  String announce = 'http://tracker.example/announce',
}) {
  return Uint8List.fromList(_bDict({
    _bString('announce'): _bString(announce),
    _bString('info'): infoBytes,
  }));
}

void main() {
  test('解析单文件种子：info-hash / 名称 / 总大小', () {
    final info = _bDict({
      _bString('length'): _bInt(123456789),
      _bString('name'): _bString('Sample Anime 01.mkv'),
      _bString('piece length'): _bInt(262144),
      _bString('pieces'): _bBytes(List.filled(40, 0xAB)),
    });
    final torrent = _singleFileTorrent(infoBytes: info);

    final meta = TorrentFileMeta.parse(torrent);

    expect(meta, isNotNull);
    final expected = crypto.sha1.convert(info).toString();
    expect(meta!.infoHashHex, expected);
    expect(meta.name, 'Sample Anime 01.mkv');
    expect(meta.totalLength, 123456789);
  });

  test('解析多文件种子：总大小为各文件之和', () {
    final info = _bDict({
      _bString('files'): _bList([
        _bDict({
          _bString('length'): _bInt(100),
          _bString('path'): _bList([_bString('a.mkv')]),
        }),
        _bDict({
          _bString('length'): _bInt(250),
          _bString('path'): _bList([_bString('sub'), _bString('b.ass')]),
        }),
      ]),
      _bString('name'): _bString('Sample Batch'),
      _bString('piece length'): _bInt(262144),
      _bString('pieces'): _bBytes(List.filled(20, 0x01)),
    });
    final torrent = _singleFileTorrent(infoBytes: info);

    final meta = TorrentFileMeta.parse(torrent);

    expect(meta, isNotNull);
    expect(meta!.infoHashHex, crypto.sha1.convert(info).toString());
    expect(meta.name, 'Sample Batch');
    expect(meta.totalLength, 350);
  });

  test('名称按 UTF-8 解码', () {
    final name = '【字幕组】某番剧 第01话 [1080P].mkv';
    final info = _bDict({
      _bString('length'): _bInt(1),
      _bString('name'): _bString(name),
      _bString('piece length'): _bInt(16384),
      _bString('pieces'): _bBytes(List.filled(20, 0x02)),
    });
    final torrent = _singleFileTorrent(infoBytes: info);

    final meta = TorrentFileMeta.parse(torrent);

    expect(meta, isNotNull);
    expect(meta!.name, name);
  });

  test('损坏数据返回 null', () {
    expect(TorrentFileMeta.parse(utf8.encode('not a torrent')), isNull);
    expect(TorrentFileMeta.parse(<int>[]), isNull);
  });

  test('缺少 info 字典返回 null', () {
    final torrent = _bDict({
      _bString('announce'): _bString('http://tracker.example/announce'),
    });
    expect(TorrentFileMeta.parse(torrent), isNull);
  });
}
