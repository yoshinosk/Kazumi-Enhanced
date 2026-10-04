# 上游功能同步进度

- 基线:上游 `2.2.8`(640dfdcb)
- 目标:同步上游 `2.2.9` ~ `2.3.4` 的全部功能(批次 1~4 共 72 个提交 + 批次 5 共 28 个提交);批次 6 起为滚动同步
- 状态标记:⬜ 未开始 / 🔄 进行中 / ✅ 已完成 / ❌ 决定跳过(附原因)
- 每完成一项,在对应条目标记 ✅ 并注明日期

> **当前状态(2026.10.5)**:批次 1~6 已全部完成并合入 `dev`,上游功能同步至 **2.3.7**(目标 commit `02afdabf`,批次 6 完成于 2026.10.5);上游暂无更新的提交。
> - 工程构建于 Flutter 3.47.2(批次 5/6 连续跳过上游 3.47.3/3.47.5/3.47.6 SDK 升级,pubspec 保持 flutter pin 3.47.2、Dart 下限 ≥3.10.0);`dart analyze lib test` 为 0 error / 0 warning(41 条既有 info),`flutter test` 436 项全部通过。
> - 历史过程(批次 4 WIP 树 506 个编译错误修复、Flutter 3.47.2 升级、mobx 产物重生成、批次 5 冲突回植)见 CHANGELOG 2026.9.10 / 2026.9.13。
> - 批次 6 起 GitHub 直连恢复,辅助同步用 blobless clone(见批次 6 备注);fetch_upstream.py(api.github.com contents 接口)仍可用于单文件场景。
> - 注意:本机代理会话内 flutter 工具时通时不通(安全层拦截 flutter/dart 对 SDK 缓存文件的写打开);2026.10.5 批次 6 期间 flutter pub get / test / analyze 已可在会话内直跑,若再次挂死请退回 `dart analyze lib test` + 本机终端验证。

## 批次 1:低冲突功能

| 状态 | 上游提交 | 内容 | 完成日期 |
|---|---|---|---|
| ✅ | ac39437a | feat(plugin): 批量规则导入 | 2026.9.9 |
| ✅ | 030645a9 | fix(ui): 修复批量规则更新 toast 消失 | 2026.9.9 |
| ✅ | 5b5fd9a8 | feat(download): 下载页自动滚动到正在播放的集 | 2026.9.9 |
| ✅ | 49c19350 | fix: 禁用相关番剧卡片 hero 动画 | 2026.9.9 |
| ✅ | 281ee9cc | fix(android): PiP 入口重构 | 2026.9.9 |
| ✅ | 80af230b | fix(android): 媒体会话销毁后不再复现 | 2026.9.9 |
| ✅ | 84043d59 | fix(android): 应用后台时挂起 demuxer 预取 | 2026.9.9 |

验证: `flutter analyze` 无新增问题(21 个均为既有 info/warning),`flutter test` 364 项全部通过。

## 批次 2:中冲突功能

