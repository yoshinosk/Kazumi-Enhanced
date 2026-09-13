# 修改日志

每次修改后在此文件**最顶部**追加日志，格式见 `AGENTS.md`。

## 2026.9.13

- 新增首页「继续观看」区域：打开 app 即可在默认的推荐（时间表）页顶部看到最近在看的一部番剧（封面 + 上次集数 + 断点进度），点击卡片或「继续播放」按钮直接恢复上次集数和进度开始播放；更早的记录以横滑封面列表展示（最多 10 条），可快速切换；右上角提供「历史记录」入口直达完整历史页。同时把历史页卡片的恢复播放逻辑抽为共用函数供两处复用，行为不变。
  - 相关文件: lib/pages/history/continue_watching_section.dart（新增）, lib/pages/history/history_resume.dart（新增，共用恢复播放逻辑）, lib/pages/timeline/timeline_page.dart, lib/pages/history/history_page.dart

## 2026.9.10

- 同步上游 2.2.9 ~ 2.3.1（批次 4：M3E UI 重构浪潮，按「整体接收 2.3.1 UI + 回移植本分支功能」策略收尾）
  - 打通前置条件：工程升级到 Flutter 3.47.2（上游 pubspec environment 精确要求）；用 Flutter 3.47.2 重新 `pub get`，并重新生成 mobx 产物
    - 相关文件: pubspec.lock, lib/pages/video/video_controller.g.dart, lib/pages/timeline/timeline_controller.g.dart, lib/pages/media/media_controller.g.dart
  - 修复批次 4 WIP 树的全部编译错误（首轮 analyze 506 个 error → 0 error / 0 warning）
    - 相关文件: lib/bean/dialog/dialog.dart, lib/pages/info/source_sheet.dart, lib/pages/info/info_page.dart, lib/pages/video/video_controller.dart, lib/pages/video/video_page.dart, lib/pages/player/player_item.dart, lib/pages/player/danmaku_destination_sheet.dart, lib/request/apis/bangumi_api.dart, lib/utils/constants.dart, lib/utils/search_parser.dart, lib/services/storage/settings_keys.dart
  - 新版 M3E 弹窗体系（`KazumiDialog.show/showToast/dismiss` + `KazumiDialogController`）下，补回 fork 仍在调用的 `KazumiDialog.showLoading` 兼容实现（含加载弹窗组件与 `dismiss` 对加载句柄的处理），避免改动弹幕库切换弹窗等调用点；顺带删除已无人使用的 `showTimedSuccessDialog`（原调用方 `source_sheet` 已改为上游实现）
    - 相关文件: lib/bean/dialog/dialog.dart
  - 详情页源搜索面板改用上游重构版（`source_sheet.dart` + `source_alias_dialog/source_captcha_flow/source_sheet_view` 三个 part）；本分支仅调整过 import 顺序，无功能损失；同时清理 `info_page.dart` 中误粘贴到 `_InfoHeaderBackground` 的重复磁力搜索面板，并移除新版 `showAdaptiveBottomSheet` 已不支持的 `backgroundColor` 参数
    - 相关文件: lib/pages/info/source_sheet.dart, lib/pages/info/info_page.dart
  - 从上游补回剧集评论相关状态与接口（`episodeInfo`/`episodeCommentsList`/`commentsEpisode`/`isCommentsAscending`/`toggleSortOrder`/`queryBangumiEpisodeCommentsByID`/`commentEpisodeForSelection`/`_resetEpisodeComments` 及独立 `_commentSessions` 取消域），接入切集与销毁流程，供 `episode_comments_sheet`/`video_page` 使用
    - 相关文件: lib/pages/video/video_controller.dart
  - 播放器控制面板对齐上游：`needFullPanel` → `_needsFullPanel`；移除上游面板已内置的 `changeEpisode`/`sendDanmaku`/`showDanmakuDestinationPickerAndSend` 三个传参；删除 `danmaku_destination_sheet.dart` 中与 `player_models.dart` 重复的 `DanmakuDestination` 枚举改为导入
    - 相关文件: lib/pages/player/player_item.dart, lib/pages/player/danmaku_destination_sheet.dart
  - 补齐上游新增依赖与工具：新增 `image_cache_service.dart`（存储设置页图片缓存统计/清理）、`constants.dart` 补 `settingsPageTransitionsTheme`（设置页嵌套路由转场）、`bangumi_api.getCalendarBySearch` 失败分支返回空表、`search_parser.updateSort` 保留（搜索测试依赖）
    - 相关文件: lib/services/storage/image_cache_service.dart, lib/utils/constants.dart, lib/request/apis/bangumi_api.dart, lib/utils/search_parser.dart
  - 清理编译告警：`video_page.dart` 移除未用导入；`settings_keys.dart` 的 `magnetAskDirOnAdd` 改用 `_SettingBoxKey` 常量消除 unused_field
    - 相关文件: lib/pages/video/video_page.dart, lib/services/storage/settings_keys.dart
  - 回植合并中丢失的两处 fork 功能（新 UI 采用上游版本后入口消失）：
    - 本地媒体库历史记录在文件缺失时，恢复「本地文件不可用」引导弹窗（搜索磁力 / 去详情页），原先随旧历史卡片 `bangumi_history_card` 一起丢失；现移入新历史页，普通历史仍保持 toast 提示
      - 相关文件: lib/pages/history/history_page.dart
    - 时间线筛选恢复「只看日本动画」（`timelineOnlyShowJapaneseBangumis` 过滤逻辑与控制器字段都还在，只是新 M3E 选项面板漏了开关）
      - 相关文件: lib/pages/timeline/timeline_options.dart
  - 验证状态：`dart analyze lib test` 通过（0 error / 0 warning，7 条 info 均为基线存量）；`flutter test` 与 Windows 构建已在本机终端用 Flutter 3.47.2 跑通
    - 相关文件: .gitignore

## 2026.9.10

- 上游同步批次 4(M3E UI 重构)中途暂停,WIP 保存至独立分支 `sync-upstream-batch4-wip`(commit 2326d28,不可编译);`dev` 保持在批次 3 完成后的绿色状态,本条仅更新进度文档
  - 相关文件: UPSTREAM_SYNC.md
  - 说明: 批次 1~3 已全部完成并验证(共 7 个功能提交);批次 4 前置条件为 Flutter 3.47.2 SDK(下载速度过慢已中止,续传命令记录在 UPSTREAM_SYNC.md)

## 2026.9.9

- 同步上游 2.2.9 ~ 2.3.1（批次 3：依赖升级）
  - canvas_danmaku ^0.3.1 → ^0.3.3（对齐上游 491482c1/794567ed）；dio 约束 ^5.0.0 → ^5.11.0（对齐上游 main）
    - 相关文件: pubspec.yaml, pubspec.lock
  - 说明: media-kit git ref 与上游 main 一致（994465d）无需变更；Flutter SDK 3.47.x 升级涉及本机工具链与 fastlane/.flutter 子模块更新，暂缓并记录于 UPSTREAM_SYNC.md

## 2026.9.9

- 同步上游 2.2.9 ~ 2.3.1（批次 2 第三部分：弹幕搜索链路）
  - 弹幕搜索 API v2（6c3c46c9）：自动匹配的 `/api/v2/search/anime` 请求追加 `v2=true` 参数提升匹配质量
    - 相关文件: lib/request/apis/danmaku_api.dart
  - 手动弹幕匹配改用搜索集数接口（c32db78c）：新增 `DanmakuApi.searchAnimes`（`/api/v2/search/episodes` + `v2=true`，结果不截断，解决柯南等大系列主条目被 25 条上限挤掉的问题）；`DanmakuSearchResponse` 模型精简并新增 `hasMore`（保留 `errorCode/success/errorMessage` 可空字段以兼容自动匹配路径，本分支自动匹配仍走 `/search/anime`）；手动切换弹幕结果列表显示条目截断提示与类型副标题
    - 相关文件: lib/modules/danmaku/danmaku_search_response.dart, lib/request/apis/danmaku_api.dart, lib/request/config/api_endpoints.dart, lib/pages/player/danmaku_switch_dialog.dart
  - 修复弹幕「持续时间」设置（bd66ce55）：设置面板滑块改为编辑存储的原始时长（不再读被倍速缩放后的运行值），保存后统一通过 `updateDanmakuSpeed` 重新应用倍速；`onUpdateDanmakuSpeed` 回调改为必传
    - 相关文件: lib/pages/settings/danmaku/danmaku_settings_sheet.dart, lib/pages/player/player_item.dart

## 2026.9.9

- 同步上游 2.2.9 ~ 2.3.1（批次 2 第二部分：网络感知低内存模式）
  - 播放器低内存模式升级为三档策略（跟随网络/始终开启/始终关闭，新增 `LowMemoryMode` 枚举与 `lowMemoryPolicy` 设置，兼容旧 `lowMemoryMode` 布尔值）：新增低内存模式选择弹窗（设置页点击进入），播放器缓存策略按策略 + 计量网络 + 本地播放自动计算，设置或网络状态变化时自动应用；应用启动与回前台时刷新计量网络状态；移动数据自动开启时的提示文案更新
    - 相关文件: lib/services/player/low_memory_mode.dart（新增）, lib/pages/settings/low_memory_mode_settings.dart（新增）, lib/services/player/playback_cache_policy.dart, lib/services/network/metered_network_service.dart, lib/services/storage/settings_keys.dart, lib/services/storage/storage.dart, lib/pages/settings/player_settings.dart, lib/pages/player/controller/player_playback_controller.dart, lib/app_widget.dart, lib/main.dart

