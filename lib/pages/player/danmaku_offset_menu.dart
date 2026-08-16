import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_time_offset_sheet.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 调整弹幕时间轴偏移并通知上层重新调度当前弹幕。
void adjustDanmakuTimeOffset(double offset, {VoidCallback? onChanged}) {
  final normalized = normalizeDanmakuTimeOffset(offset);
  GStorage.putSetting<double>(SettingsKeys.danmakuTimeOffset, normalized);
  onChanged?.call();
}

/// 播放界面上的弹幕时间轴快速调整菜单：
/// ±1 秒 / ±10 秒 / 恢复无偏移 / 详细调整。
class DanmakuOffsetMenu extends StatelessWidget {
  const DanmakuOffsetMenu({
    super.key,
    required this.onChanged,
    this.color = Colors.white,
    this.iconSize = 24,
  });

  /// 偏移变化后的回调（通常用于重新调度当前弹幕）。
  final VoidCallback onChanged;
  final Color color;
  final double iconSize;

  double get _current =>
      GStorage.getSetting<double>(SettingsKeys.danmakuTimeOffset);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = normalizeDanmakuTimeOffset(_current);
    return MenuAnchor(
      consumeOutsideTap: true,
      builder: (context, controller, child) => IconButton(
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
        color: color,
        iconSize: iconSize,
        icon: const Icon(Icons.timelapse_rounded),
        tooltip: '弹幕时间轴',
      ),
      menuChildren: [
        MenuItemButton(
          onPressed: null,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: Text(
              '弹幕时间轴：${formatDanmakuTimeOffset(normalized)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
        MenuItemButton(
          onPressed: () =>
              adjustDanmakuTimeOffset(_current - 10, onChanged: onChanged),
          child: _menuItem('提前 10 秒'),
        ),
        MenuItemButton(
          onPressed: () =>
              adjustDanmakuTimeOffset(_current - 1, onChanged: onChanged),
          child: _menuItem('提前 1 秒'),
        ),
        MenuItemButton(
          onPressed: () =>
              adjustDanmakuTimeOffset(_current + 1, onChanged: onChanged),
          child: _menuItem('延后 1 秒'),
        ),
        MenuItemButton(
          onPressed: () =>
              adjustDanmakuTimeOffset(_current + 10, onChanged: onChanged),
          child: _menuItem('延后 10 秒'),
        ),
        MenuItemButton(
          onPressed: normalized == 0
              ? null
              : () => adjustDanmakuTimeOffset(0, onChanged: onChanged),
          child: _menuItem('恢复无偏移'),
        ),
        MenuItemButton(
          onPressed: () {
            showAdaptiveBottomSheet<void>(
              context: context,
              builder: (context) => DanmakuTimeOffsetSheet(
                onTimelineOffsetChanged: onChanged,
              ),
            );
          },
          child: _menuItem('详细调整…'),
        ),
      ],
    );
  }

  Widget _menuItem(String label) {
    return Container(
      height: 48,
      constraints: const BoxConstraints(minWidth: 132),
      alignment: Alignment.centerLeft,
      child: Text(label),
    );
  }
}
