# 上游功能同步进度

- 基线:上游 `2.2.8`(640dfdcb)
- 目标:同步上游 `2.2.9` / `2.3.0` / `2.3.1` / `main` 的全部功能(共 72 个提交)
- 状态标记:⬜ 未开始 / 🔄 进行中 / ✅ 已完成 / ❌ 决定跳过(附原因)
- 每完成一项,在对应条目标记 ✅ 并注明日期

> **当前状态(2026.9.10)**:批次 1~3 已完成并在 `dev` 提交;批次 4 在 `sync-upstream-batch4-wip` 分支**完成代码整合**。
> - 工程已升级到 Flutter 3.47.2(上游 pubspec environment 精确要求),`pub get` 通过,mobx 产物(`video/timeline/media` 的 `.g.dart`)由 build_runner 重新生成。
> - 首轮 `dart analyze` 报出 506 个编译错误,WIP 树不可编译;现全部修完,`dart analyze lib test` 为 **0 error / 0 warning**(7 条 info 均为基线存量)。
> - 修复要点见 CHANGELOG 2026.9.10;上游基线 commit:`23610a526ab380d9013d9fe07c7bca73996f796f`(upstream/main,2026-09-09)。
> - 验证与合流:`flutter test` 与 Windows 构建已在 Flutter 3.47.2 下于本机终端跑通,批次 4 已合并回 `dev`。
>   注意:本机代理会话内无法运行 flutter 工具(安全层拦截 flutter/dart 对 SDK 缓存文件的写打开,`flutter.bat` 会静默挂死),
>   test/build 需在本机终端执行,详见备注。

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