| 状态 | 上游提交 | 内容 | 完成日期 |
|---|---|---|---|
| ✅ | 6c3c46c9 | feat: 弹幕搜索 API v2 | 2026.9.9 |
| ✅ | c32db78c | fix(danmaku): 手动弹幕匹配使用搜索集数 | 2026.9.9 |
| ✅ | bd66ce55 | fix(danmaku): 修复存储时长编辑 | 2026.9.9 |
| ✅ | 5d1569b3 | feat(sync): Bangumi 收藏同步优化 | 2026.9.9 |
| ✅ | 22f9ee13 | feat(player): 网络感知低内存模式 | 2026.9.9 |
| ❌ | 43e0fe80 | ~~fix(windows): 检测到的 M3U 源强制 HLS demux~~（已在 2.2.8 基线内，无需同步） | - |
| ✅ | 50f83370 | fix: 仅自动展开第一个播放源（随 1eab03f3 源选择重设计一并接收） | 2026.9.10 |
| ✅ | a2fd8259 | fix(video): 选集网格中定位历史集数 | 2026.9.9 |
| ✅ | 3e86da15 | fix(player): 无效源错误提示改进 | 2026.9.9 |
| ✅ | 280a5adc | fix(player): 源失败 toast 移出错误 switch | 2026.9.9 |
| ✅ | 08905a38 | fix(player): 关闭播放线路菜单后恢复焦点（随 2.3.1 新选集面板接收） | 2026.9.10 |
| ✅ | 45201365 | feat(collect): 番剧计数从页脚移到标签页（随收藏库重设计接收） | 2026.9.10 |
| ✅ | d658832d | chore: 设置页文案优化 | 2026.9.9 |
| ✅ | 92e91e3d | fix(bangumi): 保留同步偏好并稳定连接状态 | 2026.9.9 |
| ✅ | 9b7d6458 | fix(info): 分离评论与播放操作（随 98e331c7 评论对话框重设计接收） | 2026.9.10 |
| ✅ | 495bf11a | fix(images): 统一角色立绘加载（随 character_info_view 接收） | 2026.9.10 |
| ✅ | 11b0cb76 | fix(history): 移除多余的卡片加载指示器（随 history 页重构接收） | 2026.9.10 |
| ✅ | 7d2d0d58 | fix(collect): 恢复封面 hero 转场（随 collect_library_* 接收） | 2026.9.10 |
| ✅ | e436ab76 | fix(collect): 修正滚动行为（同上） | 2026.9.10 |
| ✅ | 99562de8 | fix(timeline): 对齐卡片封面（随 02f4b307 时间线重设计接收） | 2026.9.10 |
| ✅ | edb7b526 | fix(timeline): 滚动时保持星期标签稳定（同上） | 2026.9.10 |
| ✅ | aeae76d9 | perf(history): 惰性渲染日期（随 history_list_view 接收） | 2026.9.10 |
| ✅ | 2c1dad2e | fix(search): 图片搜索滚动条对齐（随 a71dfa21 图片搜索重设计接收） | 2026.9.10 |
| ✅ | 879eb849 | fix(timeline): 合并排序与筛选控件（随 timeline_options 接收） | 2026.9.10 |
| ✅ | 22be2365 | fix(collect): 搜索栏随库内容滚动（同上） | 2026.9.10 |
| ✅ | d5784deb | fix(collect): 库滚动条对齐页面边缘（同上） | 2026.9.10 |
| ✅ | 23610a52 | fix(search): 防止结果卡片标题被裁剪（随 0aadad1e 搜索重设计接收） | 2026.9.10 |

## 批次 3:依赖升级

| 状态 | 上游提交 | 内容 | 完成日期 |
|---|---|---|---|
| ❌ | 2eefde98 | ~~deps: bump dio~~（已在 2.2.8 基线内） | - |
| ❌ | 145feb99 | ~~deps: bump media kit~~（本分支与上游 main 的 media-kit ref 一致 994465d，无需变更） | - |
| ✅ | 491482c1 / 794567ed | deps: bump canvas danmaku（^0.3.1 → ^0.3.3） | 2026.9.9 |
| ✅ | （补充） | deps: dio 约束提升至 ^5.11.0（与上游 main 对齐） | 2026.9.9 |
| ❌ | b018c6ca | ~~chore: bump 默认插件~~（已在 2.2.8 基线内） | - |
| ✅ | 2d13a412 / 0d6237ab | deps: Flutter 3.47.0 → 3.47.2（本机已安装 3.47.2 并以之重新 `pub get`；上游 pubspec 的 `environment.flutter` 已随批次 4 接收） | 2026.9.10 |
| ❌ | 76fc6ecf | ~~chore: 从 appBuildName 派生应用版本号~~（已在 2.2.8 基线内） | - |

## 批次 4:M3E UI 重构浪潮(整体接收 2.3.1 UI 后回移植本分支功能)

