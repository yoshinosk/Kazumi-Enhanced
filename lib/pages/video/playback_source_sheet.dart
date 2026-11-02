import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:kazumi/bean/widget/split_list_row.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/info/source_sheet.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

/// 「来源与详情」面板的后续动作。
///
/// 面板只负责收集用户的选择并关闭自己，真正的路由跳转交给播放页：换源要
/// 替换播放页本身，不能由面板直接 push（否则返回栈里会留下已失效的播放页）。
sealed class PlaybackSourceAction {
  const PlaybackSourceAction();
}

/// 用户挑了另一个来源，需要用新参数重新进入播放页。
class PlaybackSourceSwitch extends PlaybackSourceAction {
  const PlaybackSourceSwitch(this.args);

  final VideoPlaybackArgs args;
}

/// 用户要去看番剧详情。
class PlaybackSourceOpenInfo extends PlaybackSourceAction {
  const PlaybackSourceOpenInfo();
}

/// 打开播放页的「来源与详情」面板。
///
/// 历史记录等入口进入播放页后，播放页原本没有回到番剧详情或更换播放源的
/// 入口；来源失效时只能退回列表重新找到该番剧。本面板补上这两个出口。
Future<PlaybackSourceAction?> showPlaybackSourceSheet(
  BuildContext context, {
  required VideoPageController videoPageController,
}) {
  return showAdaptiveBottomSheet<PlaybackSourceAction>(
    context: context,
    maxHeightFactor: 0.8,
    builder: (_) =>
        PlaybackSourceSheet(videoPageController: videoPageController),
  );
}

class PlaybackSourceSheet extends StatefulWidget {
  const PlaybackSourceSheet({super.key, required this.videoPageController});

  final VideoPageController videoPageController;

  @override
  State<PlaybackSourceSheet> createState() => _PlaybackSourceSheetState();
}

class _PlaybackSourceSheetState extends State<PlaybackSourceSheet> {
  /// 换源面板复用详情页的 [SourceSheet]。它只读取检索结果与番剧信息，
  /// 因此单独建一份 [InfoController]，不碰详情页路由作用域里的实例。
  InfoController? _sourceInfoController;

  BangumiItem get _bangumiItem => widget.videoPageController.bangumiItem;

  String get _title {
    final item = _bangumiItem;
    return item.nameCn.isEmpty ? item.name : item.nameCn;
  }

  InfoController _ensureSourceInfoController() {
    final existing = _sourceInfoController;
    if (existing != null) return existing;
    final controller = InfoController(inject<CollectController>());
    controller.bangumiItem = _bangumiItem;
    _sourceInfoController = controller;
    return controller;
  }

  void _close([PlaybackSourceAction? action]) {
    Navigator.of(context).pop(action);
  }

  /// 打开与详情页「开始观看」相同的来源检索面板；选中结果后关闭两层
  /// 面板，把新的播放参数交回播放页。
  Future<void> _openSourceList() async {
    final pluginsController = inject<PluginsController>();
    if (pluginsController.pluginList.isEmpty) {
      KazumiDialog.showToast(
        message: '还没有播放规则，无法检索在线来源',
        showActionButton: true,
        actionLabel: '添加规则',
        onActionPressed: _openPluginSettings,
        duration: const Duration(seconds: 4),
      );
      return;
    }
    final selected = await showAdaptiveBottomSheet<PlaybackSourceAction>(
      context: context,
      maxHeightFactor: 0.88,
      builder: (_) => SourceSheet(
        infoController: _ensureSourceInfoController(),
        onPlaySelected: (args) => _close(PlaybackSourceSwitch(args)),
      ),
    );
    if (!mounted || selected == null) return;
    _close(selected);
  }

  void _openPluginSettings() {
    _close();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.pushNamed('/settings/plugin/');
    });
  }

  @override
  Widget build(BuildContext context) {
    final sourceLabel = widget.videoPageController.playbackSourceLabel;
    // 不用 Scaffold：面板内容不多，让 Column 按内容收缩，避免撑满整块
    // 面板高度、底下留一片空白。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MaterialBottomSheetHeader(
          title: '来源与详情',
          description: '$_title · 当前来源：$sourceLabel',
          compact: true,
          onClose: _close,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SplitListRow(
                  topRadius: splitListOuterRadius,
                  bottomRadius: splitListInnerRadius,
                  onTap: _openSourceList,
                  child: ListTile(
                    leading: const Icon(Icons.swap_horiz_rounded),
                    title: const Text('切换播放来源'),
                    subtitle: const Text('重新检索播放规则，换个来源继续看'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
                const SizedBox(height: splitListRowGap),
                SplitListRow(
                  topRadius: splitListInnerRadius,
                  bottomRadius: splitListOuterRadius,
                  onTap: () => _close(const PlaybackSourceOpenInfo()),
                  child: const ListTile(
                    leading: Icon(Icons.info_outline_rounded),
                    title: Text('番剧详情'),
                    subtitle: Text('简介、评分、收藏与评论'),
                    trailing: Icon(Icons.chevron_right_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SafeArea(top: false, child: SizedBox(height: 16)),
      ],
    );
  }
}
