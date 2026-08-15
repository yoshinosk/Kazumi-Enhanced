# 修改日志

每次修改后在此文件**最顶部**追加日志，格式见 `AGENTS.md`。

## 2026.8.15

- 调整播放器侧边「弹幕」面板内容：新增当前弹幕池列表（按时间排序展示每条弹幕的时间、类型与内容，时间显示已计入弹幕时间轴偏移），并在面板顶部加入弹幕时间轴快速调整入口（±1/±10 秒、恢复无偏移、详细调整）
  - 相关文件: lib/pages/player/episode_danmaku_sheet.dart

## 2026.8.15

- 修复本地文件无法匹配弹弹弹幕库的问题：`matchLocalFile` 向 `/api/v2/match` 发送的 `fileName` 此前带扩展名（`p.basename`），与弹弹 Play 官方 API 规范（fileName 不包含文件夹名与扩展名）不符，导致哈希匹配与文件名模糊检索均失配；改回 `p.basenameWithoutExtension`。同时不再静默吞掉 match 接口的业务错误响应（200 + success=false），改为记录 errorCode/errorMessage 日志便于定位
  - 相关文件: lib/request/apis/danmaku_api.dart
- 将用户反馈的文件名 `[smzase&LoliHouse] Otome Kaijuu Carameliser - 06 [WebRip 1080p HEVC-10bit AAC ASSx2].mkv` 加入解析回归测试（集数=6、番剧名=Otome Kaijuu Carameliser）
  - 相关文件: test/local_episode_parser_test.dart

## 2026.8.15

- 修复媒体库播放历史未正确显示对应番剧的问题：`MediaController.getFileScrapeInfo` 原实现用文件全路径查询文件夹级搜刮结果（`scrapeResults` 以文件夹/逻辑分组路径为 key），永远匹配不上，导致播放本地文件时历史以占位番剧（id<=0）落库；现改为按文件所在文件夹路径查询，并让 media_library_page 中所有调用点传入对应文件夹
  - 相关文件: lib/pages/media/media_controller.dart, lib/pages/media/media_library_page.dart
- 新增存量占位历史自动迁移：媒体库扫描后 `_repairPlaceholderHistories()` 将已以占位番剧落库的本地历史条目（id<=0 且带本地文件路径）迁移到真实番剧条目下，仅当所在文件夹搜刮结果为真实 Bangumi 匹配（bangumiId 非空）时执行，保留播放进度与集数
  - 相关文件: lib/pages/media/media_controller.dart
- 新增回归测试覆盖「按文件夹路径搜刮回退」与「占位历史扫描后迁移」
  - 相关文件: test/media_history_repair_test.dart

## 2026.8.14

- 时间表页新增「仅显示日漫」过滤选项：`BangumiItem` 新增 `isJapaneseAnime` 判定（按标签命中「日本」），只保留日本动画、过滤国漫等其他地区条目；选项持久化保存，过滤器面板计数同步；同时重新生成 MobX codegen（新增 observable/action 未进 codegen 导致开关无响应）
  - 相关文件: lib/modules/bangumi/bangumi_item.dart, lib/services/storage/settings_keys.dart, lib/repositories/collect_repository.dart, lib/pages/timeline/timeline_controller.dart, lib/pages/timeline/timeline_controller.g.dart, lib/pages/timeline/timeline_page.dart

## 2026.8.14

- 番剧详情页直接展示本地资源：抽出共享组件 `LocalEpisodesSection`（媒体库文件 + 离线缓存剧集 + 搜索磁力补集 / 打开媒体库），在详情页「概览」tab 底部直接显示；「开始观看」弹窗（SourceSheet）不再包含本地资源区块，仅保留在线播放源检索；顺带修复原弹窗中集数 chips 的乱码文案
  - 相关文件: lib/pages/info/local_episodes_section.dart, lib/pages/info/info_tabview.dart, lib/pages/info/source_sheet.dart

## 2026.8.14