| 状态 | 上游提交 | 内容 | 完成日期 |
|---|---|---|---|
| ✅ | ba52a11c | refactor(ui): 统一表现力组件并移除旧代码 | 2026.9.10 |
| ✅ | 24690559 | feat(collect): 收藏库重设计 | 2026.9.10 |
| ✅ | 02f4b307 | feat(ui): 时间线重设计 + 收藏空状态简化 | 2026.9.10 |
| ✅ | 7ca223bb | feat(history): 观看历史页重设计 | 2026.9.10 |
| ✅ | 1eab03f3 | feat(ui): 播放源选择卡片重设计 | 2026.9.10 |
| ✅ | 8c0dcc9d | fix(ui): 主页面 AppBar 标题样式统一 | 2026.9.10 |
| ✅ | 4b05b11f | refactor(ui): 统一 M3E 空状态 | 2026.9.10 |
| ✅ | a530f703 | feat(ui): 错误状态重设计并统一 | 2026.9.10 |
| ✅ | 0aadad1e | feat(search): 番剧搜索重设计 | 2026.9.10 |
| ✅ | a71dfa21 | feat(search): 图片搜索重设计 | 2026.9.10 |
| ✅ | 1625761e | refactor(search): 简化图片搜索布局 | 2026.9.10 |
| ✅ | acb28d30 | feat(player): 选集面板重设计 | 2026.9.10 |
| ✅ | 782e7076 | refactor(player): 移除标签页弹幕输入并简化控制边界 | 2026.9.10 |
| ✅ | b6779400 | feat(comments): 统一集数与角色卡片 | 2026.9.10 |
| ✅ | 66d8483c | fix(character): M3E 详情页重设计并恢复角色信息 | 2026.9.10 |
| ✅ | 1aa66d9b | feat(rules): 规则管理重设计 | 2026.9.10 |
| ✅ | 665784a5 | feat(ui): 退出确认重设计 | 2026.9.10 |
| ✅ | 2d39ecbd | feat(onboarding): 引导页重设计 | 2026.9.10 |
| ✅ | 9f8f6a52 | chore: 使用 M3 outlined 输入框 | 2026.9.10 |
| ✅ | 19f71356 | feat(collect): 简化布局并支持竖屏分类滑动 | 2026.9.10 |
| ✅ | 31e0db7f | refactor(dialog): 集中化工作流 | 2026.9.10 |
| ✅ | f26ca74f | refactor(about): 关于页重设计 | 2026.9.10 |
| ✅ | 1c42520 | feat(my): 我的页重设计 | 2026.9.10 |
| ✅ | 091b357 | feat(settings): 同步设置重设计 | 2026.9.10 |
| ✅ | 98e331c7 | feat(info): 评论对话框重设计 | 2026.9.10 |
| ✅ | e140ecd8 | feat(collect): 手动同步重设计 | 2026.9.10 |
| ✅ | 3977a81a | feat(settings): 响应式嵌套路由 | 2026.9.10 |
| ✅ | d780e997 | refactor(settings): 简化导航并移除死代码 | 2026.9.10 |
| ✅ | cddf2b38 | fix(settings): 恢复页面转场 | 2026.9.10 |

编译打通中修复的问题(本分支新增,不属上游提交):
弹窗 API 兼容层(`KazumiDialog.showLoading`/`showTimedSuccessDialog`)、源搜索面板采用上游重构版并清理重复磁力面板、补回剧集评论接口、播放器面板传参对齐、`DanmakuDestination` 重复枚举清理、新增 `image_cache_service.dart`、`settingsPageTransitionsTheme` 补全、`getCalendarBySearch` 返回类型修正、`search_parser.updateSort` 保留。详见 CHANGELOG 2026.9.10。

## 批次 5:上游 2.3.2 ~ 2.3.4(基线 23610a52 → 目标 88a8ec59,共 28 个提交)

- 策略:沿用「按提交逐个内容移植 + 回植 fork 功能」,按上游时间顺序应用。
- 本机 Flutter 保持 3.47.2,**跳过**上游 3.47.3/3.47.5 SDK 升级(用户确认两个小版本差距影响不大;pubspec environment 保留 3.47.2)。

