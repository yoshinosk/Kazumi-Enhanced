import 'dart:async';

import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/widget/collect_button.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/modules/collect/collect_sync_plan.dart';
import 'package:kazumi/services/storage/storage.dart';

class CollectPage extends StatefulWidget {
  const CollectPage({
    super.key,
    required this.controller,
  });

  final CollectController controller;

  @override
  State<CollectPage> createState() => _CollectPageState();
}

class _CollectPageState extends State<CollectPage>
    with SingleTickerProviderStateMixin {
  CollectController get collectController => widget.controller;
  TabController? tabController;
  bool showDelete = false;
  bool syncCollectiblesing = false;

  Future<bool> _syncBangumiWithProgress({
    required GlobalKey<_FullSyncProgressDialogState> progressDialogKey,
  }) async {
    progressDialogKey.currentState?.update('准备同步 Bangumi 收藏...', null);

    await Future<void>.delayed(const Duration(milliseconds: 80));

    return collectController.syncCollectiblesBangumi(
      showSuccessToast: false,
      onProgress: (message, current, total) {
        progressDialogKey.currentState?.update(
          total > 0 ? '$message ($current/$total)' : message,
          total > 0 ? (current / total).clamp(0.0, 1.0).toDouble() : null,
        );
      },
    );
  }

  void _showFullSyncProgressDialog({
    required GlobalKey<_FullSyncProgressDialogState> progressDialogKey,
  }) {
    unawaited(KazumiDialog.show(
      clickMaskDismiss: false,
      builder: (context) => _FullSyncProgressDialog(key: progressDialogKey),
    ));
  }

  String _buildFullSyncSummary({
    required CollectSyncPlan plan,
    required bool webDavSynced,
    required bool bangumiSynced,
    required bool webDavUploaded,
  }) {
    final List<String> states = [];
    if (plan.shouldSyncWebDavCollectibles) {
      states.add(webDavSynced ? 'WebDav 已同步' : 'WebDav 未完成');
    }
    if (plan.shouldSyncBangumi) {
      states.add(bangumiSynced ? 'Bangumi 已同步' : 'Bangumi 未完成');
    }
    if (plan.shouldSyncWebDavCollectibles &&
        plan.shouldSyncBangumi &&
        webDavSynced &&
        bangumiSynced) {
      states.add(webDavUploaded ? 'WebDav 已回传最新数据' : 'WebDav 未回传最新数据');
    }
    return states.join('，');
  }

  Future<void> _runFullSync({
    required CollectSyncPlan plan,
  }) async {
    final progressDialogKey = GlobalKey<_FullSyncProgressDialogState>();

    _showFullSyncProgressDialog(
      progressDialogKey: progressDialogKey,
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));

    bool webDavSynced = false;
    bool bangumiSynced = false;
    bool webDavUploaded = false;

    try {
      if (plan.shouldSyncWebDavCollectibles) {
        progressDialogKey.currentState?.update('正在同步 WebDav 收藏...', null);
        webDavSynced =
            await collectController.syncCollectibles(showSuccessToast: false);
      }

      if (plan.shouldSyncBangumi) {
        bangumiSynced = await _syncBangumiWithProgress(
          progressDialogKey: progressDialogKey,
        );
      }

      if (plan.shouldUploadWebDavAfterBangumi(
        webDavSynced: webDavSynced,
        bangumiSynced: bangumiSynced,
      )) {
        progressDialogKey.currentState?.update('正在回传最新收藏到 WebDav...', null);
        webDavUploaded = await collectController.uploadCollectiblesToWebDav(
          showSuccessToast: false,
        );
      }
    } finally {
      if (KazumiDialog.observer.hasKazumiDialog) {
        KazumiDialog.dismiss();
      }
    }

    KazumiDialog.showToast(
      message: _buildFullSyncSummary(
        plan: plan,
        webDavSynced: webDavSynced,
        bangumiSynced: bangumiSynced,
        webDavUploaded: webDavUploaded,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    collectController.loadCollectibles();
    tabController = TabController(vsync: this, length: tabs.length);
  }

  @override
  void dispose() {
    tabController?.dispose();
    super.dispose();
  }

  final List<Tab> tabs = const <Tab>[
    Tab(text: '在看'),
    Tab(text: '想看'),
    Tab(text: '搁置'),
    Tab(text: '看过'),
    Tab(text: '抛弃'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        needTopOffset: false,
        toolbarHeight: 104,
        bottom: TabBar(
          controller: tabController,
          tabs: tabs,
          indicatorColor: Theme.of(context).colorScheme.primary,
        ),
        title: const Text('追番'),
        actions: [
          IconButton(
              onPressed: () {
                setState(() {
                  showDelete = !showDelete;
                });
              },
              icon: showDelete
                  ? const Icon(Icons.edit_outlined)
                  : const Icon(Icons.edit))
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          bool webDavenable =
              await GStorage.getSetting(SettingsKeys.webDavEnable);
          bool webDavCollectEnable =
              GStorage.getSetting(SettingsKeys.webDavEnableCollect);
          bool bgmSyncEnable =
              GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
          final syncPlan = CollectSyncPlan(
            webDavEnabled: webDavenable,
            webDavCollectiblesEnabled: webDavCollectEnable,
            bangumiEnabled: bgmSyncEnable,
          );
          if (!syncPlan.canSync) {
            KazumiDialog.showToast(message: '同步功能不可用，请至少开启一个同步功能');
            return;
          }
          if (showDelete) {
            KazumiDialog.showToast(message: '编辑模式无法执行同步');
            return;
          }
          if (syncCollectiblesing) {
            return;
          }
          setState(() {
            syncCollectiblesing = true;
          });
          try {
            await _runFullSync(
              plan: syncPlan,
            );
          } finally {
            if (mounted) {
              setState(() {
                syncCollectiblesing = false;
              });
            }
          }
        },
        child: syncCollectiblesing
            ? const SizedBox(
                width: 32, height: 32, child: CircularProgressIndicator())
            : const Icon(Icons.sync_rounded),
      ),
      body: Observer(builder: (context) {
        return renderBody;
      }),
    );
  }

  Widget get renderBody {
    if (collectController.collectibles.isNotEmpty) {
      return TabBarView(
        controller: tabController,
        children: contentGrid(collectController.collectibles),
      );
    } else {
      return const Center(
        child: GeneralEmptyState(
          icon: Icons.favorite_border_rounded,
          title: '暂无追番内容',
        ),
      );
    }
  }

  List<Widget> contentGrid(List<CollectedBangumi> collectedBangumiList) {
    final bool showAnimeCounter =
        GStorage.getSetting(SettingsKeys.showAnimeCounter);
    // 本地可用角标：按 Bangumi subject ID 汇总媒体库文件数与缓存集数。
    // 用文件级口径（与详情页 / 搜索页一致），文件夹级整目录计数在
    // 混合目录单文件改匹配时会虚报。
    final mediaController = inject<MediaController>();
    final downloadController = inject<DownloadController>();
    final localCounts = mediaController.fileCountsByBangumi();
    final cacheCounts = <int, int>{};
    for (final record in downloadController.records) {
      final completed = record.episodes.values
          .where((e) => e.status == DownloadStatus.completed)
          .length;
      if (completed > 0) {
        cacheCounts[record.bangumiId] =
            (cacheCounts[record.bangumiId] ?? 0) + completed;
      }
    }
    List<Widget> gridViewList = [];
    List<List<CollectedBangumi>> collectedBangumiRenderItemList =
        List.generate(tabs.length, (_) => <CollectedBangumi>[]);
    for (CollectedBangumi element in collectedBangumiList) {
      collectedBangumiRenderItemList[element.type - 1].add(element);
    }
    for (List<CollectedBangumi> list in collectedBangumiRenderItemList) {
      list.sort((a, b) => b.time.millisecondsSinceEpoch
          .compareTo(a.time.millisecondsSinceEpoch));
    }
    int crossCount = 3;
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.compact['width']!) {
      crossCount = 5;
    }
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.medium['width']!) {
      crossCount = 6;
    }
    for (List<CollectedBangumi> collectedBangumiRenderItem
        in collectedBangumiRenderItemList) {
      gridViewList.add(
        CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(StyleString.cardSpace,
                  StyleString.cardSpace, StyleString.cardSpace, 0),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  mainAxisSpacing: StyleString.cardSpace - 2,
                  crossAxisSpacing: StyleString.cardSpace,
                  crossAxisCount: crossCount,
                  mainAxisExtent:
                      MediaQuery.of(context).size.width / crossCount / 0.65 +
                          MediaQuery.textScalerOf(context).scale(32.0),
                ),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                    return collectedBangumiRenderItem.isNotEmpty
                        ? _CollectGridCard(
                            item: collectedBangumiRenderItem[index],
                            showDelete: showDelete,
                            localCount: localCounts[
                                    collectedBangumiRenderItem[index]
                                        .bangumiItem
                                        .id] ??
                                0,
                            cacheCount: cacheCounts[
                                    collectedBangumiRenderItem[index]
                                        .bangumiItem
                                        .id] ??
                                0,
                          )
                        : null;
                  },
                  childCount: collectedBangumiRenderItem.isNotEmpty
                      ? collectedBangumiRenderItem.length
                      : 10,
                ),
              ),
            ),
            if (collectedBangumiRenderItem.isNotEmpty && showAnimeCounter)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 12),
                      child: Text(
                        '总计：${collectedBangumiRenderItem.length}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return gridViewList;
  }
}

