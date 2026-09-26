# 音量滑块浮层（Volume Slider Card）问题审查

- 审查日期: 2026.9.26
- 审查对象: 桌面端 hover 音量图标弹出的竖向音量滑块浮层（第三批交互打磨 P1#5 引入，commit `3370862`）
- 结论: 1 个 P1 交互缺陷 + 1 个 P2 视觉缺陷 + 2 个 P3 细节问题

## 涉及代码

| 文件 | 位置 | 职责 |
| --- | --- | --- |
| lib/pages/player/player_item_panel.dart | L109-171 | 浮层 OverlayEntry 的显示/延迟隐藏/联动移除 |
| lib/pages/player/player_item_panel.dart | L1060-1088 | 底栏音量按钮 `CompositedTransformTarget` + hover MouseRegion |
| lib/pages/player/player_item_panel.dart | L1460-1525 | `_VolumeSliderCard` 浮层本体（RotatedBox 竖向 Slider） |
| lib/pages/player/player_item_panel.dart | L345-359 | 底栏隐藏时同步移除浮层的 reaction |
| lib/pages/player/player_item.dart | L983-1021 | 面板 hold 租约机制（`acquirePlayerPanelHold`） |
| lib/pages/player/player_item.dart | L1103-1117 | 控制层自动隐藏计时器（默认 4000ms，可在设置中调整） |
| lib/pages/player/player_panel_hold.dart | L71-119 | `PlayerPanelHoldMouseRegion`（悬停底栏 = 持有 hold） |

## 问题清单

### P1 — 浮层未持有面板 hold，悬停/拖动中控制层会连人带浮层一起消失（甚至闪烁循环）

**复现路径**: hover 音量按钮弹出浮层 → 鼠标移入浮层（停止 4 秒）→ 控制层与浮层同时消失。

**根因链路**:

1. 鼠标 hover 底栏 → 底栏级 `PlayerPanelHoldMouseRegion` acquire hold → 面板保持显示；
2. 鼠标从按钮移向浮层 → 离开底栏 MouseRegion → `onExit` release hold → `_startHideTimer()` 启动 4 秒倒计时（设置项 `playerControllerLayerDisappearTime` 可调更短）；
3. 浮层通过 `OverlayEntry` 插在全局 Overlay 顶层，**不在底栏 MouseRegion 内，也没有任何代码为它 acquire hold**；浮层物理上还遮住了播放器画面，鼠标移动事件不会重置隐藏倒计时；
4. 倒计时到期 → `hideVideoController()` → `panel.showVideoController = false` → reaction（panel L345-359）移除浮层；
5. 浮层消失后鼠标下方重新露出底栏 → 再次 hover → 面板与浮层再次出现 → 用户还在原位就会形成"弹出-消失"闪烁循环。

用户正要读数字、准备拖动、或拖动间隙松手的瞬间，整个控制层连同滑块一起消失，是最直观的"界面有问题"。

**修复方向**（对齐现有 `PlayerPanelHoldMenuAnchor` 的租约模式）:

```dart
// _PlayerItemPanelState 新增字段
PlayerPanelHold? _volumeOverlayHold;

void _showVolumeOverlay() {
  if (!_desktop || _volumeOverlayEntry != null) return;
  _cancelVolumeOverlayHide();
  _volumeOverlayHold ??= widget.acquirePlayerPanelHold(); // 浮层存续期间持有 hold
  // ...原 OverlayEntry 逻辑不变
}

void _hideVolumeOverlay() {
  _volumeOverlayEntry?.remove();
  _volumeOverlayEntry = null;
  _volumeOverlayHold?.release(); // 释放后由 onRelease 走常规隐藏计时
  _volumeOverlayHold = null;
}

@override
void dispose() {
  _volumeOverlayVisibilityReaction?.call();
  _volumeOverlayHideTimer?.cancel();
  _volumeOverlayEntry?.remove();
  _volumeOverlayHold?.releaseSilently(); // dispose 中静默释放，避免回调里再起新 timer
  // ...
}
```

注意: `acquirePlayerPanelHold()` 内部会 `showVideoController(restartHideTimer: false)`，语义正确（浮层弹出即保持面板）；释放 hold 后 `onRelease` 会重新 `_startHideTimer()`，鼠标不在底栏时 4 秒后正常隐藏，行为与菜单锚点一致。