| 状态 | 上游提交 | 内容 | 完成日期 |
|---|---|---|---|
| ✅ | 4b29571e | fix(ui): 评分可见性在搜索与收藏卡片生效 | 2026.9.23 |
| ✅ | 5006efac | fix(search): 布局变化时保持输入连接 | 2026.9.23 |
| ✅ | 3bfd5d1f | fix(navigation): 修复 tab 路由不匹配 | 2026.9.23 |
| ✅ | 2624e0c0 | fix(ui): 统一操作按钮高度 | 2026.9.23 |
| ✅ | 1317f20d | fix(webdav): 启动时尊重历史同步开关 | 2026.9.23 |
| ✅ | c2c21b5f | refactor(player): 统一全屏行为与布局归属(回植 fork 功能,见下) | 2026.9.23 |
| ✅ | dc5bd860 | feat(sync): 弹幕屏蔽规则 WebDAV 同步 | 2026.9.23 |
| ✅ | cd9bc04c | fix(player): 退出时加载指示器不再闪烁 | 2026.9.23 |
| ✅ | c94c4830 | fix(ui): 移除重复的空状态操作 | 2026.9.23 |
| ✅ | ac494bce | deps: bump media kit(与 4fed48b5/551b2360 合并接收:最终 ref 6fd002aa;移除 libs overrides 与 media_kit_libs_video 直接依赖;接收 sdk >=3.10.0 下限,flutter pin 保持 3.47.2) | 2026.9.23 |
| ✅ | cd7c0f88 | fix(my): 简化竖屏布局 | 2026.9.23 |
| ✅ | 80e256ec | feat(collect): 响应式布局与可配置默认视图(回植本地/缓存角标到新海报卡与列表瓦片;随上游移除遗留 showAnimeCounter 键) | 2026.9.23 |
| ✅ | c24f9a85 | fix(settings): 窗口关闭选项与启动设置对齐(依赖 80e256ec,在其后应用) | 2026.9.23 |
| ✅ | a2e5a583 | feat(player): 弹幕源选择器重设计 | 2026.9.23 |
| ✅ | 551b2360 | deps: bump media kit(合并入 ac494bce 行接收) | 2026.9.23 |
| ✅ | 4aef9b39 | fix(collect): hero 转场保持圆角 | 2026.9.23 |
| ✅ | ba21fe35 | fix(collect): 分类标签切换平滑过渡 | 2026.9.23 |
| ✅ | (收尾) | 接收上游 test/webdav_service_test.dart;`flutter pub get` 重生成 pubspec.lock 与 windows/linux/macos 插件注册文件。analyze 基线 8→48 条 info:语言版本升至 Dart 3.10 激活 `unnecessary_underscores`/`use_null_aware_elements` 新 lint,0 error / 0 warning 不变 | 2026.9.23 |

### 批次 5 决定跳过

| 状态 | 上游提交 | 原因 |
|---|---|---|
| ❌ | 7d042c09 + f1f1d2e7 | go router 迁移随后即被回退,净效果为零(仅保留其后的 3bfd5d1f 修复) |
| ❌ | 0029b732 / 4fed48b5 | deps: bump media kit——与本分支已接收的 ref 重复(AC494BCE/551b2360 已覆盖),逐项核对 ref 后按需接收 |
| ❌ | 1b395a50 / 285fa01b | deps: bump flutter 3.47.3/3.47.5——本机保持 3.47.2(用户决定) |
| ❌ | 81b7734c | fix(ci): 仅 CI,与本分支无关 |
| ❌ | bcf5f8bc | fix(macos): 仅 macOS(平台约束) |
| ❌ | 7c15b9a9 / 48e3d873 / 88a8ec59 | version 提交——本分支版本号独立(0.0.1),不接收 |

### 批次 5 冲突文件与 fork 回植点

- `player_item.dart` / `player_item_panel.dart` / `smallest_player_item_panel.dart`(上游删除,并入新 `player_transport_bar.dart` / `video_fullscreen_controller.dart` / `video_side_panel.dart`):回植弹幕发射追踪、本地媒体/边下边播 pluginName、Bangumi 进度同步、远程投屏在线模式守卫
- `video_page.dart` / `video_controller.dart`:回植三模式初始化分支(`isOnlinePlaybackMode`)、`LocalMediaVideoPlaybackArgs` / `MagnetStreamVideoPlaybackArgs` 处理、剧集评论接口
- `collect_library_view.dart` / `collect_library_card.dart`:回植本地可用/缓存角标(localCount/cacheCount)
- `index_module.dart` / `init_page.dart`:保留 magnet/media 模块注册与 magnetController 注入
- `settings_keys.dart`:保留 magnet/media 设置组(约 50 项)+ 弹幕轴作用域偏移键
- `danmaku_settings_sheet.dart`:保留 `playerDanmakuController` 参数与弹幕轴偏移面板对接
- `pubspec.yaml`:保留 fork 依赖(libtorrent_flutter vendor、awesome_notifications、local_notifier、watcher、xml、material_new_shapes)与版本 0.0.1,接收上游 media-kit ref 更新
- `fastlane/.flutter`:保持删除;`test/webdav_service_test.dart`:接收上游更新版本

## 批次 6:上游 2.3.5 ~ 2.3.7(基线 88a8ec59 → 目标 02afdabf,共 28 个提交,完成于 2026.10.5)

