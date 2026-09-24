# 播放器工具栏优化与缺失功能分析报告

> 分析日期：2026.9.24 · 代码基线：当前工作区（无代码改动，纯分析）
> 范围：播放器控制栏（顶栏 / 底栏 / 右侧栏 / 更多菜单），对比 B 站、DanDanPlay、mpv/IINA/PotPlayer 等主流播放器的常用功能基线。

## 一、结论摘要

工具栏的弹幕能力（开关/偏移/样式/屏蔽/发送）已经相当完善，倍速、超分辨率、定时关闭、画中画、一起看、投屏等长尾功能也齐备。但对照主流播放器基线，存在 **6 项 P1 级功能缺失**（上一集按钮、音轨选择、字幕轨道选择、A-B 循环、桌面音量滑块、静音按钮）和若干 P2 级体验缺口。其中音轨/字幕轨道/A-B 循环三项，mpv 底层能力完备（media_kit 全部暴露），纯粹是 UI 入口缺失，实现成本低、收益高。

## 二、现状盘点（基于代码事实）

### 2.1 工具栏结构

| 区域 | 现有控件 | 代码位置 |
| --- | --- | --- |
| 顶栏 | 返回、标题(拖动区)、快进80s(长按改秒数)、画中画、弹幕开关(仅compact)、收藏、更多菜单 | `lib/pages/player/player_item_panel.dart` `_buildTopControls()` |
| 底栏(宽屏) | 播放/暂停、**下一集(无上一集)**、进度条+缓冲、时间、弹幕组(开关/偏移/设置/发送框)、超分辨率、倍速、视频比例、选集面板、全屏 | `player_item_panel.dart` `_wideControls` + `_buildBottomControls()` |
| 底栏(compact) | 播放/暂停、进度条、时间、全屏 | `player_transport_bar.dart` |
| 右侧栏(仅移动端) | 截图、锁定面板 | `player_item_panel.dart` `_rightControls` |
| 更多菜单 | 弹幕切换、视频详情、远程投屏(在线)、外部播放、定时关闭(含倒计时)、一起看；compact 下另有比例/倍速/超分辨率子菜单 | `_buildTopControls()` 尾部 MenuAnchor |

### 2.2 已具备的交互能力

- 快捷键 17 个动作可自定义（`lib/utils/constants.dart` `defaultShortcuts`）：空格/←→/N/P/↑↓/M/F/Esc/D/S/K/1/2/3/X/Z
- 手势（`player_item.dart` L1522-1700）：移动端横拖 seek(带方向HUD)、左半屏竖拖亮度/右半屏竖拖音量、长按临时倍速、双击播放暂停(移动)/全屏(桌面)、滚轮音量
- 设置项：自动连播、自动跳转、默认倍速、长按倍速、跳过时长、控制栏消失时间、默认视频比例、字幕样式等（`lib/pages/settings/player_settings.dart`）

## 三、缺失功能清单（功能部分）

### P1 —— 高价值缺失，建议优先补齐

| # | 功能 | 现状与依据 | 实现要点 | 难度 |
| --- | --- | --- | --- | --- |
| 1 | **上一集按钮** | 底栏只有"下一集"（`_wideControls` 中仅 `nextEpisode`）；上一集逻辑已存在（`player_item.dart` `handlePreNextEpisode('prev')`，快捷键 P、媒体通知栏均可用），**纯粹缺 UI 按钮** | 在 `PlayerTransportBar` 增加 `prevEpisode` 槽位，`skip_previous_rounded` 图标 | 极低 |
| 2 | **音轨选择** | 初始化仅 `setAudioTrack(AudioTrack.auto())`（`player_playback_controller.dart` L384）；全库无音轨切换 UI。多音轨视频（日/国语、评论音轨）无法切换 | media_kit 提供 `player.state.tracks` / `stream.tracks` / `setAudioTrack()`；在更多菜单加"音轨"子菜单，样式复用 `_choiceItems` | 低 |
| 3 | **字幕轨道选择 + 字幕延迟** | 本地播放 `sub-auto fuzzy` 自动加载外挂字幕后无入口切换简繁/英字；弹幕有时间轴偏移而字幕没有（`sub-delay`） | 同上用 `setSubtitleTrack()`；延迟用 `pp.setProperty('sub-delay', ...)`,入口与弹幕偏移菜单(`danmaku_offset_menu.dart`)对齐 | 低 |
| 4 | **A-B 循环** | 全库无 `ab-loop` 相关代码。学语言、循环 OP/ED、卡点复读场景刚需 | mpv 原生 `ab-loop-a/b/clear`,需在进度条/更多菜单给入口 + 状态指示 | 低 |
| 5 | **桌面音量滑块 UI** | 桌面只有滚轮/↑↓ + HUD 气泡（`PlayerAdjustmentHud`），无可拖动音量条；B 站/IINA 均为悬停音量图标弹出竖向滑块 | 悬停音量图标(新增)或悬停底栏音量区弹出滑块，复用 `playback.setVolume` | 中 |
| 6 | **静音按钮** | 静音逻辑完备（`player_controller.dart` `toggleMute`，含持久化），但 UI 无按钮，HUD 也不反映静音态，移动端无法静音 | 音量图标叠加静音态（`Icons.volume_off`），点击切换；HUD 显示状态 | 低 |

### P2 —— 体验增强，按需排期