## 2026.9.9

- 同步上游 2.2.9 ~ 2.3.1（批次 2 第一部分：Bangumi 同步链路重构与播放器错误修复）
  - Bangumi 收藏同步优化（5d1569b3）：收藏拉取改为全量单接口 + 3 并发分页 + 全局 200ms 速率调度（新增 `AsyncRateLimiter`），按服务端 limit 自适应步长，缺 total/空首包防御性抛错，条目按 `bangumiId` 去重；`BangumiCollection.fromJson` 解析加固（id/updated_at 校验、字段可空兜底）；同步冲突仲裁新增「最新优先」（timeFirst）策略，按更新时间比较
    - 相关文件: lib/utils/async_rate_limiter.dart（新增）, lib/modules/bangumi/bangumi_collection.dart, lib/modules/bangumi/sync_priority.dart, lib/modules/collect/collect_sync_merger.dart, lib/request/apis/bangumi_api.dart, lib/request/config/api_endpoints.dart, lib/services/sync/bangumi_sync_service.dart, test/async_rate_limiter_test.dart（新增）, test/collect_sync_test.dart
  - 保留同步偏好并稳定连接状态（92e91e3d）：`BangumiSyncService` 重构为 `ChangeNotifier`（连接状态/错误可监听），失败不再自动关闭同步开关；新增 `saveToken`（先验证后保存）与 `describeError`（401/403/429 等友好错误文案）；新增 `BangumiSyncSettings` 设置区块（连接状态展示、测试/重试连接）；Bangumi 配置页新增「验证并保存」FAB 与 Token 输入校验提示；Bangumi API 支持显式 accessToken 传参、`getBangumiCollectibles` 改为必传 username；手动同步失败提示改用统一错误文案
    - 相关文件: lib/bean/settings/bangumi_sync_settings.dart（新增）, lib/services/sync/bangumi_sync_service.dart, lib/pages/bangumi/bangumi_setting.dart, lib/pages/collect/collect_controller.dart, lib/pages/init_page.dart, lib/pages/webdav_editor/webdav_setting.dart, lib/request/apis/bangumi_api.dart, lib/request/clients/bangumi_client.dart, test/bangumi_sync_service_test.dart（新增）
  - 选集网格正确定位历史集数（a2fd8259）：跳转索引修正为 `episode - 1`、等待 GridViewObserver 绑定后跳转、非桌面端 GridViewObserver 仅包裹移动端布局
    - 相关文件: lib/pages/video/video_page.dart
  - 无效源错误提示改进（3e86da15）+ 源失败 toast 移出错误开关（280a5adc）：新增 `PlayerErrorMapper`，识别「无法识别文件格式」与缓冲期「Failed to open」给出可操作提示；源失败提示不再受「显示播放器内部错误」开关影响；该开关默认值改为关闭
    - 相关文件: lib/services/player/player_error_mapper.dart（新增）, lib/pages/player/controller/player_playback_controller.dart, lib/services/storage/settings_keys.dart
  - 设置页文案优化（d658832d）
    - 相关文件: lib/pages/settings/interface_settings.dart, lib/pages/webdav_editor/webdav_setting.dart

## 2026.9.9

- 同步上游 2.2.9 ~ 2.3.1（批次 1：低冲突功能，共 7 项）
  - 插件支持批量规则导入：新增 `PluginImportParser`，支持一次粘贴多条 `kazumi://` 规则链接（含跨行换行、大写协议头、尾随文本容错）或 JSON 数组，去重并逐条报告失败原因；规则名比较统一为大小写不敏感的 `pluginNameKey`
    - 相关文件: lib/services/plugin/plugin_import_parser.dart（新增）, lib/plugins/plugins.dart, lib/plugins/plugins_controller.dart, lib/utils/encoding.dart, lib/pages/plugin_editor/plugin_view_page.dart, test/plugin_import_parser_test.dart（新增）, test/plugin_api_config_test.dart
  - 修复批量规则更新提示一闪而过：改用持久提示展示批量规则更新状态
    - 相关文件: lib/pages/plugin_editor/plugin_update_actions.dart
  - 下载选集面板自动滚动到正在播放的集
    - 相关文件: lib/pages/download/download_episode_sheet.dart
  - 禁用相关番剧卡片的 Hero 动画，避免转场闪烁
    - 相关文件: lib/pages/info/info_tabview.dart
  - 重构 Android 画中画（PiP）入口：新增 `onModeChanged` 模式回调、`sourceRectHint` 展开动画源区域、宽高比钳制（1:2.39 ~ 2.39:1）防止 `enterPictureInPictureMode` 抛异常、PiP/播放页期间窗口背景强制黑色避免过渡闪白、退出 PiP 后正确恢复系统栏状态、参数更新加异常保护、`seamlessResizeEnabled` 改为 true
    - 相关文件: android/app/src/main/kotlin/com/example/kazumi/MainActivity.kt, lib/services/player/pip_utils.dart, lib/pages/player/player_item.dart, lib/pages/player/player_item_panel.dart, lib/pages/player/smallest_player_item_panel.dart, lib/pages/video/video_page.dart
  - 修复 Android 媒体会话销毁后复现：音频会话生命周期管理与播放器 teardown 解耦
    - 相关文件: android/app/src/main/kotlin/com/example/kazumi/MainActivity.kt, lib/services/player/audio_controller.dart, lib/pages/player/player_item.dart
  - Android 应用切后台时挂起 demuxer 预取，降低后台内存与带宽
    - 相关文件: lib/pages/player/controller/player_playback_controller.dart, lib/pages/player/player_item.dart
- 新增上游同步进度文档 UPSTREAM_SYNC.md

## 2026.9.9

* 修复所有视频弹幕都提前 1:22 的问题：遗留全局弹幕轴偏移（-82 秒）未被清理。旧版（偏移作用域化之前）的手动调整（快速菜单 / 详细调整面板）与自动检测「应用推荐偏移」全部直接写入全局设置 `danmakuTimeOffset`，且当时会被已存在的番剧级作用域偏移遮蔽「看似无效」，用户反复点击「提前」后在全局累积出从未生效的 -82 秒；偏移作用域化后该遗留值作为 `effectiveOffset` 的兜底作用于所有未命中作用域的视频，表现为「播放任何视频弹幕都提前 1:22」。新增一次性迁移清零遗留全局偏移（新标记 `danmakuTimeOffsetGlobalMigrated` 门控，只执行一次，此后用户主动设置的全局偏移保留），分集 / 番剧作用域偏移不受影响；新增迁移测试用例

  * 相关文件: lib/utils/danmaku_time_offset_store.dart, lib/services/storage/settings_keys.dart, lib/main.dart, test/danmaku_time_offset_store_test.dart

## 2026.9.5

* 磁力下载支持在创建任务时选择下载目录：新增「添加下载任务」确认弹窗，展示资源信息与目标目录，可临时为单个任务指定保存位置（含「使用默认目录」一键还原）；本次会话手动选过的目录会作为后续任务的默认值，批量下载无需重复选择

  * 相关文件: lib/pages/magnet/magnet\_download\_dialog.dart, lib/pages/magnet/magnet\_page.dart

* 统一各创建任务入口：搜索结果、订阅条目、剪贴板磁力检测、手动添加链接四个入口全部走同一套目录选择逻辑；订阅条目沿用订阅自带下载目录作为初始值

  * 相关文件: lib/pages/magnet/magnet\_page.dart

* 抽取目录选择公共工具 lib/utils/directory\_picker.dart：picker + 可写探测 + Android「所有文件访问」授权引导，设置页磁力下载目录、订阅下载目录、入库根目录统一复用；新增设置项「添加任务时询问下载目录」（默认开启，关闭后直接按默认目录提交）

  * 相关文件: lib/utils/directory\_picker.dart, lib/pages/settings/magnet\_settings.dart, lib/services/storage/settings\_keys.dart

* 提交下载前确保目标目录存在，避免用户指定的新目录因路径不存在导致落盘失败

  * 相关文件: lib/services/magnet/magnet\_download\_service.dart

## 2026.9.2

* 修复本地媒体库弹幕轴偏移手动调整不生效的问题：手动调整（快速菜单 / 详细调整面板 / 弹幕设置页）此前只读写全局偏移，会被已存在的分集 / 番剧作用域偏移（弹幕轴自动检测应用过的推荐值）遮蔽，表现为"调整提前 1 分 22 秒没有反应"。现在手动调整基于当前作用域的有效偏移增减并写回当前作用域，菜单与设置页同步展示有效偏移；"恢复无偏移"在作用域内显式写入 0（可遮蔽番剧级与全局偏移），确保清零立即生效

  * 相关文件: lib/pages/player/danmaku\_offset\_menu.dart, lib/pages/settings/danmaku/danmaku\_time\_offset\_sheet.dart, lib/pages/settings/danmaku/danmaku\_settings\_sheet.dart, lib/pages/player/player\_item\_panel.dart, lib/pages/player/smallest\_player\_item\_panel.dart, lib/pages/player/episode\_danmaku\_sheet.dart