- 策略:GitHub 直连恢复,新增 blobless clone(`.upstream_tmp/upstream-git`,git-ignored);以 `git merge-file` 做「fork 当前版 vs 基线 88a8ec59 vs 上游 main」三方合并,冲突逐个回植 fork 功能。
- ech_http 由 pub 依赖改为本地 vendor(`third_party/ech_http`,dependency_overrides):上游 hook 把 ~186KB CA 证书嵌成单个 C++ 原始字符串,MSVC(VS 2022)C2026 上限 65,535 字节无法编译;vendor 版在 CMake 层按 ~14KB 分块拼接(仅分块修复,逻辑与 0.2.1 一致),`licenses/ech_http/` 资产与上游一致。

| 状态 | 上游提交 | 内容 | 完成日期 |
|---|---|---|---|
| ✅ | 1a5f408 | feat(network): 可配置 ECH 图片加速(ech_http/http 依赖、licenses/ech_http 资产、代理感知图片缓存) | 2026.10.5 |
| ✅ | 1bb6159 | fix(search): 重复搜索时保留并刷新历史条目 | 2026.10.5 |
| ✅ | 2ba6131 | fix(network): Bangumi API 图片请求启用 ECH(含测试) | 2026.10.5 |
| ✅ | 9aceca1 | fix(collect): 收藏分类标签文字居中 | 2026.10.5 |
| ✅ | 685ddce / cc8f67a / 98d486b | deps: bump ech_http(合并接收,最终 ^0.2.1,落地为 vendor) | 2026.10.5 |
| ✅ | b6e1da2 | deps: bump media kit(6fd002aa → 最终 803c4a27) | 2026.10.5 |
| ✅ | d163d2a | fix(settings): 嵌套页窗口控件去重(SysAppBar 精简;保留 fork 双击最大化/拖拽阈值/最大化按钮,恢复 fork 使用的 bottom 参数) | 2026.10.5 |
| ✅ | 0dfe1dc | feat(player): 进度手势拖回边缘可取消(新 PlayerGestureDetector;替换 fork 旧内联手势层) | 2026.10.5 |
| ✅ | b484025 | feat(info): 封面保存/标题复制紧凑菜单(新 InfoActionsMenu;保留 fork 磁力搜索按钮) | 2026.10.5 |
| ✅ | c4ac0e2 | fix(window): 标题栏控件变更延迟到重启(新 DesktopWindowConfig;fork 页面同步切换) | 2026.10.5 |
| ✅ | b41f98d / 0066f6c / 34e5ebd / 767bdb3 | feat(player): 截图挑选与跨平台导出(净效果接收:新截图控制器/候选面板/导出服务;保留 fork 桌面快捷保存目录链路与 Android 相册流程,SaverGallery 文件名用 fork 的标题_集数_进度命名) | 2026.10.5 |
| ✅ | a132c95 | feat(danmaku): 可配置简繁转换(设置瓦片并入 fork 重排后的单页弹幕设置) | 2026.10.5 |
| ✅ | c576d1d | feat(network): Bangumi API 可配置加速(direct/ech/mirror + bangumi_transport/dio_factory 重构) | 2026.10.5 |
| ✅ | e7e7d3f | fix(network): ECH 客户端复用与请求清理 | 2026.10.5 |
| ✅ | 36d5363 | fix(danmaku): 弹幕搜索历史按番剧持久化(danmaku_source_sheet 增加 bangumiId) | 2026.10.5 |
| ✅ | 241ec54 | fix(plugin): 非 2xx 反爬挑战检测(含测试) | 2026.10.5 |
| ✅ | 0ea0bbd | refactor(ui): 统一下拉菜单(新 KazumiMenu/KazumiMenuItem/SettingsDropdownTile;删除 custom_dropdown_menu) | 2026.10.5 |
| ✅ | eb53fcb | fix(settings): 分类重复点击不再重复导航 | 2026.10.5 |
| ✅ | 02afdab | fix(player): 集评论头部空字幕占位置空 | 2026.10.5 |
| ✅ | .github/workflows/pr.yaml | CI:ech_http 需要 cmake/ninja(pr.yaml 为 fork 未改动的干净接收;release.yaml 为 fork 自维护,不接收) | 2026.10.5 |

### 批次 6 决定跳过

| 状态 | 上游提交 | 原因 |
|---|---|---|
| ❌ | b1826fe / d830231 / 65da249 | version 提交(2.3.5/2.3.6/2.3.7)——本分支版本号独立(1.0.1),不接收 |
| ❌ | 35ae2f6 | deps: bump flutter 3.47.6——本机保持 3.47.2(沿用批次 5 决定) |
| ❌ | (fastlane/.flutter 部分) | fork 保持删除,不接收 |