- RSS 订阅列表显示番剧封面图：`MagnetSubscription` 新增持久化 `coverUrl` 字段，添加/编辑订阅保存时按名称搜索 Bangumi 解析封面；旧订阅在列表加载时懒回填封面（去重、失败静默），无封面时回退原有图标
  - 相关文件: lib/services/magnet/magnet_models.dart, lib/services/magnet/magnet_subscription_service.dart, lib/pages/magnet/magnet_controller.dart, lib/pages/magnet/magnet_page.dart
- 调整 RSS 订阅编辑页：保存按钮从顶部栏移到页面底部，改为通栏大按钮
- 磁力搜索页字幕组筛选选择器不再请求 Animes Garden teams 接口，改为列出当前搜索结果中出现过的字幕组（去重排序），仍支持搜索 / 手动输入 / 清除不限
  - 相关文件: lib/pages/magnet/magnet_page.dart

## 2026.8.14

- 修复第二轮代码审查发现的问题（详见 `.docs/CODE_REVIEW_2026.8.14.md` 第二轮复核）：
  - WebDAV 历史同步不再删除本地媒体库 / 边下边播历史（stale 判定排除这两类条目）；边下边播流 HEAD 恢复校验只接受 2xx（404/403 视为失效并引导从下载页重新开始）
  - 磁力边下边播流生命周期：维护在播任务集合，完成/队列降级/WiFi 暂停豁免在播任务（完成后保留引擎句柄、流停止后补做移除），手动暂停先停流，播放页退出自动停止流服务器（释放端口与预读缓存）
  - 磁力启动不再轰炸通知：启动首帧 onChanged 仅初始化状态快照；删除任务时清理 `_lastTaskStatuses` 等防重入集合
  - 自动搜刮/入库只对本会话内进入 complete/seeding 终态的任务生效（不再每次启动对历史任务重跑并弹存储权限）；无读取权限时自动入库静默跳过；入库失败会话内不再每 2s 无限重试；搜刮网络错误不再误标记「待确认」，无法确定落盘文件时终止重试循环
  - 限速时段 0 改为「不限」语义（与设置文案一致）；设置变更立即失效限速缓存；关闭「仅 WiFi」后恢复被策略暂停的任务；手动暂停清除 WiFi 暂停标记
  - 排队任务引擎报错时状态流转为 error（不再恒显示「排队中」）；元数据就绪磁盘空间校验改为会话级去重（重启后重新校验）
  - Android 存储权限结果按 requestCode 队列化（并发请求不再覆盖挂起）；前台下载服务 acquire/release 串行化（不再零租约常驻 / 双次启动）
  - 磁力缺集检测改为「已落盘文件」口径（区分种子全量清单，已入库任务豁免）；体积解析支持千分位；临时 .torrent 文件用后即删
  - 播放页本地角标：预构建「集数→文件」映射（原逐集全库线性扫描），按剧集名称解析集数匹配（多季列表不再错标），切换本地播放前先停止旧播放器
  - 历史恢复本地播放补传 bangumiSyncId（本地看完联动 Bangumi 进度恢复生效）；`MediaResumePoint` 实现 `==`（续播点缓存不再每帧重建触发观察者）
  - 搜索页本地提示 / 追番角标改为批量单次遍历全库，追番角标统一为文件级口径；`sub-auto=fuzzy` 外挂字幕自动加载仅本地播放生效；更正边下边播「不写历史」注释
  - 相关文件: lib/services/sync/history_sync_service.dart, lib/services/player/history_playback_service.dart, lib/services/magnet/magnet_download_service.dart, lib/pages/magnet/magnet_controller.dart, lib/pages/magnet/magnet_page.dart, lib/pages/download/background_download_service.dart, lib/pages/media/media_controller.dart, lib/pages/video/video_page.dart, lib/pages/video/video_playback_args.dart, lib/pages/video/video_controller.dart, lib/pages/search/search_page.dart, lib/pages/collect/collect_page.dart, lib/services/media/local_availability_service.dart, lib/pages/player/controller/player_playback_controller.dart, android/app/src/main/kotlin/com/example/kazumi/MainActivity.kt, .docs/CODE_REVIEW_2026.8.14.md