* 修复弹幕轴偏移作用域污染：旧版自动检测在 episodeId 未知时把推荐偏移写成了番剧级作用域（`bangumiID:0`），单集的检测结果会作用于同番剧所有分集（如药屋 EP35 的 +82 秒推荐污染了 EP37）。现在文件哈希匹配、搜刮映射、标题检索、在线播放各路径都会把弹弹 episodeId 传递到控制器，推荐偏移按精确分集作用域写入；弹幕侧车缓存同时持久化 danDanEpisodeId（旧侧车回读为 0 保持兼容）。附带一次性迁移清理历史番剧级作用域偏移

  * 相关文件: lib/pages/player/controller/player\_danmaku\_controller.dart, lib/request/apis/danmaku\_api.dart, lib/pages/download/download\_controller.dart, lib/utils/danmaku\_time\_offset\_store.dart, lib/services/storage/settings\_keys.dart, lib/main.dart

* 修复弹幕轴自动检测把"ED 后自然稀疏尾"误判为轴偏移的问题：故事与 ED 结束后视频还剩片尾滚铭 / 下集预告时观众极少发弹幕，P99.5 轴尾空白只是稀疏尾而非硬截断（如药屋 EP35/36 因此被错误推荐延后 82/92 秒）。新增轴尾覆盖守卫：结尾容差窗口内仍有弹幕（≥2 条）说明池覆盖到了视频结尾，轴尾空白不再作为轴偏移证据

  * 相关文件: lib/utils/danmaku\_axis\_checker.dart

* DanmakuTimeOffsetStore 迁移至独立文件（lib/utils/danmaku\_time\_offset\_store.dart），避免入口与 UI 层反向依赖播放器控制器；新增侧车 episodeId 回写与稀疏尾守卫的测试用例

  * 相关文件: lib/utils/danmaku\_time\_offset\_store.dart, lib/pages/player/danmaku\_axis\_dialog.dart, test/local\_media\_danmaku\_test.dart, test/danmaku\_axis\_checker\_test.dart

## 2026.8.30

* 完成 Android 本地构建链路配置：新增 Gradle 发行版腾讯云镜像（解决国内网络访问 services.gradle.org 超时），并为 libtorrent\_flutter 补充 armeabi-v7a / x86\_64 的 prebuilt .so（arm64-v8a 原有），使完整三 ABI 均可跳过 GitHub prebuilt 下载直接使用本地预编译库，`flutter build apk --release` 已在本地验证构建成功（app-release.apk 87.8MB）

  * 相关文件: android/gradle/wrapper/gradle-wrapper.properties, third\_party/libtorrent\_flutter/prebuilt/android/armeabi-v7a/liblibtorrent\_flutter.so, third\_party/libtorrent\_flutter/prebuilt/android/x86\_64/liblibtorrent\_flutter.so

## 2026.8.30

* 新增安卓端本地构建脚本 build\_android\_local.ps1：与 Windows 脚本一致，读取 local\_dandan\_credentials.env 注入 DANDANAPI\_APPID/DANDANAPI\_KEY 的 dart-define，执行 flutter build apk --release

  * 相关文件: tools/build\_android\_local.ps1

## 2026.8.30

* 修复 Android 15+ 前台服务达到系统时限（dataSync 每日约 6 小时）后被静默停止的问题：TaskHandler onDestroy 收到 isTimeout 时通知主 isolate，标记服务已停止、清空全部租约并发系统通知提醒用户；同时为 startService 增加失败冷却（5 分钟内不再重试），避免磁力下载每 2s 一轮的租约同步反复触发必败的原生启动调用刷异常日志

  * 相关文件: lib/services/download/background\_download\_service.dart

* 磁力下载目录选择增加 Android 写入权限校验：选完目录后写临时探测文件验证可写，不可写且未授予「所有文件访问」时弹窗引导跳转系统设置，用户返回应用后自动重新探测，仍失败则提示更换目录（避免 libtorrent 落盘 EACCES 卡死任务）

  * 相关文件: lib/pages/settings/magnet\_settings.dart

* 磁力下载状态轮询增加生命周期感知：应用退后台后由 2s 降为 30s 低频轮询（省电，进度持久化与通知更新仍继续），回前台自动恢复

  * 相关文件: lib/services/magnet/magnet\_download\_service.dart

* 「仅 WiFi 下载」策略改为流式监听网络切换（onConnectivityChanged），WiFi ↔ 移动数据切换立即暂停/恢复任务，不再等最长 60s 的策略周期轮询，消除切换后偷跑流量窗口

  * 相关文件: lib/services/magnet/magnet\_download\_service.dart

* 修复引擎重启 reconcile 期间并发新增/删除任务的竞态：重挂循环改为快照迭代（消除 ConcurrentModificationError 风险），结尾合并循环期间的并发变更，不再用旧快照整体覆盖任务索引（避免丢失新增条目 / 复活已删除任务）

  * 相关文件: lib/services/magnet/magnet\_download\_service.dart

* 优化磁力任务搜刮结果同步到媒体库的性能：目录分组扫描键按文件清单指纹缓存（避免每 2s 一轮的 onChanged 重复执行同步 IO 与重量级分组计算），同步连续失败 3 次后本会话退避跳过（不再无限重试）

  * 相关文件: lib/pages/magnet/magnet\_controller.dart

* 修复磁力剪贴板检测的去重口径：改用与下载队列一致的 info-hash 规范化比较（忽略 tracker 参数差异），同一资源不同 tracker 参数的磁力不再先弹确认框、再提示已在队列

  * 相关文件: lib/pages/magnet/magnet\_page.dart, lib/pages/magnet/magnet\_controller.dart

* 修复前台服务通知栏速度单位固定 MB/s 导致低速时显示「0.0 MB/s」的问题：改用自适应单位（B/s / KB/s / MB/s）

  * 相关文件: lib/pages/magnet/magnet\_controller.dart

* 「未匹配卡片视频缩略图」设置项在 Android 上标注仅桌面端可用（Android 设备通常没有 ffmpeg，开关不会生效）

  * 相关文件: lib/pages/settings/magnet\_settings.dart

## 2026.8.30

* 同步 CHANGELOG（2026.8.16 \~ 2026.8.30）更新 README：项目特点新增「播放器增强」；开发路线新增「播放器增强」小节（Anime4K 六档超分辨率、着色器版本整体覆盖、Windows 渲染器选项、弹幕轴偏移推荐检测与作用域持久化、倍速弹幕修复）；本地媒体库与磁力下载小节补充已完成的开发项（番剧右键删除、鲁棒扫描、占位历史迁移、种子元数据持久化、去重防假做种、按添加时间排序、本地播放分流、RSS 自动检查、做种时长最低 1 小时）；近期计划 TODO 同步当前待办

  * 相关文件: README.md

## 2026.8.30

* 优化播放器弹幕轴推荐偏移算法：不再仅对比「弹幕轴总长度 vs 视频时长」（该方案把 ED 弹幕群后的片尾滚铭、片头安静开场等自然空窗误判为轴偏移，推荐出错误偏移量）。新方案改为基于弹幕时间分布头尾两端的「空白 / 越界」信号，并做密度形态校验与冲突检测：

  * 四类候选信号：轴尾硬截断→延后、轴尾越界→提前、轴头越界→延后、轴头硬边界→提前（头空白仅在轴尾同时越界、构成整轴平移佐证时采信，避免安静开场误报）

  * 密度形态校验区分「硬截断」与「自然空窗」：边界前弹幕相对前一窗口骤降（自然稀疏）或骤升（ED 弹幕群后戛然而止）时空白不可信、不产生信号

  * 弹幕源错误判定改用轴「跨度」（头尾分位之差）与视频时长比较，并新增头尾信号方向冲突（单一偏移无法同时修复两端）即判定换源

  * 同向信号按幅度加权融合为推荐偏移，输出置信度（多个同向信号互相印证时提升），弹窗展示轴头/轴尾空白与推荐可信度

  * 有效弹幕样本数低于 30 条时不检测，避免小样本统计失真

  * 相关文件: lib/utils/danmaku\_axis\_checker.dart, lib/pages/player/danmaku\_axis\_dialog.dart, test/danmaku\_axis\_checker\_test.dart

## 2026.8.30

* 修复测试卡死问题：Windows 上 flutter\_tester 环境中 `Directory.deleteSync(recursive: true)` 会死循环（同步删除与 flutter\_tester 线程模型冲突，连仅含文件的目录也会挂死；纯 Dart CLI 与异步 `delete()` 均正常）。local\_media\_scanner\_test 的「单个番剧文件夹保持整体（不拆分）」等用例断言本可通过，但 tearDown 的同步递归删除永不返回，导致整个测试文件挂起 19 分钟。将三处测试清理改为异步 `await delete(recursive: true)`，测试 1 秒内跑完

  * 相关文件: test/local\_media\_scanner\_test.dart, test/magnet\_media\_key\_test.dart, test/magnet\_download\_entry\_test.dart

## 2026.8.30

