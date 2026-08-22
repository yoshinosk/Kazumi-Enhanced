import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/magnet/animes_garden_service.dart';

void main() {
  group('AnimesGardenService.formatAnimesGardenSize', () {
    test('API size 字段按字节处理，而非 KB（回归：曾放大 1024 倍）', () {
      // Animes Garden 实测返回值即为字节数：
      // 781398016 bytes ≈ 745 MB，3435973632 bytes ≈ 3.2 GB
      expect(AnimesGardenService.formatAnimesGardenSize(781398016), '745 MB');
      expect(AnimesGardenService.formatAnimesGardenSize(3435973632), '3.2 GB');
    });

    test('745 MB 量级的资源不应被格式化为 GB（防止 1024 倍误判）', () {
      // 旧实现会把 781398016 当作 KB，得到约 744 GB，进而让磁盘空间校验
      // 误判「空间不足」。修复后必须是 MB 级。
      final label = AnimesGardenService.formatAnimesGardenSize(781398016);
      expect(label, isNot(contains('GB')));
      expect(label, contains('MB'));
    });

    test('常规字节数换算正确', () {
      // 格式化约定：<100 保留 1 位小数（如 "3.2 GB"），>=100 取整（如 "745 MB"）
      expect(AnimesGardenService.formatAnimesGardenSize(1024), '1.0 KB');
      expect(AnimesGardenService.formatAnimesGardenSize(1048576), '1.0 MB');
      expect(AnimesGardenService.formatAnimesGardenSize(1073741824), '1.0 GB');
    });

    test('非法 / 空输入返回空字符串', () {
      expect(AnimesGardenService.formatAnimesGardenSize(null), '');
      expect(AnimesGardenService.formatAnimesGardenSize(''), '');
      expect(AnimesGardenService.formatAnimesGardenSize('abc'), '');
      expect(AnimesGardenService.formatAnimesGardenSize(0), '');
      expect(AnimesGardenService.formatAnimesGardenSize(-5), '');
    });
  });
}
