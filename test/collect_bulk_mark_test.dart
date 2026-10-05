import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/hive_registrar.g.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_change_module.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/services/storage/storage.dart';

BangumiItem _item(int id) => BangumiItem.fromJson({
      'id': id,
      'type': 2,
      'name': 'n$id',
      'name_cn': '',
      'summary': '',
      'date': '',
      'images': {'large': 'https://example.com/$id.jpg'},
      'rating': {'rank': 1, 'score': 5, 'total': 10},
    });

void main() {
  late Directory tempDir;
  late CollectController controller;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('kazumi_bulk_mark_test');
    Hive.init(tempDir.path);
    Hive.registerAdapters();
    GStorage.collectibles =
        await Hive.openBox<CollectedBangumi>('test_bulk_collectibles');
    GStorage.favorites =
        await Hive.openBox<BangumiItem>('test_bulk_favorites');
    GStorage.collectChanges =
        await Hive.openBox<CollectedBangumiChange>('test_bulk_collect_changes');
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException catch (_) {
      // Windows 上文件句柄释放可能有延迟，残留临时目录交给系统清理
    }
  });

  setUp(() async {
    await GStorage.collectibles.clear();
    await GStorage.collectChanges.clear();
    controller = CollectController(CollectCrudRepository(), CollectRepository());
  });

  group('CollectController.bulkSetCollect', () {
    test('未收藏 → 新增并记录 action=1', () async {
      final summary = await controller
          .bulkSetCollect([_item(1)], CollectType.watched.value);
      expect(summary.imported, 1);
      expect(summary.updated, 0);
      expect(summary.skipped, 0);
      expect(controller.getCollectType(_item(1)), CollectType.watched.value);

      final change = GStorage.collectChanges.values.single;
      expect(change.bangumiID, 1);
      expect(change.action, 1);
      expect(change.type, CollectType.watched.value);
    });

    test('已收藏且状态不同 → 覆盖更新并记录 action=2', () async {
      await controller.bulkSetCollect([_item(2)], CollectType.watching.value);
      final changesBefore = GStorage.collectChanges.length;

      final summary = await controller
          .bulkSetCollect([_item(2)], CollectType.watched.value);
      expect(summary.imported, 0);
      expect(summary.updated, 1);
      expect(controller.getCollectType(_item(2)), CollectType.watched.value);
      expect(GStorage.collectChanges.length, changesBefore + 1);

      final last = GStorage.collectChanges.values
          .reduce((a, b) => a.id > b.id ? a : b);
      expect(last.bangumiID, 2);
      expect(last.action, 2);
      expect(last.type, CollectType.watched.value);
    });

    test('已收藏且状态相同 → 跳过且不写变更日志', () async {
      await controller
          .bulkSetCollect([_item(3)], CollectType.planToWatch.value);
      final changesBefore = GStorage.collectChanges.length;

      final summary = await controller
          .bulkSetCollect([_item(3)], CollectType.planToWatch.value);
      expect(summary.skipped, 1);
      expect(summary.imported, 0);
      expect(summary.updated, 0);
      expect(GStorage.collectChanges.length, changesBefore);
    });

    test('批量混合：新增 / 跳过 / 更新并存', () async {
      await controller.bulkSetCollect([_item(4)], CollectType.onHold.value);

      final summary = await controller.bulkSetCollect([
        _item(5),
        _item(4),
        _item(6),
      ], CollectType.watched.value);

      expect(summary.imported, 2); // 5、6 新增
      expect(summary.updated, 1); // 4 搁置 → 看过
      expect(summary.skipped, 0);
      expect(controller.getCollectType(_item(4)), CollectType.watched.value);
      expect(controller.getCollectType(_item(5)), CollectType.watched.value);
      expect(controller.getCollectType(_item(6)), CollectType.watched.value);
    });
  });
}