* 扩展超分辨率档位：由「关闭 / 效率 / 质量」两档扩展为 Anime4K 官方定义的六种模式（效率 Mode C、降噪 Mode C+A、均衡 Mode B、质量 Mode A、均衡增强 Mode B+B、极致 Mode A+A），补齐此前缺失的 Mode B 与三个增强模式。各档链路严格按上游 `md/GLSL_Instructions_Advanced.md` 的 `Restore / Restore_Soft / Upscale_Denoise -> Upscale` 组合编排，两个 Upscale 之间保留 AutoDownscalePre 以降采样到接近屏幕尺寸、避免在远大于显示尺寸的纹理上浪费算力；原质量档链路本就与上游 `GLSL_Windows_High-end` 模板一致，未作改动。枚举声明顺序即开销递增顺序，UI 直接按此顺序展示；已发布档位的 storageValue（off=1 / efficiency=2 / quality=3）保持不变，老用户设置不会错位。档位定义下沉为枚举的 `shaders` 字段，`setShader` 不再需要 switch 分支，今后新增档位只需改枚举一处

  * 相关文件: lib/pages/player/controller/player\_super\_resolution.dart, lib/utils/constants.dart, lib/pages/player/controller/player\_playback\_controller.dart, lib/pages/player/player\_item.dart, lib/pages/settings/super\_resolution\_settings.dart

* 新增 Anime4K 着色器：Restore\_CNN\_Soft\_M、Restore\_CNN\_Soft\_S、Upscale\_Denoise\_CNN\_x2\_M、Upscale\_Denoise\_CNN\_x2\_S（取自 bloc97/Anime4K，MIT 协议，与仓库内既有 LICENSE 一致）。Soft 变体针对降采样产生的振铃与锯齿，Upscale\_Denoise 在放大同时降噪且无额外性能开销

  * 相关文件: assets/shaders/Anime4K\_Restore\_CNN\_Soft\_M.glsl, assets/shaders/Anime4K\_Restore\_CNN\_Soft\_S.glsl, assets/shaders/Anime4K\_Upscale\_Denoise\_CNN\_x2\_M.glsl, assets/shaders/Anime4K\_Upscale\_Denoise\_CNN\_x2\_S.glsl

* 修复着色器升级后不生效的问题：此前 `ShaderAssetService` 只要目标文件存在就跳过拷贝，导致应用升级后老用户仍在使用旧着色器。现引入 `shaderBundleVersion` 版本文件（存于 `anime_shaders/.shader_bundle_version`），版本不匹配时整体覆盖重写；仅当全部文件拷贝成功才记录版本，失败的文件可在下次启动时补上。今后增删或替换着色器必须递增 `shaderBundleVersion`

  * 相关文件: lib/services/shaders/shader\_asset\_service.dart

* Windows 端新增视频渲染器选项（自动 / gpu / gpu-next）：随包分发的 libmpv 已内置 libplacebo 与 Vulkan，但此前 Windows 无渲染器设置、只能走 mpv 默认的 `gpu`。默认值为 auto，此时不向 mpv 传 `vo`，与引入该设置前的行为完全一致，老用户升级无回归；渲染器设置页按平台切换选项列表与存储键

  * 相关文件: lib/services/storage/settings\_keys.dart, lib/utils/constants.dart, lib/pages/settings/renderer\_settings.dart, lib/pages/player/controller/player\_playback\_controller.dart

* 新增超分档位单元测试：校验各档引用的着色器真实存在、Clamp\_Highlights 位于链路首位、storageValue 唯一且已发布取值不漂移

  * 相关文件: test/super\_resolution\_shaders\_test.dart

## 2026.8.26

* 调整磁力下载设置界面：做种指定时长下拉项最低改为 1 小时（新增「1 小时」选项，原最低 6 小时）

  * 相关文件: lib/pages/settings/magnet\_settings.dart

## 2026.8.26

* 媒体库番剧视图的番剧条目新增右键菜单（桌面端），菜单提供「删除」功能：点击后弹出二次确认对话框（列出将删除的文件夹、视频数与总体量），确认后删除该番剧所有本地关联的文件和目录——组内文件夹为真实目录且不含其他番剧文件时整目录递归删除（含外挂字幕、弹幕侧车等）并向上清理变空的祖先目录；目录为用户添加的媒体库根目录、混有其他番剧文件或是标题分组产生的逻辑路径时退化为逐个删除本组视频，并在无视频残留的目录中清理弹幕侧车文件后自底向上删除空目录（不越过媒体库根目录）；同时清理按路径持久化的文件夹级 / 文件级搜刮结果与未匹配缩略图缓存条目，最后重扫同步内存库

  * 相关文件: lib/pages/media/media\_library\_page.dart, lib/pages/media/media\_controller.dart

## 2026.8.25

* 修复从磁力任务播放入库番剧时播放器选集面板只显示当前任务文件、看不到本地媒体库同番剧其他集数的问题：磁力任务播放（`_showCompletedPlayback`）此前只把任务自身落盘文件传给播放器，现按任务搜刮的 `bangumiId` 合并本地媒体库中同番剧文件（按路径去重、按文件名解析集数排序）后再传入，选集面板可见全部本地集数；任务文件已入库（原路径被移走）时回退直接用媒体库文件播放

  * 相关文件: lib/pages/magnet/magnet\_page.dart

## 2026.8.23

* 调整磁力下载页排序为固定按添加时间倒序（新添加的在前），不再随任务状态（下载中 / 做种 / 已完成等）变化而跳动：平铺列表与分组内任务统一按 `addedAt` 排序；分组模式下分组之间以「添加分组的时间」（组内最早任务的添加时间，即创建分组的时刻）倒序排列。服务层展示排序同步移除「已完成任务后置」逻辑

  * 相关文件: lib/pages/magnet/magnet\_page.dart, lib/services/magnet/magnet\_download\_service.dart

* 修复已下载完成的任务在「已暂停 / 已停止」等状态下右键菜单仍显示「边下边播」的问题：新增 `MagnetDownloadEntry.hasCompleteFiles` 判定文件是否完整落盘——除 complete / seeding 外，还覆盖「下载完之后再被暂停」的任务（进入完成态时 verifiedLength 已对齐总量并持久化，据此与下载中途暂停区分），此类任务右键菜单一律显示「播放」并走媒体库本地播放流程；未完成任务才保留边下边播入口

  * 相关文件: lib/pages/magnet/magnet\_page.dart, lib/services/magnet/magnet\_download\_service.dart, test/magnet\_download\_entry\_test.dart

## 2026.8.23

* 修复磁力下载页已完成但仍在做种的任务右键菜单误显示「边下边播」的问题：下载完成（含做种中，文件已完整落盘）的任务应走本地「播放」逻辑而非引擎边下边播。新增 `MagnetDownloadEntry.isFinished`（status 为 complete 或 seeding），并用于磁力下载列表任务条目的播放入口判定（菜单文案与点击回调统一按 `isFinished` 分支）

  * 相关文件: lib/services/magnet/magnet\_download\_service.dart, lib/pages/magnet/magnet\_page.dart

* 修复磁力下载任务「磁力页已搜刮但媒体库未匹配」的问题：搜刮结果同步到媒体库时以任务真实落盘目录为键，但媒体库扫描器对混存多部番剧的目录（如单文件种子直接落盘的下载根目录）会按清洗后标题拆出逻辑分组文件夹（`<目录>/<清洗后标题>`），导致同步键与扫描产出的文件夹路径不一致、媒体库查表落空。现改为按扫描器同款分组口径（新增 `LocalMediaScanner.scanFoldersForDir`，列目录直接视频文件后走同一标题分组逻辑）计算任务所属的媒体库键，单文件种子混部场景也能命中；同时历史已搜刮任务不再要求 complete/seeding 状态（文件已落盘即同步，修复 queued/metadata 状态任务永不入库的问题），同步后清理旧版遗留的真实目录键死数据

  * 相关文件: lib/services/media/local\_media\_scanner.dart, lib/pages/magnet/magnet\_controller.dart, test/local\_media\_scanner\_test.dart, test/magnet\_media\_key\_test.dart

## 2026.8.22

* 修复磁力搜索页字幕组筛选选择列表的问题：选中某字幕组后会按该组重新搜索，而候选列表此前直接取自当前搜索结果，导致再次打开时只剩当前选中的字幕组、必须先清除筛选才能选其它组。现于控制器中按关键词缓存出现过的字幕组候选（搜索与加载更多时合并去重，切换关键词自动重置），筛选后仍展示完整候选

  * 相关文件: lib/pages/magnet/magnet\_controller.dart, lib/pages/magnet/magnet\_page.dart

## 2026.8.22

* 修复重启后已完成未做种完的任务先显示「正在获取种子元数据」一段时间才恢复做种的问题：磁力链只含 info-hash，种子元数据（文件布局 + 分片哈希）只存在于引擎进程内存，之前缓存的 `files` 清单仅是 Dart 层展示数据、引擎无法据此恢复，重启重挂只能重新从 DHT/peer 拉取元数据。现于元数据首次到达时把引擎内元数据导出为 `.torrent` 持久化（按 info-hash 存于应用支持目录 `magnet/torrents/`，幂等），重挂（重启 reconcile / 错误重试 / 元数据超时重试）优先加载缓存的 `.torrent`，引擎立即拿到完整文件布局、直接校验磁盘续做种 / 续传，缓存损坏时自动回退磁力。新增原生接口 `lt_export_torrent`（create\_torrent + bencode 落盘）并补齐 FFI 绑定与 `exportTorrent` 方法

  * 相关文件: third\_party/libtorrent\_flutter/src/torrent\_bridge.h, third\_party/libtorrent\_flutter/src/torrent\_bridge.cpp, third\_party/libtorrent\_flutter/lib/src/ffi\_bindings.dart, third\_party/libtorrent\_flutter/lib/src/libtorrent\_flutter\_base.dart, lib/services/magnet/magnet\_download\_service.dart