### 批次 6 冲突文件与 fork 回植点

- `player_item.dart`:保留 fork 截图快捷保存(`ScreenshotSaveService`,桌面分支)+ fork 相册命名;接收上游候选截图流/新手势层;补回 `DanmakuScreen` 挂载与 `onPrevEpisode`;`showDanmakuSwitch` 传 `bangumiId`;删除 fork 旧内联手势 Positioned.fill(被 PlayerGestureDetector 取代,`_commitInteractiveSeek` 由上游 `finishInteractiveSeek(cancelled:)` 取代)。
- `player_item_panel.dart`:更多菜单保留 fork `_buildMoreMenuChildren`(音轨/字幕/字幕延迟/AB 循环/播完动作/画面旋转/在线模式守卫投屏),按钮与菜单项迁移到 KazumiMenu 体系;画面右键菜单经 `PlayerPanelHoldMenuAnchor.controller`(新增可选参数)保留 `open(position:)` 能力。
- `sys_app_bar.dart`:保留 fork StatefulWidget(双击最大化/拖拽阈值/WindowMaximizeButton),接收 DesktopWindowConfig;`bottom` 参数为 fork 下载页/磁力页 TabBar 所需,予保留。
- `bangumi_client.dart`:镜像签名合并——fork 私有镜像(bgmapi.anibt.net)沿旧 `enableBangumiProxy` 开关签名;上游公共 API 域名仅在 mirror 加速模式签名;两者都以「存在 KAZUMI_APPID/KEY 凭据」为前提。
- `dio_factory.dart` / `api_endpoints.dart` / `settings_keys.dart` / `interface_settings.dart` / `theme_settings_page.dart` / `popular_page.dart` / `info_page.dart` / `danmaku_api.dart` 等:零冲突或 1-2 处冲突,均按「fork 功能 + 上游重构」拼接(磁力设置入口、开机自启、媒体库默认页、背景图设置、HeaderScrim、弹幕匹配/标题检索等均保留)。
- `test/player_panel_hold_menu_anchor_test.dart`:适配新 `(context, toggle)` builder 签名,并经新增 `controller` 参数保留「已打开时再 open()」的 SDK 语义用例。

## 决定跳过(按项目平台约束)

| 状态 | 上游提交 | 原因 |
|---|---|---|
| ❌ | 52a18732 | fix(macos): 仅 macOS |
| ❌ | 7b19e26f | fix(linux): 仅 Linux |
| ❌ | 6d4a2d5d | docs(readme): 移除 archlinuxcn 下载源,与 README 无关 |

## 备注

- 两个仓库 git 历史不相连,所有同步均按内容移植,不能直接 cherry-pick。
- 每完成一项需:更新本文件状态 → 更新 CHANGELOG.md → `flutter analyze` / `flutter test` → 提交。
- 上游单文件获取:GitHub clone/ghproxy 均失败,但 `api.github.com`(contents 接口 + base64)可直连;
  注意 `raw.githubusercontent.com` 会**截断大文件**(曾把 28KB 的 `video_controller.dart` 截成 4KB),一律走 api 接口。
  辅助脚本 `tools/fetch_upstream.py`(已 gitignore)。
- 本机代理会话内 flutter 工具不可用(安全层拦截 flutter/dart 对 SDK 缓存文件的写打开,且时通时不通,`flutter.bat` 会静默挂死);
  验证请用 `dart analyze lib test`,test/build 在本机终端执行。
- 整体接收上游 UI 后**必须做一次 fork 功能回归自查**(批次 4 自查发现 2 处丢失:历史页「本地文件不可用」引导、时间线「只看日本动画」开关):
  1. 孤儿文件扫描:遍历 `lib/**.dart`,统计文件 basename 在其他文件中的出现次数,0 次即无引用(用于发现被上游新文件取代的旧文件);
  2. 文案对比:`tools/diff_strings.py`(已 gitignore)列出 dev 有、当前没有的中文短字符串——上游会大量重写文案,需人工筛选出真正丢失的 fork 功能;
  3. 逐项确认 fork 功能入口仍可达:磁力(页面/设置/详情页入口)、本地媒体库、弹幕池与时间轴偏移、低内存模式、搜索本地匹配横幅、历史缺失本地文件引导、WebDAV 排除本地历史、Bangumi 同步偏好、评论标签编辑、时间线筛选。
