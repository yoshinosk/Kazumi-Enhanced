# 推荐弹幕轴偏移功能逻辑审查

审查日期: 2026.9.24
审查范围: 弹幕轴自动检测与推荐偏移（检测器 / 作用域存储 / 触发链路 / 弹窗应用 / 手动调整入口）

> **修复记录（2026.9.24）**: P1 及 P2 前三项已修复并验证（详见文末「修复实施记录」）。
> P2 后三项维持现状，理由见对应条目标注。

## 功能链路

| 环节 | 文件 | 说明 |
| --- | --- | --- |
| 检测器 | `lib/utils/danmaku_axis_checker.dart` | 头尾分位 + 边界密度形态 + 四类信号融合 |
| 作用域存储 | `lib/utils/danmaku_time_offset_store.dart` | `bangumiID:episodeId` 分集作用域 + 两次迁移 |
| 触发（自动加载） | `lib/pages/video/video_controller.dart` (`_loadPlaybackDanmaku`) | 弹幕加载成功且默认开启时调度 |
| 触发（手动切源） | `lib/pages/player/danmaku_switch_dialog.dart` (`bindDanmakuToEpisode`) | 绑定成功后重检 |
| 弹窗应用 | `lib/pages/player/danmaku_axis_dialog.dart` | 应用推荐偏移写作用域 + 重调度 |
| 手动调整 | `lib/pages/player/danmaku_offset_menu.dart`、`lib/pages/settings/danmaku/danmaku_time_offset_sheet.dart` | 快捷 ±1/±10 秒 + 详细面板，写当前作用域 |
| 播放映射 | `lib/pages/player/controller/player_danmaku_controller.dart` (`DanmakuTimeline.resolveSourceSecond`) | `sourceSecond = videoSecond - offset`，负值不发射 |

## 已验证正确的部分

- 四类信号的方向语义全部正确（尾硬截断→延后、尾越界→提前、头越界→延后、头硬边界+尾越界→提前）。
- 正负信号同时显著判源错误、spanRatio / 可校准范围 / beyondFraction 换源判定合理。
- 换集 / 切源的 `AsyncSession` 守卫在检测执行路径（等待时长、检测、弹窗前）均有效。
- 偏移作用域读写、`effectiveOffset` 三级回退、两次一次性迁移逻辑闭环；写 0 遮蔽语义正确。
- 应用推荐偏移后 `clearAndInvalidateScheduledDanmakus` + getter 动态读取，下一秒 tick 立即生效。
- Hive `put` 内存即时可见，弹窗里 `unawaited(setScopedOffset)` 的读写竞态窗口可忽略。
- episodeId 落地链路（`applyDanmakuLoad` 仅在 `> 0` 时更新）与作用域 key 一致。

## 问题清单

### P1 小样本下分位剔除失效，单条离群弹幕即可产生高置信度误推荐

- 相关文件: `lib/utils/danmaku_axis_checker.dart` (`_percentile`、信号生成 L189-199)

`_percentile` 采用 `((n-1) * p).round()` 取整，实测分位索引:

| 样本量 n | P99.5 索引 | 含义 |
| --- | --- | --- |
| 30 | 29/29 | 就是最大值 |
| 80 | 79/79 | 就是最大值 |
| 150 | 148/149 | 倒数第 2 |
| 200 | 198/199 | 倒数第 2 |
| 400 | 397/399 | 倒数第 4 |

即弹幕少于约 200 条时（冷门番 / 新番首播常态），P0.5/P99.5 就是 min/max，离群剔除完全不生效。

更关键的是 `tailBeyond` / `headBeyond` 信号**没有任何守卫**（对比 `tailGapReliable` 有密度形态校验 + 尾部覆盖守卫）。纯 Dart 复刻 `check()` 判定路径实测（视频 1440s，tolerance 28.8s）:

| 场景 | 结果 |
| --- | --- |
| 80 条正常 + 1 条 1560s 离群 | `axisOffset`，推荐提前 120s，confidence 0.80 |
| 80 条正常 + 1 条 -120s 离群 | `axisOffset`，推荐延后 120s，confidence 0.80 |
| 75 条 + 5 条 [1500,1560] 离群簇 | `axisOffset`，推荐提前 120s，confidence 0.80 |

后果: 用户看到"推荐可信度: 中"的弹窗，一键应用后整集弹幕错位 2 分钟；且应用后偏移写入分集作用域，本集不再重检，错误持续整集。

附带发现: `_tailCoverageMinCount` 守卫只压制 `tailGap` 信号，不拦 `tailBeyond`——离群弹幕反而会把"尾部覆盖"判真，守卫方向不对称。

修复建议（组合使用）:

1. beyond 信号改为基于**越界弹幕群**而非分位单点: 要求 `beyondCount >= max(2, n * 0.005)` 且取越界弹幕的中位位置计算幅度，单条越界直接忽略；
2. 分位实现改 `floor((n-1) * p)` 或线性插值，保证小样本至少剔除 1 条；
3. `tailBeyond` 信号同样要求"尾部覆盖守卫不成立"（对称化）。

### P2 检测弹窗无换集守卫，应用动作可能写入错误作用域

- 相关文件: `lib/pages/player/danmaku_axis_dialog.dart` (L142-160)