## 2026.8.22

* 按番剧分组的下载列表子条目精简：组头已展示番剧封面与番剧名，子条目不再重复显示封面和番剧名（标题改用文件名 / 任务名，便于区分集数），并隐藏冗余的「已搜刮」标记（「待确认」「已入库」保留），样式与未搜刮条目一致

  * 相关文件: lib/pages/magnet/magnet\_page.dart

## 2026.8.22

* 修复磁力任务菜单「播放」误走边下边播流程的问题：菜单项对已完成任务显示「播放」但实际仍调用引擎流（`startStream`），而已完成任务的引擎句柄在完成时已被移除（停止做种），点「播放」只会报「启动边下边播失败」。改为已完成任务走媒体库本地播放流程（`LocalMediaVideoPlaybackArgs`）：枚举任务已选择且真实落盘的视频文件（按存在性过滤，已入库 / 被移动的文件自动跳过），选择后经应用内播放器直接播放本地文件，弹幕、历史续播（与媒体库同路径互相续播）、Bangumi 进度联动均沿用媒体库链路；未完成任务仍走边下边播

  * 相关文件: lib/pages/magnet/magnet\_page.dart

## 2026.8.22

* 磁力下载任务列表交互优化：

  * 任务条目新增集数范围标签（如「第 1 集」「第 1-12 集」），按文件名解析所选文件的集数，解决已搜刮任务按番剧分组后条目统一显示番剧名、无法区分集数的问题

  * 种子内只有一个文件时隐藏「选择下载文件」菜单项（无部分下载余地）

  * 支持右键任务条目直接展开操作菜单（与「⋯」按钮一致，Windows 桌面端）；已完成任务的菜单项显示「播放」而非「边下边播」，多文件选择面板标题同步调整为「选择要播放的文件」

  * 相关文件: lib/pages/magnet/magnet\_page.dart

## 2026.8.22

* 修复磁力任务「边下边播后瞬间 100% / 已完成」的根因：libtorrent 官方语义中 `finished/seeding` 仅表示**优先级 > 0 的片段已下完**（可伴随「部分片段被过滤未下载」），而边下边播启动流时原生引擎（`lt_start_stream`）会把非流窗口片段全部降为 `dont_download`，流窗口（头部 + 尾部 + 起播关键片段，通常仅数十 MB）下完引擎即如实上报 `finished/progress=1.0`；应用层此前把它当作整包完成，`completedLength` 被对齐到整包大小导致假 100%，文件实际只有流窗口数据。新增完成态覆盖校验（`completionCoversExpected`）：引擎的 `totalWanted` 与 `totalDone` 未覆盖期望下载集（全部文件或已选择文件之和）的完成上报一律按下载中处理，任务保持真实进度，停止播放恢复优先级后继续下载剩余部分；已处于完成 / 做种态的任务不受影响。另将「原生完成上报」诊断日志改为 `forceLog` 持久化（INFO 默认不落盘，导致此前复现无据可查）

  * 相关文件: lib/services/magnet/magnet\_download\_service.dart, test/magnet\_download\_entry\_test.dart

## 2026.8.22

* 修复磁力任务「文件不完整却显示做种中 / 100%」：`_onTorrents` 中「完成态可信」证据含 `checking` 状态，而当目标目录已残留（可能不完整）同名文件时引擎校验阶段的 `totalDone` 会从 0 爬升，据此置位后引擎一报 `finished/seeding` 即被直接信任导致假做种；收严为**仅当** **`active`** **且** **`hasMetadata`** **且** **`totalDone > 0`**（真实进入下载并校验 / 下载出字节）才置位可信，`checking` / 空 `active` 不再充当完成证据，交给「可疑瞬时报完成」检测强制 `recheck` 按磁盘真实情况转成续传缺失。另新增完成态上报的现场诊断日志便于确认引擎的 `state/progress/totalDone/totalWanted/isFinished/hasMetadata`。

  * 相关文件: lib/services/magnet/magnet\_download\_service.dart

## 2026.8.22

* 修复创建磁力下载任务时磁盘空间校验误判「空间不足」的问题：Animes Garden 搜索源的 `size` 字段单位为字节（API 实测直接返回字节数，如 781398016 ≈ 745 MB），原 `_formatKbSize` 误当作 KB 乘以 1024，导致磁力任务体积被放大 1024 倍，磁盘空间校验用错误体积对比而误报「空间不足」；改为按字节处理（重命名为 `formatAnimesGardenSize`），并补充回归测试

  * 相关文件: lib/services/magnet/animes\_garden\_service.dart, test/animes\_garden\_size\_test.dart

## 2026.8.19

* 调整磁力 RSS 订阅功能：新增自动检查更新间隔设置（默认 1 小时，可在设置中调整为 30 分钟～1 天），定时检查发现新条目时自动提交下载

  * 相关文件: lib/services/storage/settings\_keys.dart, lib/services/magnet/magnet\_subscription\_service.dart, lib/pages/magnet/magnet\_controller.dart, lib/pages/settings/magnet\_settings.dart

## 2026.8.19

* 磁力 RSS 订阅：打开软件时立即检查一次订阅更新；添加订阅时立即检查并自动下载当前 feed 条目（按订阅的自动下载开关决定是否下载，引擎未启用等失败场景不推进游标、下次定时检查自动重试）

  * 相关文件: lib/services/magnet/magnet\_subscription\_service.dart, test/magnet\_subscription\_service\_test.dart

## 2026.8.19

* 播放器弹幕面板「弹幕池 / 切换分集」按钮上方增加边距，避免紧贴分隔线

  * 相关文件: lib/pages/player/episode\_danmaku\_sheet.dart

## 2026.8.19

* 修复本地媒体库播放时弹幕池绑定到其它番剧的问题（弹幕正常关联但不显示 / 轴对不上）：

  * 策略链原为「侧车缓存 → 下载缓存 → 文件哈希匹配 → BGM 映射 → 标题检索」，文件哈希匹配 / 标题检索可能把弹幕池绑到与搜刮结果不同的番剧，且侧车缓存会固化这种错误绑定 —— 改为优先按「搜刮的番剧」绑定：先解析搜刮 BGM ID 对应的弹弹番剧 ID，命中且该集有弹幕时直接采用，文件匹配 / 标题检索仅作兜底

  * 侧车缓存新增番剧一致性校验：搜刮番剧的弹弹 ID 已知且侧车 `danDanBangumiID` 与之不符时丢弃侧车（历史错误绑定），改按搜刮番剧重新绑定

  * 在线播放路径行为不变（文件匹配本就只用于本地文件）

  * 相关文件: lib/pages/player/controller/player\_danmaku\_controller.dart

## 2026.8.18

* 修复磁力下载重复任务与「刚创建就显示做种中」问题：

  * 同磁力链（info-hash 相同、tracker 不同）重复提交会创建重复任务：新增按 `xt=urn:btih` 归一化的去重（忽略大小写 / tracker / dn 差异），`add()` 直接忽略重复，搜索界面重复提交提示「该资源已在下载队列中」

  * 新建任务几秒内即显示「做种中 / 100%」而文件实际是空占位：元数据未就绪时引擎把「0 片（无内容可下）」的磁力上报为 `progress=1.0 / is_finished`，`_mapStatus` 不再对无元数据任务判完成；元数据到达后引擎可能跳过磁盘校验直接报完成 —— 新增「可疑瞬时报完成」检测，任务从未下载、也未经过引擎校验却被报完成时强制 `recheck` 校验磁盘（空文件转下载、数据完整维持做种），重挂 / 重试后重新评估

  * 相关文件: lib/services/magnet/magnet\_download\_service.dart, lib/pages/magnet/magnet\_controller.dart, test/magnet\_download\_entry\_test.dart

## 2026.8.16

* 修复本地文件手动绑定弹幕库（弹幕检索 / 弹幕切换）后弹幕不显示的问题：

  * `getDanDanmakuByEpisodeID` 绑定成功后不写回弹弹番剧 ID：本地播放自动加载失败（`bangumiID=0`）后手动绑定，弹幕面板仍显示「未绑定弹幕」、弹幕轴偏移作用域落到 `0:episodeId` 与其它本地文件互相污染 —— 新增 `bangumiId` 参数并在绑定成功时写回，`bindDanmakuToEpisode` 及各调用点补传番剧 ID

  * 弹幕池整体替换后发射代次不复位：播放器发射追踪误以为当前秒已发射，绑定瞬间当前秒的弹幕被跳过 —— 绑定成功后清空画布残留弹幕并递增发射代次，追踪复位后从当前秒重新发射

  * 弹幕面板以 `bangumiID <= 0` 判定「未绑定弹幕」：弹幕池非空（侧车文件 / 手动绑定，bangumiID 可能为 0）也被隐藏 —— 改为按弹幕池是否为空判定，空态文案仍区分「未绑定 / 池为空」

  * 相关文件: lib/pages/player/controller/player\_danmaku\_controller.dart, lib/pages/player/controller/player\_danmaku\_controller.g.dart, lib/pages/player/danmaku\_switch\_dialog.dart, lib/pages/player/episode\_danmaku\_sheet.dart

