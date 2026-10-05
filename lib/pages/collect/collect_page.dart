import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/sync_priority.dart';
import 'package:kazumi/modules/collect/collect_layout.dart';
import 'package:kazumi/modules/collect/collect_sync_plan.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/collect/collect_library_view.dart';
import 'package:kazumi/pages/collect/collect_sync_dialog.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/bangumi_note_json.dart';

class CollectPage extends StatefulWidget {
  const CollectPage({
    super.key,
    required this.controller,
  });

  final CollectController controller;

  @override
  State<CollectPage> createState() => _CollectPageState();
}

class _CollectPageState extends State<CollectPage> with KazumiDialogOwner {
  CollectController get collectController => widget.controller;
  bool get _syncDialogOpen => dialogs.isRunning;
  final Set<int> _pendingIds = {};
  late CollectLayout _layout;

  Future<bool> _syncStep(
    CollectSyncStep step, {
    required ValueChanged<String> onError,
    required void Function(String message, int current, int total) onProgress,
  }) =>
      switch (step) {
        CollectSyncStep.webDav => collectController.syncCollectibles(
            onError: onError,
          ),
        CollectSyncStep.bangumi => collectController.syncCollectiblesBangumi(
            onError: onError,
            onProgress: onProgress,
          ),
        CollectSyncStep.upload => collectController.uploadCollectiblesToWebDav(
            onError: onError,
          ),
      };

  @override
  void initState() {
    super.initState();
    // Read once; page switches never change the saved default.
    _layout = CollectLayout.fromValue(
      GStorage.getSetting(SettingsKeys.defaultCollectLayout),
    );
    collectController.loadCollectibles();
  }

  void _changeLayout(CollectLayout layout) {
    if (_layout == layout) return;
    setState(() => _layout = layout);
  }

  Future<void> _changeType(BangumiItem item, CollectType type) async {
    if (_syncDialogOpen || _pendingIds.contains(item.id)) return;
    setState(() => _pendingIds.add(item.id));
    try {
      await collectController.addCollect(item, type: type.value);
    } catch (_) {
      KazumiDialog.showToast(message: '修改收藏状态失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _pendingIds.remove(item.id));
    }
  }

  Future<void> _sync() async {
    if (_syncDialogOpen || _pendingIds.isNotEmpty) return;
    final plan = CollectSyncPlan(
      webDavEnabled: GStorage.getSetting(SettingsKeys.webDavEnable),
      webDavCollectiblesEnabled:
          GStorage.getSetting(SettingsKeys.webDavEnableCollect),
      bangumiEnabled: GStorage.getSetting(SettingsKeys.bangumiSyncEnable),
    );
    await dialogs.run((task) async {
      final destination = await task.show<CollectSyncDestination>(
        builder: (_) => CollectSyncDialog(
          plan: plan,
          priority: BangumiSyncPriority.fromValue(
            GStorage.getSetting(SettingsKeys.bangumiSyncPriority),
          ),
          onSync: _syncStep,
        ),
      );
      task.withContext((context) => context.pushNamed(switch (destination) {
            CollectSyncDestination.webDavSettings => '/settings/webdav/',
            CollectSyncDestination.bangumiSettings => '/settings/bangumi/',
          }));
    }, errorMessage: '同步未完成，请稍后重试');
  }

  /// 导出收藏为 bangumi-note 兼容 JSON（可再导回 bangumi-note 或导入 Kazumi）。
  Future<void> _exportJson() async {
    try {
      final entries = collectController.collectibles.toList();
      if (entries.isEmpty) {
        KazumiDialog.showToast(message: '暂无收藏可导出');
        return;
      }
      final bytes = utf8.encode(BangumiNoteJson.encode(entries));
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: '导出追番记录',
        fileName: '追番记录.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
        lockParentWindow: true,
      );
      if (saved == null) return;
      KazumiDialog.showToast(message: '已导出 ${entries.length} 条收藏');
    } catch (e, stackTrace) {
      KazumiLogger()
          .e('Collect: failed to export collectibles', error: e, stackTrace: stackTrace);
      KazumiDialog.showToast(message: '导出失败：$e');
    }
  }

  /// 从 bangumi-note 兼容 JSON 导入收藏（仅新增，不覆盖已有状态）。
  Future<void> _importJson() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
        lockParentWindow: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw const FileSystemException('无法读取所选文件');
      final parsed = BangumiNoteJson.parse(utf8.decode(bytes));
      if (parsed.collectibles.isEmpty) {
        KazumiDialog.showToast(
            message: parsed.failureCount > 0
                ? '没有可导入的收藏（${parsed.failureCount} 条解析失败）'
                : '文件中没有可导入的收藏');
        return;
      }
      final summary =
          await collectController.importCollectibles(parsed.collectibles);
      KazumiDialog.showToast(
          message: '已导入 ${summary.imported} 条，跳过已有 ${summary.skipped} 条'
              '${parsed.failureCount > 0 ? '，解析失败 ${parsed.failureCount} 条' : ''}');
    } catch (e, stackTrace) {
      KazumiLogger()
          .e('Collect: failed to import collectibles', error: e, stackTrace: stackTrace);
      KazumiDialog.showToast(message: '导入失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        needTopOffset: false,
        toolbarHeight: 72,
        title: Text(
          '追番',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: '追番统计',
                  child: StateActionButton.tonal(
                    text: '统计',
                    onPressed: () => context.pushNamed('/stats/'),
                    icon: Icons.query_stats_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: '同步收藏',
                  child: StateActionButton.tonal(
                    text: '同步',
                    onPressed:
                        _syncDialogOpen || _pendingIds.isNotEmpty ? null : _sync,
                    icon: Icons.sync_rounded,
                  ),
                ),
                KazumiMenuButton(
                  builder: (context, toggle) => IconButton(
                    tooltip: '更多',
                    onPressed: toggle,
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                  menuChildren: [
                    KazumiMenuItem(
                      label: '导出追番记录 JSON',
                      leadingIcon: const Icon(Icons.ios_share_rounded),
                      onPressed: _exportJson,
                    ),
                    KazumiMenuItem(
                      label: '导入追番记录 JSON',
                      leadingIcon: const Icon(Icons.file_open_rounded),
                      onPressed: _importJson,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Observer(
          builder: (context) => CollectLibraryView(
            entries: collectController.collectibles.toList(),
            showRating: GStorage.getSetting(SettingsKeys.showRating),
            layout: _layout,
            onLayoutChanged: _changeLayout,
            canEdit: (item) =>
                !_syncDialogOpen && !_pendingIds.contains(item.id),
            onOpen: (item) => context.pushNamed('/info/', arguments: item),
            onChangeType: (item, type) => unawaited(_changeType(item, type)),
          ),
        ),
      ),
    );
  }
}