## 2026.8.14

- 对当日三批变更完成代码审查并输出报告
  - 相关文件: .docs/CODE_REVIEW_2026.8.14.md

## 2026.8.14

- 同步上游修复：Windows 平台解析到 m3u8 源时强制 HLS 解封装
  - 新增 `VideoSourceFormat` 枚举与 `VideoParserEvent` 事件类型，webview 解析器在 Windows 检出 m3u8 地址时标记 `hls`，经 `VideoSource.format` → `PlaybackInitParams.videoSourceFormat` 传递到播放器，打开媒体前执行 `demuxer-lavf-format=hls`，规避 libmpv 自动探测失败导致的无法播放/卡死
  - 相关文件: lib/services/video_source/video_source_format.dart, lib/services/video_source/video_source_service.dart, lib/services/video_source/webview_video_source_service.dart, lib/webview/video/video_webview_controller.dart, lib/webview/video/impl/video_webview_impl.dart, lib/webview/video/impl/video_webview_android_impl.dart, lib/webview/video/impl/video_webview_apple_impl.dart, lib/webview/video/impl/video_webview_linux_impl.dart, lib/webview/video/impl/video_webview_windows_impl.dart, lib/pages/player/controller/player_models.dart, lib/pages/player/controller/player_playback_controller.dart, lib/pages/player/player_controller.dart, lib/pages/video/video_controller.dart

## 2026.8.14

- 围绕磁力下载与本地媒体库做全面体验增强（仅 Windows / Android）：
  - 详情页「开始观看」面板新增「本地播放」区块：按 Bangumi subject ID 汇总媒体库已匹配文件与离线缓存完成的剧集，按目录/插件分组展示集数 chips 直接播放（携带 Bangumi 关联，弹幕/历史/进度联动正常），并提供「搜索磁力补集」「打开媒体库」入口；新增 `LocalAvailabilityService`（core_module 单例）供各页面复用
  - 播放页剧集列表新增本地媒体库角标：在线播放时若媒体库已匹配同集文件，显示文件夹图标，点击直接切换为本地播放
  - 追番收藏网格新增「本地N」「缓存N」角标（按 bangumiId 汇总媒体库文件数与已完成缓存集数）
  - 磁力下载页新增「按番剧分组」视图（设置 `magnetGroupDownloads`）：同番任务聚合为一组，组头支持「缺集」检测（对比 Bangumi 正片集数，点击缺失集数跳转磁力搜索）；分组状态持久化，下载中心与磁力页共享
  - 磁力任务「已入库」状态可视化：自动入库完成的任务显示绿色「已入库」标记，删除任务时提示文件已移入媒体库、删除仅移除记录
  - 磁力边下边播写入历史记录（adapterName=magnet-stream）：恢复播放前对流 URL 做 HEAD 可达性校验（2 秒超时），失效时提示从下载页重新开始；边下边播与本地媒体条目均不参与 WebDAV/设备历史同步
  - 提交磁力下载前磁盘空间检查（设置 `magnetDiskSpaceCheck`，默认开启）：解析资源体积与目标分区剩余空间，不足时弹窗确认
  - 媒体库未匹配卡片生成视频首帧缩略图（设置 `localMediaThumbnails`，默认开启；复用 `VideoFrameExtractor`，缓存键含文件修改时间，变化自动重生成）
  - Windows 媒体库目录实时监听（设置 `localMediaWatchFolder`，默认开启；`package:watcher` 递归监听 + 1.5s 去抖自动重扫），Android 保留定时轮询
  - 媒体库多季目录排序：同一番剧的多个季目录按解析季数升序排列（`S02`/`第二季` 等）
  - 历史卡片来源标签细化（在线/缓存/本地/边下边播）；本地文件缺失时提供「去详情页 / 搜索磁力」引导
  - 本地媒体库最后一集播完引导：弹窗提供「去详情页在线播放」「搜索磁力补集」（每个剧集仅提示一次）；在线/流播放最后一集播完给出轻量提示
  - 搜索页本地整合提示：搜索结果命中本地媒体库时顶部横幅显示匹配数量，点击直达媒体库
  - 相关文件: lib/core_module.dart, lib/services/media/local_availability_service.dart, lib/services/media/media_folder_watcher.dart, lib/pages/media/media_controller.dart, lib/pages/media/media_controller.g.dart, lib/pages/media/media_library_page.dart, lib/pages/info/source_sheet.dart, lib/pages/collect/collect_page.dart, lib/pages/video/video_page.dart, lib/pages/video/video_controller.dart, lib/pages/video/video_controller.g.dart, lib/pages/video/video_playback_args.dart, lib/pages/magnet/magnet_page.dart, lib/pages/magnet/magnet_controller.dart, lib/pages/magnet/magnet_controller.g.dart, lib/pages/settings/magnet_settings.dart, lib/services/storage/settings_keys.dart, lib/pages/player/player_item.dart, lib/pages/search/search_page.dart, lib/bean/card/bangumi_history_card.dart, lib/modules/history/history_module.dart, lib/modules/history/history_sync.dart, lib/services/sync/history_sync_service.dart, lib/services/player/history_playback_service.dart, pubspec.yaml, pubspec.lock