class _FullSyncProgressDialog extends StatefulWidget {
  const _FullSyncProgressDialog({super.key});

  @override
  State<_FullSyncProgressDialog> createState() =>
      _FullSyncProgressDialogState();
}

class _FullSyncProgressDialogState extends State<_FullSyncProgressDialog> {
  String _progressText = '准备开始同步收藏...';
  double? _progressValue;

  void update(String text, double? value) {
    if (!mounted) return;
    setState(() {
      _progressText = text;
      _progressValue = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '收藏全量同步中',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(_progressText),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _progressValue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ׷������Ƭ��BangumiCardV + ���½Ǳ༭��ť + ���ϽǱ��ؿ��ýǱꡣ
class _CollectGridCard extends StatelessWidget {
  const _CollectGridCard({
    required this.item,
    required this.showDelete,
    required this.localCount,
    required this.cacheCount,
  });

  final CollectedBangumi item;
  final bool showDelete;
  final int localCount;
  final int cacheCount;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];
    if (localCount > 0) {
      badges.add(_AvailabilityBadge(
        text: '����$localCount',
        color: Theme.of(context).colorScheme.primary,
        foreground: Theme.of(context).colorScheme.onPrimary,
      ));
    }
    if (cacheCount > 0) {
      badges.add(_AvailabilityBadge(
        text: '����$cacheCount',
        color: Theme.of(context).colorScheme.tertiary,
        foreground: Theme.of(context).colorScheme.onTertiary,
      ));
    }
    return Stack(
      children: [
        BangumiCardV(
          bangumiItem: item.bangumiItem,
          canTap: !showDelete,
        ),
        if (badges.isNotEmpty)
          Positioned(
            left: 5,
            top: 5,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: badges,
            ),
          ),
        Positioned(
          right: 5,
          bottom: 5,
          child: showDelete
              ? Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: CollectButton(
                    bangumiItem: item.bangumiItem,
                    color:
                        Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                )
              : Container(),
        ),
      ],
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({
    required this.text,
    required this.color,
    required this.foreground,
  });

  final String text;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
      ),
    );
  }
}
