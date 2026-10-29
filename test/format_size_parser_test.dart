import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/format.dart';

void main() {
  group('parseSizeToBytes', () {
    test('解析常见的体积文案', () {
      expect(parseSizeToBytes('1.2 GB'), (1.2 * 1024 * 1024 * 1024).round());
      expect(parseSizeToBytes('800MB'), 800 * 1024 * 1024);
      expect(parseSizeToBytes('1,234 MB'), 1234 * 1024 * 1024);
      expect(parseSizeToBytes('  1 GB  '), 1024 * 1024 * 1024);
      expect(parseSizeToBytes('12.5GiB'), (12.5 * 1024 * 1024 * 1024).round());
      expect(parseSizeToBytes('0 B'), 0);
    });

    test('无法识别时返回 null', () {
      expect(parseSizeToBytes(''), isNull);
      expect(parseSizeToBytes('   '), isNull);
      expect(parseSizeToBytes('未知'), isNull);
      expect(parseSizeToBytes('1080p'), isNull);
    });

    test('与 formatBytes 互为逆运算（1 位小数精度内的值）', () {
      const bytes = 3 * 1024 * 1024 * 1024;
      final label = formatBytes(bytes);
      expect(parseSizeToBytes(label), bytes);
    });
  });
}