## 2026.8.14

- 磁力下载与本地媒体库功能增强（路线图见 `static/doc/MAGNET_MEDIA_ROADMAP.md`）
  - 订阅/手动任务下载完成后自动搜刮番剧并入库：新增 `magnetAutoScrapeOnComplete`（默认开启）与 `magnetAutoImportConfidence`（默认 0.7）设置；任务新增 `scrapeConfidence` / `scrapeAttempted` 字段；未命中标记「待确认」，下载页支持「匹配番剧」（搜索 Bangumi 手动关联）与「重新搜刮」
  - Android 端本地媒体库改为应用内播放（弹幕/历史/续播/Bangumi 进度联动）：媒体库两处播放入口（卡片点击与文件操作面板）Windows/Android 统一走 `/video/`；新增 `AndroidStorageAccess` 服务与 MainActivity 存储权限通道（READ_MEDIA_VIDEO / READ_EXTERNAL_STORAGE 运行时申请、MANAGE_EXTERNAL_STORAGE 引导入口），启动扫描与添加文件夹时自动确保读取权限
  - 下载并发限制与队列调度：新增 `magnetMaxActiveDownloads`（默认 3，0 不限）；新状态 `queued`（排队中），纯函数 `computeQueueChanges` 按添加顺序自动提升/降级，重启重挂、手动暂停恢复后自动重算；任务菜单新增「立即开始」
  - 边下边播：使用 vendored libtorrent fork 内置的 TorrServer 风格 HTTP 流服务器；任务菜单「边下边播」（可流式文件选择 → 启动流 → 播放页）；新增 `MagnetStreamVideoPlaybackArgs` 与播放器 `isStreamMode`（弹幕按文件名集数+标题匹配，不写历史）；暂停/排队任务自动先恢复；删除任务停止关联流
  - 下载完成/失败系统通知：新增 `AppNotifications` 服务（Android: awesome_notifications 含通道与 Android 13+ 权限申请；Windows: local_notifier/WinToast），任务状态跳变到完成/错误时触发一次，启动时初始化
  - Android 磁力下载后台存活：`BackgroundDownloadService` 重构为租约制共享前台服务（`http` / `magnet` 双租约，全部释放才停服，通知内容按最后更新租约渲染、释放时回退）；磁力任务下载中自动持有并每 2s 节流更新进度通知；通知栏「暂停全部」联动磁力任务
  - 错误重试与元数据超时重试：新增「重试」（重挂源、保留磁盘数据）；元数据 10 分钟超时自动重试（最多 5 次后标记错误），进入真实下载/校验后复位计数
  - 限速时段：新增 `magnetScheduledLimitEnabled` / Start / End / `magnetScheduledLimitKb` 设置（支持跨天窗口），策略调度器每分钟覆盖全局下载限速
  - 仅 WiFi 下载：新增 `magnetWifiOnly` 设置（connectivity_plus 判定网络类型，非 WiFi/有线自动暂停下载任务、恢复后自动继续）
  - 磁盘空间检查：新增 `DiskSpace` 工具（Android 复用 StatFs MethodChannel，Windows 用 win32 GetDiskFreeSpaceExW）；添加任务前可用空间 <300MB 告警，元数据首次就绪时按真实大小校验、不足（余量 200MB）自动暂停
  - 手动文件校验：任务菜单「校验文件」（引擎 force_recheck，复用 fork 的 recheckTorrent），校验期间 UI 显示「校验进度中」
  - 剪贴板磁力识别：进入磁力页检测剪贴板 `magnet:?xt=urn:btih:` 与 `.torrent` 直链，弹窗一键加入下载（与已有任务同源去重）
  - 已完成记录清理：已完成筛选下新增「清除已完成记录」（确认后移除记录、保留磁盘文件）
  - 下载列表搜索：任务搜索框（按标题/文件名/番剧名过滤，与状态筛选组合）
  - 媒体库续播状态可视化：新增 `MediaResumePoint` 与续播点缓存（按 episodePageUrl 精确匹配本地播放历史，随历史变化自动刷新）；网格封面「续播 EPx · 时间」角标点击直达续播；番剧视图分组头部「上次看到…」+「续播」按钮；续播由播放器历史机制自动恢复进度
  - 外挂字幕自动加载：播放器启用 mpv `sub-auto=fuzzy`，自动加载与本地视频同目录的外挂字幕（.ass/.srt 等）
  - 特别篇分类：新增 `classifyLocalEpisode` / `localEpisodeKindLabel`（正片 / SP / 剧场版 / 特典），媒体库文件列表对非正片显示分类徽章
  - 媒体库搜索：顶栏搜索开关，按番剧名/文件夹名/文件名过滤三种视图
  - 全库空间统计：统计栏展示全部视频总占用
  - 自动重扫：媒体库页打开期间每 5 分钟自动重扫 + 应用回到前台（含桌面窗口聚焦）时重扫
  - 全集看完自动标记「看过」：Bangumi 进度同步追平正片总量后把收藏状态更新为 type=2，按 subject 幂等去重
  - 相关文件: static/doc/MAGNET_MEDIA_ROADMAP.md, lib/services/magnet/magnet_download_service.dart, lib/services/magnet/magnet_subscription_service.dart, lib/pages/magnet/magnet_controller.dart, lib/pages/magnet/magnet_page.dart, lib/pages/settings/magnet_settings.dart, lib/services/storage/settings_keys.dart, lib/pages/media/media_controller.dart, lib/pages/media/media_library_page.dart, lib/services/media/local_media_models.dart, lib/services/media/local_media_scanner.dart, lib/services/media/media_scraper.dart, lib/services/media/bangumi_progress_sync_service.dart, lib/services/platform/android_storage_access.dart, lib/services/notification/app_notifications.dart, lib/services/download/background_download_service.dart, lib/pages/download/download_controller.dart, lib/utils/disk_space.dart, lib/utils/local_episode_parser.dart, lib/pages/video/video_controller.dart, lib/pages/video/video_page.dart, lib/pages/video/video_playback_args.dart, lib/pages/player/player_item.dart, lib/pages/player/controller/player_playback_controller.dart, lib/pages/init_page.dart, android/app/src/main/AndroidManifest.xml, android/app/src/main/kotlin/com/example/kazumi/MainActivity.kt, pubspec.yaml, test/magnet_download_entry_test.dart, test/local_episode_parser_test.dart

- 新增 AGENTS.md，规定项目修改规则（平台约束、修改日志、验证流程）
  - 相关文件: AGENTS.md