## 2026.8.16

* 修复审查确认的 9 个问题：

  * 自动入库会移动 / 重命名正在被边下边播流读取的文件导致断流：`MagnetDownloadService` 新增 `isStreaming()`，`shouldAutoImport` 对在播任务跳过入库（不标记失败，流停止后下一轮状态同步自动重试）

  * `clearCompleted()` 不停止在播任务的流服务器 / 做种句柄导致端口泄漏至进程退出：清除前逐个调用 `stopStreamsForTask()` 补做流停止与引擎移除

  * tracker 定时器回调在 `dispose()` 之后重建调度链、退出后继续联网且无 try/catch：调度入口加 `_disposed` 检查，回调包 try/catch，更新失败也继续下一周期自愈

  * 新订阅首拉 feed 为空时 `lastGuid=null`、下一轮把整个 feed 当新条目全量自动下载：游标未初始化时本轮只建立游标、不上报新条目

  * 媒体库标题分组「假路径」键随目录文件集合变化（单标题 ↔ 多标题）失效、搜刮 / 历史迁移按旧键永久丢失：扫描结果新增分组快照（目录 → 归一化标题 → 分组路径，新增设置 `localMediaLastGrouping`），每次扫描按标题对齐新旧快照并迁移搜刮结果到新键

  * 弹幕池面板每次 build 全量 flatten + O(N log N) 排序（数万条弹幕时卡顿）：`PlayerDanmakuController` 新增弹幕池版本计数，面板按版本缓存排序结果

  * WebView 旧页面在导航切换期间迟到的解析事件被新 resolve 接受、可能播错 URL/offset：新增页面代际（`beginPageLoad` / `markPageStarted` / `canAcceptResolve`），Android 实现以新页面脚本启动标记、通用回退实现以 `onLoadStart` 为界丢弃旧页面迟到消息

  * 播放中每秒 2 行历史同步事件写入、约 1 小时触发 1MB checkpoint 全量重写：进度事件按（条目, 分集, 线路）10 秒窗口合并，中间重复写入直接丢弃（事件为幂等 upsert，不影响最终一致性）

  * 前台服务拒绝通知权限后每批任务重复弹窗、acquire 失败后租约悬挂：权限询问改为会话级记忆（拒绝后不再重复弹自定义窗），`acquire` 启动失败时回滚本次新增租约，避免 `isHeldBy` 门控误判服务可用而不再重试

  * 相关文件: lib/services/magnet/magnet\_download\_service.dart, lib/pages/magnet/magnet\_controller.dart, lib/services/magnet/magnet\_subscription\_service.dart, lib/services/media/local\_media\_scanner.dart, lib/services/media/local\_media\_models.dart, lib/pages/media/media\_controller.dart, lib/services/storage/settings\_keys.dart, lib/pages/player/controller/player\_danmaku\_controller.dart, lib/pages/player/episode\_danmaku\_sheet.dart, lib/webview/video/video\_webview\_controller.dart, lib/webview/video/impl/video\_webview\_android\_impl.dart, lib/webview/video/impl/video\_webview\_impl.dart, lib/services/sync/history\_sync\_service.dart, lib/services/download/background\_download\_service.dart

## 2026.8.16

* 修复「仅 WiFi 下载」策略完全失效的问题：非 WiFi 分支先置 `_pausedByWifi = true` 再调用 `pause()`，而 `pause()` 同步段第一句就把该标记清除（注释本意只清用户手动暂停），导致 WiFi 恢复 / 关闭开关时按标记续传的分支永不命中、被策略暂停的任务永远卡在暂停态。抽出内部 `_pauseEntry()`（不清标记），策略暂停改走内部实现，`pause()` 仅用户手动暂停时清标记

  * 相关文件: lib/services/magnet/magnet\_download\_service.dart

* 修复磁盘空间自动暂停对新任务永不生效的问题：防重标记 `_diskSpaceCheckedTaskIds.add` 在 `applyTorrentStatus` 之前执行，而任务总量在 `applyTorrentStatus` 中才写入，元数据就绪首个 tick 里 `totalLength` 仍为 0，检查提前 return 但标记已下发导致会话内永不复查；磁盘空间校验移到 `applyTorrentStatus` 之后

  * 相关文件: lib/services/magnet/magnet\_download\_service.dart

* 修复倍速 ≠ 1 时弹幕系统性丢失或重复的问题：弹幕发射由固定 1s Timer 驱动且每次只采样当前秒桶，2x 时奇数秒整桶丢失、0.5x 时同秒重复发射、缓冲停滞时同秒反复发射。改为记录上次发射的源秒，逐 tick 补发区间内所有整秒弹幕（跳变超过 5 秒视为 seek 只发当前秒），弹幕池代次变化（seek / 偏移调整 / 弹幕重载）后重置追踪

  * 相关文件: lib/pages/player/player\_item.dart

* 修复弹幕轴检测结论写入全局持久设置、一次应用后永久自废的问题：推荐偏移改为按「bangumiID:episodeId」作用域存储（新增设置 `danmakuTimeOffsetByEpisode`，JSON 字符串），命中顺序为精确分集 → 同番剧（episodeId 未知）→ 全局手动偏移；单集检测结果不再作用于之后所有剧集，其他番剧 / 分集仍会自动触发检测

  * 相关文件: lib/services/storage/settings\_keys.dart, lib/pages/player/controller/player\_danmaku\_controller.dart, lib/pages/player/danmaku\_axis\_dialog.dart

* 修复同步关闭期间的删除不落墓碑、重新开启后已删历史复活的问题：`appendSafely` 新增 `requireEnabled` 参数，删除 / 清空的墓碑无条件写盘（同步开关只控制上传与高频进度事件），重新开启同步后事件日志中的墓碑会抑制远程快照 putAll 复活

  * 相关文件: lib/services/sync/history\_sync\_service.dart, lib/repositories/history\_repository.dart

* 修复占位历史迁移覆盖更新的真实历史的问题：`_repairPlaceholderHistories` 迁移前先按真实番剧查询既有条目，若匹配后用户已重新播放过（真实条目更新）则跳过迁移、直接丢弃占位条目，避免 `updateHistory` 无条件写 `lastWatchTime=now` 并用陈旧占位进度覆盖新历史；迁移路径改为迁移全部集数进度并按占位条目的 watch-state 收尾

  * 相关文件: lib/pages/media/media\_controller.dart

* 修复本地媒体库扫描单个无权限子目录（如 Android/data）导致整个根目录扫描失败清空媒体库的问题：`listSync(recursive: true)` 改为逐层手动遍历，单个子目录无权限 / 损坏只跳过该目录；同时以真实路径（resolveSymbolicLinks）去重，防止 Windows junction 符号链接环导致无限遍历

  * 相关文件: lib/services/media/local\_media\_scanner.dart

* 修复 Android 13+ 首次启动并发请求通知（POST\_NOTIFICATIONS）与媒体读取（READ\_MEDIA\_VIDEO）权限时后发弹窗被系统静默取消、媒体库首次扫描无权限的问题：`_initializeApp` 改为先 `await AppNotifications.init()` 完成通知权限请求，再进入 `mediaController.init()` 的媒体权限请求，串行化启动时的权限对话框

  * 相关文件: lib/pages/init\_page.dart

## 2026.8.16