| # | 功能 | 现状与依据 | 实现要点 | 难度 |
| --- | --- | --- | --- | --- |
| 7 | 倍速自定义输入 | 仅 13 档预设（0.25~3.0，`defaultPlaySpeedList`），无任意倍速；"跳过秒数"已有数字输入弹窗先例（`_showForwardChange`） | 倍速子菜单尾部加"自定义"，复用弹窗模式 | 极低 |
| 8 | 进度条悬停时间气泡 | `audio_video_progress_bar` 仅拖动时显示时间标签（`onDragUpdate`），桌面 hover 无预览 | 包一层 `MouseRegion` 换算时间为气泡 | 中 |
| 9 | 循环模式/播放器内连播开关 | 无单集循环；"自动连播"开关藏在设置页（`player_settings.dart` L363），换番剧时切换不便 | 更多菜单加"播完动作"（连播/单集循环/暂停）；mpv `loop-file` | 低 |
| 10 | 移动端双击左右屏 ±10s | 移动端双击=播放/暂停（`_handleDoubleTap`）；B 站/YouTube 移动端习惯是双击左屏退/右屏进 | 按点击坐标分左右触发 `seekBy`,建议做成可选设置兼容现有习惯 | 低 |
| 11 | 画面旋转 | 无 `video-rotate` 代码；竖拍视频横屏播放场景需要 | `pp.setProperty('video-rotate', '90/180/270')`,进视频比例子菜单 | 低 |
| 12 | 音量增益(volume-max) | Android 显式锁 100（`player_playback_controller.dart` L348）,Windows 为 mpv 默认 130；小音量源无法拉高 | 设置项放开到 200,音量 HUD 超过 100 变色提示 | 低 |
| 13 | 进度条缩略图预览 | 无 | mpv 无原生支持，需自行抽帧缓存，成本高 | 高(远期) |
| 14 | 章节标记 | 无 | 番剧场景价值有限 | 远期 |

## 四、界面与交互优化清单（界面部分）

| # | 优先级 | 问题 | 现状依据 | 建议 |
| --- | --- | --- | --- | --- |
| 15 | P1 | **快进按钮图标与实际秒数脱节** | 图标硬编码 `forward_80.png`（`_forwardButton`），长按改成 30/90 秒后 tooltip 变了、图标仍显示 80 | 用通用快进图标 + 动态秒数文字角标（`Stack` 实现），或动态生成 |
| 16 | P1 | **底栏无溢出收纳策略** | 宽屏 `_wideControls` 已含 5 组以上控件，再补 P1 功能（音轨/字幕/AB循环/上一集）必然溢出；超分辨率还是文字按钮占地且风格不统一 | 常驻只留高频项（上下集/倍速/音量/全屏），其余统一收进更多菜单；或提供可配置工具栏 |
| 17 | P2 | compact 模式顶栏标题完全消失 | `compact ? SizedBox(height:40) : Text(...)`（`_buildTopControls`），移动全屏看不到在放什么 | compact 时显示单行省略标题（小字号），或顶部中央 toast 提示 |
| 18 | P2 | 桌面全屏无截图/锁定入口 | `_rightControls` 仅 `!_desktop` 渲染（L451），桌面截图只能靠 S 键 | 桌面全屏时也显示右侧栏（hover 唤出） |
| 19 | P2 | 进度条拖动热区偏小 | `thumbRadius: 8` 固定（`_buildBottomControls`），鼠标精细操作不友好 | 桌面加大到 10~12 或外包透明热区 |
| 20 | P2 | 超分辨率/比例菜单无当前值指示 | 比例按钮是纯图标、无选中态反馈；超分辨率按钮无状态标记 | 按钮加当前值角标（如比例图标右下角显示"16:9"），菜单选中项已有高亮保持 |
| 21 | P3 | 倍速按钮状态展示不完整 | 仅在 ≠1x 时显示 `x` 后缀；调出菜单前不知道当前倍速的精确语义 | 可接受；若做 #16 工具栏重构时统一处理 |
| 22 | P3 | compact 判定阈值耦合字体缩放 | `constraints.maxWidth < textScaler.scale(600)` 已考虑字体缩放，边界情况（大字体+中宽屏）下按钮行仍可能挤压 | 引入溢出检测降级渲染（overflow 时自动把次要按钮收进菜单） |

## 五、建议实施路线

1. **第一批（低成本高收益，约半天~1天量级）**：#1 上一集按钮、#6 静音按钮、#7 自定义倍速、#15 快进图标动态化 —— 全部为纯 UI 改动，无底层风险。
2. **第二批（播放能力补全）**：#2 音轨选择、#3 字幕轨道 + 字幕延迟、#4 A-B 循环、#9 循环模式 —— 依赖 media_kit tracks 流与 mpv 属性，需要处理"轨道动态变化/无轨道"的空态。
3. **第三批（交互打磨）**：#5 桌面音量滑块、#8 进度条悬停气泡、#10 双击快进(做成可选项)、#16 工具栏收纳重构 —— 建议与 #16 一并设计，避免底栏反复改版。
4. **远期**：#13 缩略图预览、#14 章节标记。

## 六、风险与注意事项

- 轨道类功能（#2/#3）需同步处理 SyncPlay「一起看」场景下的轨道同步语义（至少保证各自独立不互相干扰）。
- 移动端双击语义变更（#10）必须做成设置项默认关闭，避免破坏既有用户肌肉记忆。
- 底栏重构（#16）注意 compact/非 compact 双布局与 `PlayerTimeLabelPlacement` 三种时间标签位置的兼容。
- 依据 `AGENTS.md`：以上涉及改动时仅保证 Android/Windows；改动后需 `dart analyze lib test`（本机代理会话限制见项目记忆）+ 本地 `flutter test` + `tools/build_windows_local.ps1` 构建验证，并更新 CHANGELOG。