### P2 — 浮层配色跟随 App 主题，浅色主题下白字浅底不可读，且与播放器暗色 UI 脱节

**根因**: `_VolumeSliderCard`（panel L1470-1487）背景用 `colorScheme.surfaceContainerHighest.withValues(alpha: 0.96)`、边框用 `colorScheme.outlineVariant`，但音量数字写死 `Colors.white`（L1498）。播放器面板其余部分全部是手动 `Colors.white` 文字 + 黑色 scrim（自绘暗色，不依赖 Theme），而 App 支持浅色/深色/跟随系统（lib/app_widget.dart L124-127）。浅色主题下 `surfaceContainerHighest` 接近 `#E6E0E9`，白字对比度约 1.6:1，**音量数字几乎不可见**；Slider 的轨道/thumb 颜色也会跟着浅色主题走，风格突兀。

**修复方向**: 播放器内浮层统一固定暗色，与进度条悬停时间气泡 `_ProgressHoverPreview`（L1577 `Colors.black.withValues(alpha: 0.85)`）保持一致:

```dart
decoration: BoxDecoration(
  color: Colors.black.withValues(alpha: 0.85),
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: Colors.white.withValues(alpha: 0.12)), // 或去掉边框
  boxShadow: [ /* 原阴影保留 */ ],
),
```

可选: 用 `SliderTheme` 固定 activeColor/inactiveTrackColor，避免主题色干扰（P3 级，可顺手）。

### P3 — 按钮与浮层之间 8px 空隙会让浮层提前进入隐藏倒计时

浮层 anchor 为 `followerAnchor: bottomCenter` + `offset: Offset(0, -8)`，按钮顶边到浮层 hover 区之间有 8px 空隙。鼠标穿过空隙时浮层 MouseRegion 尚未 `onEnter`，而 250ms 延迟隐藏已启动；鼠标移动稍慢就会出现"浮层闪一下"。P1 修复后浮层生命周期由 hold 保证，此问题降级为体验细节。

**修复方向**: 把 MouseRegion 包在卡片外侧并向下扩展 8px 命中区，视觉位置不变:

```dart
child: MouseRegion(
  onEnter: (_) => _cancelVolumeOverlayHide(),
  onExit: (_) => _scheduleVolumeOverlayHide(),
  child: Padding(
    padding: const EdgeInsets.only(bottom: 8), // 命中区覆盖空隙
    child: _VolumeSliderCard(playerController: playerController),
  ),
),
```

### P3 — 记录在案、暂不建议处理的两个小点

1. `PlayerPlaybackController.updateVolume`（controller L618-620）有 `volume.toInt() == value.toInt()` 的整数节流，拖动时数字按整数跳变；但 Slider 拖动中显示的是内部 drag 值，松手后 `finishVolumeGesture` 写回连续值，观感影响很小。
2. M3 Slider 的 thumb glow/overlay 绘制可超出自身 bounds，拖到 0/200 端点时辉光轻微溢出浮层圆角边缘，极不明显。

## 已排查、确认无问题的点

- RotatedBox(quarterTurns: 3) + SizedBox(height: 120) 的约束交换数学正确（Slider 收到 120 宽 tight × 高 [0,56]，旋转后 48×120，无溢出）；旋转方向正确（向上拖 = 增大），hit-test 逆变换由框架处理。
- `volume` 类型为 double，`value.clamp(0.0, 200.0)` 在 double 上下文有语言级 clamp 特化，无类型问题；桌面 0~200、移动端锁 100 的增益逻辑一致。
- compact（窄窗口）模式底栏 controls 为 `SizedBox.shrink()`，音量按钮不渲染，浮层无从触发；PIP 同理。
- dispose 顺序（reaction → timer → entry remove）无泄漏；底栏隐藏 reaction 联动有效。

## 验证建议

修复后（用户本地终端执行）:

1. `dart analyze lib test` 确认无新增告警；
2. Windows 本地构建 `tools/build_windows_local.ps1`；
3. 手动验证: 浅色 + 深色主题下 hover 音量按钮；鼠标停在浮层上超过设置的"控制层消失时间"（默认 4s），控制层与浮层应保持；移出浮层后按所设时间正常隐藏；拖动滑块全程无消失/闪烁；菜单（倍速/比例）与浮层行为一致。