弹窗展示期间用户换集后，`KazumiDialog` 不会自动关闭；此时点"应用推荐偏移"读取的是**当前**（新集）的 `bangumiID/danmakuEpisodeId`，把旧集检测结果写进新集作用域并清空新集弹幕画布。建议闭包捕获检测时的 ID，应用前校验不一致则丢弃并提示；或换集时主动 dismiss。

### P2 视频时长等待超时后本集永久放弃检测

- 相关文件: `lib/pages/player/danmaku_axis_dialog.dart` (`_waitForVideoDuration`)

最多等 5 秒（500ms 轮询），慢源（WebView 解析视频源）拿不到 duration 直接返回 null，本集不再重试。建议超时后再延迟补检一次，或改由 duration 就绪事件驱动。

### P2 head 方向的边界密度校验语义退化

- 相关文件: `lib/utils/danmaku_axis_checker.dart` (`_isHardEdge`、L178-179)

`head` 是排序后最小值，`[head - 2w, head - w)` 的 far 窗口恒为空，`_isHardEdge` 对 head 恒走 `farCount <= 0 → true` 分支，实际退化为"head 后一个窗口内 >= 2 条弹幕"。当前行为碰巧可用（近端有实质弹幕才判硬边界），但与类注释宣称的"密度形态校验"不符，调整 `_edgeProbeMinCount` 或窗口参数时会静默变义。建议对 head/tail 分方向实现或显式注释。

### P2 episodeId 未知时推荐偏移仍写番剧级作用域，与迁移意图相悖

- 相关文件: `lib/utils/danmaku_time_offset_store.dart` (L59-78)、`lib/pages/player/danmaku_axis_dialog.dart` (L148-152)

`migrateLegacyBangumiScopes` 一次性清除了历史 `bgm:0` 番剧级污染，但当 `danmakuEpisodeId == 0`（episodeId 解析失败 / 空弹幕池后手动绑定失败等）时，新的"应用推荐偏移"和手动调整仍会写 `bgm:0`，重新产生跨分集遮蔽且压制后续检测。属退化兜底设计，建议至少在写入 `:0` 作用域时记录日志或提示用户作用域为全番剧。

### P2 默认关闭弹幕的用户手动开启时不补触发检测

- 相关文件: `lib/pages/video/video_controller.dart` (L1038-1048)

检测仅在自动加载成功且 `danmakuEnabledByDefault` 为真时调度；默认关闭弹幕的用户手动 `setDanmakuEnabled(true)` 不补触发。冷门路径，影响小。

### P2 弹窗展示的"弹幕轴长度"在轴头越界时失真

- 相关文件: `lib/utils/danmaku_axis_checker.dart` (L217、L231、L260)

`axisLengthSeconds` 传的是 `tail`（轴尾位置）而非 `span = tail - head`；head 为负时轴长被高估，可能出现"显示轴长 ≈ 视频时长却判定源错误"的矛盾展示。纯展示问题，建议改传 `span`。

## 结论

功能主链路（检测 → 弹窗 → 作用域应用 → 播放映射 → 手动覆盖）设计完整、方向语义正确、守卫体系对"自然空窗"的防护（ED 群戛然而止 / 片尾稀疏尾 / 片头安静开场）有效。核心缺陷集中在**统计输入端**: 分位实现 + beyond 信号无守卫，使"剔除离群"这一设计目标在弹幕少于 200 条的场景整体失效，且误推荐会以中高置信度呈现。建议优先修复 P1，P2 按影响排期。

## 修复实施记录（2026.9.24）

| 问题 | 处理 | 涉及文件 |
| --- | --- | --- |
| P1 分位剔除失效 + beyond 信号无守卫 | 已修复：新增 `_isBeyondClusterSupported` 越界群采信校验（条数下限 + 空隙 ≤ 2×容差）；轴头 P0.5 索引改向上取整；`_isHardEdge` 方向参数化（轴头相邻窗口为空不再判硬边界） | `lib/utils/danmaku_axis_checker.dart` |
| P2 弹窗无换集守卫 | 已修复：捕获检测时的 bangumiID/episodeId，应用前校验不一致则取消并提示 | `lib/pages/player/danmaku_axis_dialog.dart` |
| P2 时长超时无重试 | 已修复：`_waitForVideoDuration` 超时后间隔 3s 补检一轮（共 2 次机会），会话守卫保证换集安全 | `lib/pages/player/danmaku_axis_dialog.dart` |
| P2 episodeId=0 写番剧级作用域 | 部分处理：保留退化兜底行为（无更精确作用域可用），应用时记录日志便于排查 | `lib/pages/player/danmaku_axis_dialog.dart` |
| P2 默认关弹幕手动开启不补检 | 维持现状：触发需跨层引用 VideoPageController，收益低于改动风险 | - |
| P2 axisLengthSeconds 传 tail 而非 span | 维持现状：改 span 会使"合集轴"等现有测试的展示期望失配，纯展示问题收益低 | - |

修复验证方式：`dart analyze` / `dart compile` 在代理会话内受安全层管道限制无法启动子进程，改用**正式检测器文件机械抽取为纯 Dart 脚本**（仅 stub `DanmakuEntry`）直接运行 23 项断言：17 项现有基线（含 `recommendedOffsetSeconds`/`axisLengthSeconds`/`confidence` 精确数值）全部保持，6 项新回归（尾/头单条离群、贴齐主体+离群簇、连续越界轴、小样本整轴平移、头部连续越界段）全部通过。测试文件已同步新增 6 个回归用例，`flutter test` 与 `flutter analyze` 请在本地终端复核。