* 开始维护当前分支版本号：项目版本由上游 `2.2.6+20206` 改为 `0.0.1+1`（`pubspec.yaml`、`lib/request/config/api_endpoints.dart` 同步为 `0.0.1`），README 顶部标注本分支基于上游 [2.2.6](https://github.com/Predidit/Kazumi/releases/tag/2.2.6) 版本开发

  * 相关文件: pubspec.yaml, lib/request/config/api\_endpoints.dart, README.md

## 2026.8.16

* 根据 CHANGELOG 同步更新 README：更新「项目特点」「开发状态」，将本地媒体库与磁力下载中已完成的开发项（外挂字幕、续播可视化、边下边播、队列调度、限速时段、仅 WiFi、自动搜刮入库、通知与后台保活、按番剧分组等）标记为已完成并调整待办项

  * 相关文件: README.md

## 2026.8.15

* 调整播放器侧边「弹幕」面板内容：新增当前弹幕池列表（按时间排序展示每条弹幕的时间、类型与内容，时间显示已计入弹幕时间轴偏移），并在面板顶部加入弹幕时间轴快速调整入口（±1/±10 秒、恢复无偏移、详细调整）

  * 相关文件: lib/pages/player/episode\_danmaku\_sheet.dart

## 2026.8.15

* 修复本地文件无法匹配弹弹弹幕库的问题：`matchLocalFile` 向 `/api/v2/match` 发送的 `fileName` 此前带扩展名（`p.basename`），与弹弹 Play 官方 API 规范（fileName 不包含文件夹名与扩展名）不符，导致哈希匹配与文件名模糊检索均失配；改回 `p.basenameWithoutExtension`。同时不再静默吞掉 match 接口的业务错误响应（200 + success=false），改为记录 errorCode/errorMessage 日志便于定位

  * 相关文件: lib/request/apis/danmaku\_api.dart

* 将用户反馈的文件名 `[smzase&LoliHouse] Otome Kaijuu Carameliser - 06 [WebRip 1080p HEVC-10bit AAC ASSx2].mkv` 加入解析回归测试（集数=6、番剧名=Otome Kaijuu Carameliser）

  * 相关文件: test/local\_episode\_parser\_test.dart

## 2026.8.15

* 修复媒体库播放历史未正确显示对应番剧的问题：`MediaController.getFileScrapeInfo` 原实现用文件全路径查询文件夹级搜刮结果（`scrapeResults` 以文件夹/逻辑分组路径为 key），永远匹配不上，导致播放本地文件时历史以占位番剧（id<=0）落库；现改为按文件所在文件夹路径查询，并让 media\_library\_page 中所有调用点传入对应文件夹

  * 相关文件: lib/pages/media/media\_controller.dart, lib/pages/media/media\_library\_page.dart

* 新增存量占位历史自动迁移：媒体库扫描后 `_repairPlaceholderHistories()` 将已以占位番剧落库的本地历史条目（id<=0 且带本地文件路径）迁移到真实番剧条目下，仅当所在文件夹搜刮结果为真实 Bangumi 匹配（bangumiId 非空）时执行，保留播放进度与集数

  * 相关文件: lib/pages/media/media\_controller.dart

* 新增回归测试覆盖「按文件夹路径搜刮回退」与「占位历史扫描后迁移」

  * 相关文件: test/media\_history\_repair\_test.dart

## 2026.8.14

* 时间表页新增「仅显示日漫」过滤选项：`BangumiItem` 新增 `isJapaneseAnime` 判定（按标签命中「日本」），只保留日本动画、过滤国漫等其他地区条目；选项持久化保存，过滤器面板计数同步；同时重新生成 MobX codegen（新增 observable/action 未进 codegen 导致开关无响应）

  * 相关文件: lib/modules/bangumi/bangumi\_item.dart, lib/services/storage/settings\_keys.dart, lib/repositories/collect\_repository.dart, lib/pages/timeline/timeline\_controller.dart, lib/pages/timeline/timeline\_controller.g.dart, lib/pages/timeline/timeline\_page.dart

## 2026.8.14

* 番剧详情页直接展示本地资源：抽出共享组件 `LocalEpisodesSection`（媒体库文件 + 离线缓存剧集 + 搜索磁力补集 / 打开媒体库），在详情页「概览」tab 底部直接显示；「开始观看」弹窗（SourceSheet）不再包含本地资源区块，仅保留在线播放源检索；顺带修复原弹窗中集数 chips 的乱码文案

  * 相关文件: lib/pages/info/local\_episodes\_section.dart, lib/pages/info/info\_tabview\.dart, lib/pages/info/source\_sheet.dart

## 2026.8.14

* RSS 订阅列表显示番剧封面图：`MagnetSubscription` 新增持久化 `coverUrl` 字段，添加/编辑订阅保存时按名称搜索 Bangumi 解析封面；旧订阅在列表加载时懒回填封面（去重、失败静默），无封面时回退原有图标

  * 相关文件: lib/services/magnet/magnet\_models.dart, lib/services/magnet/magnet\_subscription\_service.dart, lib/pages/magnet/magnet\_controller.dart, lib/pages/magnet/magnet\_page.dart

* 调整 RSS 订阅编辑页：保存按钮从顶部栏移到页面底部，改为通栏大按钮

* 磁力搜索页字幕组筛选选择器不再请求 Animes Garden teams 接口，改为列出当前搜索结果中出现过的字幕组（去重排序），仍支持搜索 / 手动输入 / 清除不限

  * 相关文件: lib/pages/magnet/magnet\_page.dart

## 2026.8.14

* 修复第二轮代码审查发现的问题（详见 `.docs/CODE_REVIEW_2026.8.14.md` 第二轮复核）：

  * WebDAV 历史同步不再删除本地媒体库 / 边下边播历史（stale 判定排除这两类条目）；边下边播流 HEAD 恢复校验只接受 2xx（404/403 视为失效并引导从下载页重新开始）

  * 磁力边下边播流生命周期：维护在播任务集合，完成/队列降级/WiFi 暂停豁免在播任务（完成后保留引擎句柄、流停止后补做移除），手动暂停先停流，播放页退出自动停止流服务器（释放端口与预读缓存）

  * 磁力启动不再轰炸通知：启动首帧 onChanged 仅初始化状态快照；删除任务时清理 `_lastTaskStatuses` 等防重入集合

  * 自动搜刮/入库只对本会话内进入 complete/seeding 终态的任务生效（不再每次启动对历史任务重跑并弹存储权限）；无读取权限时自动入库静默跳过；入库失败会话内不再每 2s 无限重试；搜刮网络错误不再误标记「待确认」，无法确定落盘文件时终止重试循环

  * 限速时段 0 改为「不限」语义（与设置文案一致）；设置变更立即失效限速缓存；关闭「仅 WiFi」后恢复被策略暂停的任务；手动暂停清除 WiFi 暂停标记

  * 排队任务引擎报错时状态流转为 error（不再恒显示「排队中」）；元数据就绪磁盘空间校验改为会话级去重（重启后重新校验）

  * Android 存储权限结果按 requestCode 队列化（并发请求不再覆盖挂起）；前台下载服务 acquire/release 串行化（不再零租约常驻 / 双次启动）

  * 磁力缺集检测改为「已落盘文件」口径（区分种子全量清单，已入库任务豁免）；体积解析支持千分位；临时 .torrent 文件用后即删

  * 播放页本地角标：预构建「集数→文件」映射（原逐集全库线性扫描），按剧集名称解析集数匹配（多季列表不再错标），切换本地播放前先停止旧播放器

  * 历史恢复本地播放补传 bangumiSyncId（本地看完联动 Bangumi 进度恢复生效）；`MediaResumePoint` 实现 `==`（续播点缓存不再每帧重建触发观察者）

  * 搜索页本地提示 / 追番角标改为批量单次遍历全库，追番角标统一为文件级口径；`sub-auto=fuzzy` 外挂字幕自动加载仅本地播放生效；更正边下边播「不写历史」注释

  * 相关文件: lib/services/sync/history\_sync\_service.dart, lib/services/player/history\_playback\_service.dart, lib/services/magnet/magnet\_download\_service.dart, lib/pages/magnet/magnet\_controller.dart, lib/pages/magnet/magnet\_page.dart, lib/pages/download/background\_download\_service.dart, lib/pages/media/media\_controller.dart, lib/pages/video/video\_page.dart, lib/pages/video/video\_playback\_args.dart, lib/pages/video/video\_controller.dart, lib/pages/search/search\_page.dart, lib/pages/collect/collect\_page.dart, lib/services/media/local\_availability\_service.dart, lib/pages/player/controller/player\_playback\_controller.dart, android/app/src/main/kotlin/com/example/kazumi/MainActivity.kt, .docs/CODE\_REVIEW\_2026.8.14.md

## 2026.8.14

* 对当日三批变更完成代码审查并输出报告

  * 相关文件: .docs/CODE\_REVIEW\_2026.8.14.md

## 2026.8.14

* 同步上游修复：Windows 平台解析到 m3u8 源时强制 HLS 解封装

  * 新增 `VideoSourceFormat` 枚举与 `VideoParserEvent` 事件类型，webview 解析器在 Windows 检出 m3u8 地址时标记 `hls`，经 `VideoSource.format` → `PlaybackInitParams.videoSourceFormat` 传递到播放器，打开媒体前执行 `demuxer-lavf-format=hls`，规避 libmpv 自动探测失败导致的无法播放/卡死

  * 相关文件: lib/services/video\_source/video\_source\_format.dart, lib/services/video\_source/video\_source\_service.dart, lib/services/video\_source/webview\_video\_source\_service.dart, lib/webview/video/video\_webview\_controller.dart, lib/webview/video/impl/video\_webview\_impl.dart, lib/webview/video/impl/video\_webview\_android\_impl.dart, lib/webview/video/impl/video\_webview\_apple\_impl.dart, lib/webview/video/impl/video\_webview\_linux\_impl.dart, lib/webview/video/impl/video\_webview\_windows\_impl.dart, lib/pages/player/controller/player\_models.dart, lib/pages/player/controller/player\_playback\_controller.dart, lib/pages/player/player\_controller.dart, lib/pages/video/video\_controller.dart

## 2026.8.14

* 围绕磁力下载与本地媒体库做全面体验增强（仅 Windows / Android）：

  * 详情页「开始观看」面板新增「本地播放」区块：按 Bangumi subject ID 汇总媒体库已匹配文件与离线缓存完成的剧集，按目录/插件分组展示集数 chips 直接播放（携带 Bangumi 关联，弹幕/历史/进度联动正常），并提供「搜索磁力补集」「打开媒体库」入口；新增 `LocalAvailabilityService`（core\_module 单例）供各页面复用

  * 播放页剧集列表新增本地媒体库角标：在线播放时若媒体库已匹配同集文件，显示文件夹图标，点击直接切换为本地播放

  * 追番收藏网格新增「本地N」「缓存N」角标（按 bangumiId 汇总媒体库文件数与已完成缓存集数）

  * 磁力下载页新增「按番剧分组」视图（设置 `magnetGroupDownloads`）：同番任务聚合为一组，组头支持「缺集」检测（对比 Bangumi 正片集数，点击缺失集数跳转磁力搜索）；分组状态持久化，下载中心与磁力页共享

  * 磁力任务「已入库」状态可视化：自动入库完成的任务显示绿色「已入库」标记，删除任务时提示文件已移入媒体库、删除仅移除记录

  * 磁力边下边播写入历史记录（adapterName=magnet-stream）：恢复播放前对流 URL 做 HEAD 可达性校验（2 秒超时），失效时提示从下载页重新开始；边下边播与本地媒体条目均不参与 WebDAV/设备历史同步

  * 提交磁力下载前磁盘空间检查（设置 `magnetDiskSpaceCheck`，默认开启）：解析资源体积与目标分区剩余空间，不足时弹窗确认

  * 媒体库未匹配卡片生成视频首帧缩略图（设置 `localMediaThumbnails`，默认开启；复用 `VideoFrameExtractor`，缓存键含文件修改时间，变化自动重生成）

  * Windows 媒体库目录实时监听（设置 `localMediaWatchFolder`，默认开启；`package:watcher` 递归监听 + 1.5s 去抖自动重扫），Android 保留定时轮询

  * 媒体库多季目录排序：同一番剧的多个季目录按解析季数升序排列（`S02`/`第二季` 等）

  * 历史卡片来源标签细化（在线/缓存/本地/边下边播）；本地文件缺失时提供「去详情页 / 搜索磁力」引导

  * 本地媒体库最后一集播完引导：弹窗提供「去详情页在线播放」「搜索磁力补集」（每个剧集仅提示一次）；在线/流播放最后一集播完给出轻量提示

  * 搜索页本地整合提示：搜索结果命中本地媒体库时顶部横幅显示匹配数量，点击直达媒体库

  * 相关文件: lib/core\_module.dart, lib/services/media/local\_availability\_service.dart, lib/services/media/media\_folder\_watcher.dart, lib/pages/media/media\_controller.dart, lib/pages/media/media\_controller.g.dart, lib/pages/media/media\_library\_page.dart, lib/pages/info/source\_sheet.dart, lib/pages/collect/collect\_page.dart, lib/pages/video/video\_page.dart, lib/pages/video/video\_controller.dart, lib/pages/video/video\_controller.g.dart, lib/pages/video/video\_playback\_args.dart, lib/pages/magnet/magnet\_page.dart, lib/pages/magnet/magnet\_controller.dart, lib/pages/magnet/magnet\_controller.g.dart, lib/pages/settings/magnet\_settings.dart, lib/services/storage/settings\_keys.dart, lib/pages/player/player\_item.dart, lib/pages/search/search\_page.dart, lib/bean/card/bangumi\_history\_card.dart, lib/modules/history/history\_module.dart, lib/modules/history/history\_sync.dart, lib/services/sync/history\_sync\_service.dart, lib/services/player/history\_playback\_service.dart, pubspec.yaml, pubspec.lock

## 2026.8.14

* 磁力下载与本地媒体库功能增强（路线图见 `static/doc/MAGNET_MEDIA_ROADMAP.md`）

  * 订阅/手动任务下载完成后自动搜刮番剧并入库：新增 `magnetAutoScrapeOnComplete`（默认开启）与 `magnetAutoImportConfidence`（默认 0.7）设置；任务新增 `scrapeConfidence` / `scrapeAttempted` 字段；未命中标记「待确认」，下载页支持「匹配番剧」（搜索 Bangumi 手动关联）与「重新搜刮」

  * Android 端本地媒体库改为应用内播放（弹幕/历史/续播/Bangumi 进度联动）：媒体库两处播放入口（卡片点击与文件操作面板）Windows/Android 统一走 `/video/`；新增 `AndroidStorageAccess` 服务与 MainActivity 存储权限通道（READ\_MEDIA\_VIDEO / READ\_EXTERNAL\_STORAGE 运行时申请、MANAGE\_EXTERNAL\_STORAGE 引导入口），启动扫描与添加文件夹时自动确保读取权限

  * 下载并发限制与队列调度：新增 `magnetMaxActiveDownloads`（默认 3，0 不限）；新状态 `queued`（排队中），纯函数 `computeQueueChanges` 按添加顺序自动提升/降级，重启重挂、手动暂停恢复后自动重算；任务菜单新增「立即开始」

  * 边下边播：使用 vendored libtorrent fork 内置的 TorrServer 风格 HTTP 流服务器；任务菜单「边下边播」（可流式文件选择 → 启动流 → 播放页）；新增 `MagnetStreamVideoPlaybackArgs` 与播放器 `isStreamMode`（弹幕按文件名集数+标题匹配，不写历史）；暂停/排队任务自动先恢复；删除任务停止关联流

  * 下载完成/失败系统通知：新增 `AppNotifications` 服务（Android: awesome\_notifications 含通道与 Android 13+ 权限申请；Windows: local\_notifier/WinToast），任务状态跳变到完成/错误时触发一次，启动时初始化

  * Android 磁力下载后台存活：`BackgroundDownloadService` 重构为租约制共享前台服务（`http` / `magnet` 双租约，全部释放才停服，通知内容按最后更新租约渲染、释放时回退）；磁力任务下载中自动持有并每 2s 节流更新进度通知；通知栏「暂停全部」联动磁力任务

  * 错误重试与元数据超时重试：新增「重试」（重挂源、保留磁盘数据）；元数据 10 分钟超时自动重试（最多 5 次后标记错误），进入真实下载/校验后复位计数

  * 限速时段：新增 `magnetScheduledLimitEnabled` / Start / End / `magnetScheduledLimitKb` 设置（支持跨天窗口），策略调度器每分钟覆盖全局下载限速

  * 仅 WiFi 下载：新增 `magnetWifiOnly` 设置（connectivity\_plus 判定网络类型，非 WiFi/有线自动暂停下载任务、恢复后自动继续）

  * 磁盘空间检查：新增 `DiskSpace` 工具（Android 复用 StatFs MethodChannel，Windows 用 win32 GetDiskFreeSpaceExW）；添加任务前可用空间 <300MB 告警，元数据首次就绪时按真实大小校验、不足（余量 200MB）自动暂停

  * 手动文件校验：任务菜单「校验文件」（引擎 force\_recheck，复用 fork 的 recheckTorrent），校验期间 UI 显示「校验进度中」

  * 剪贴板磁力识别：进入磁力页检测剪贴板 `magnet:?xt=urn:btih:` 与 `.torrent` 直链，弹窗一键加入下载（与已有任务同源去重）

  * 已完成记录清理：已完成筛选下新增「清除已完成记录」（确认后移除记录、保留磁盘文件）

  * 下载列表搜索：任务搜索框（按标题/文件名/番剧名过滤，与状态筛选组合）

  * 媒体库续播状态可视化：新增 `MediaResumePoint` 与续播点缓存（按 episodePageUrl 精确匹配本地播放历史，随历史变化自动刷新）；网格封面「续播 EPx · 时间」角标点击直达续播；番剧视图分组头部「上次看到…」+「续播」按钮；续播由播放器历史机制自动恢复进度

  * 外挂字幕自动加载：播放器启用 mpv `sub-auto=fuzzy`，自动加载与本地视频同目录的外挂字幕（.ass/.srt 等）

  * 特别篇分类：新增 `classifyLocalEpisode` / `localEpisodeKindLabel`（正片 / SP / 剧场版 / 特典），媒体库文件列表对非正片显示分类徽章

  * 媒体库搜索：顶栏搜索开关，按番剧名/文件夹名/文件名过滤三种视图

  * 全库空间统计：统计栏展示全部视频总占用

  * 自动重扫：媒体库页打开期间每 5 分钟自动重扫 + 应用回到前台（含桌面窗口聚焦）时重扫

  * 全集看完自动标记「看过」：Bangumi 进度同步追平正片总量后把收藏状态更新为 type=2，按 subject 幂等去重

  * 相关文件: static/doc/MAGNET\_MEDIA\_ROADMAP.md, lib/services/magnet/magnet\_download\_service.dart, lib/services/magnet/magnet\_subscription\_service.dart, lib/pages/magnet/magnet\_controller.dart, lib/pages/magnet/magnet\_page.dart, lib/pages/settings/magnet\_settings.dart, lib/services/storage/settings\_keys.dart, lib/pages/media/media\_controller.dart, lib/pages/media/media\_library\_page.dart, lib/services/media/local\_media\_models.dart, lib/services/media/local\_media\_scanner.dart, lib/services/media/media\_scraper.dart, lib/services/media/bangumi\_progress\_sync\_service.dart, lib/services/platform/android\_storage\_access.dart, lib/services/notification/app\_notifications.dart, lib/services/download/background\_download\_service.dart, lib/pages/download/download\_controller.dart, lib/utils/disk\_space.dart, lib/utils/local\_episode\_parser.dart, lib/pages/video/video\_controller.dart, lib/pages/video/video\_page.dart, lib/pages/video/video\_playback\_args.dart, lib/pages/player/player\_item.dart, lib/pages/player/controller/player\_playback\_controller.dart, lib/pages/init\_page.dart, android/app/src/main/AndroidManifest.xml, android/app/src/main/kotlin/com/example/kazumi/MainActivity.kt, pubspec.yaml, test/magnet\_download\_entry\_test.dart, test/local\_episode\_parser\_test.dart

* 新增 AGENTS.md，规定项目修改规则（平台约束、修改日志、验证流程）

  * 相关文件: AGENTS.md

