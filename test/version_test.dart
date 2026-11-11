import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/version.dart';

void main() {
  group('needUpdate', () {
    test('相同版本（含 v 前缀与空白）不提示更新', () {
      expect(needUpdate('1.0.5', 'v1.0.5'), isFalse);
      expect(needUpdate('1.0.5', 'V1.0.5'), isFalse);
      expect(needUpdate('1.0.5', '  v1.0.5  '), isFalse);
    });

    test('远端更高时提示更新', () {
      expect(needUpdate('1.0.4', 'v1.0.5'), isTrue);
      expect(needUpdate('1.0.9', 'v1.0.10'), isTrue);
      expect(needUpdate('1.0', 'v1.0.1'), isTrue);
    });

    test('本地更高或补零段不提示更新', () {
      expect(needUpdate('1.0.10', 'v1.0.9'), isFalse);
      expect(needUpdate('1.0.5.0', 'v1.0.5'), isFalse);
      expect(needUpdate('1.0.5+1', 'v1.0.5'), isFalse);
    });

    test('预发布后缀不会抛异常', () {
      expect(needUpdate('1.0.5', 'v1.0.6-beta'), isTrue);
      expect(needUpdate('1.0.6', 'v1.0.6-rc1'), isFalse);
    });

    test('无法识别的版本按 0 段处理', () {
      expect(needUpdate('0.0.0', 'v1.0.5'), isTrue);
      expect(needUpdate('', 'v1.0.5'), isTrue);
      expect(needUpdate('dev', 'v1.0.5'), isTrue);
      expect(needUpdate('1.0.5', ''), isFalse);
    });
  });
}
