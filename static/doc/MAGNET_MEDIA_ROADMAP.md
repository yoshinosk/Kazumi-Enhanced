# 磁力下载 & 本地媒体库 改进路线图

> 本文档跟踪 Kazumi 磁力下载与本地媒体库两大功能的改进计划。
> 目标平台：Windows / Android。
> 状态说明：`[ ]` 未开始 · `[~]` 进行中 · `[x]` 已完成

## 一、高优先级（核心体验断层）

- [x] 1.1 订阅自动下载 → 自动搜刮 → 自动入库闭环
  - 现状：订阅自动下载的任务不携带番剧信息（scrapeInfo 为空），`_syncCompletedToLibrary` 只处理已搜刮任务，导致自动化追番流程断裂
  - 方案：任务完成后按标题自动跑 MediaScraper，匹配置信度高直接入库，低置信度标记「待确认」供用户一键关联
  - 涉及：`magnet_controller.dart`、`magnet_subscription_service.dart`、`media_scraper.dart`、设置项
  - 实施：任务完成后自动搜刮（`magnetAutoScrapeOnComplete` 设置），命中写入任务并同步媒体库；置信度达阈值（`magnetAutoImportConfidence`，默认 0.7）才自动入库；未命中标记「待确认」徽章，下载页支持「匹配番剧」手动搜索关联与「重新搜刮」

- [x] 1.2 Android 端应用内播放（弹幕 / 历史 / 续播 / Bangumi 进度联动）
  - 现状：`media_library_page.dart:148` Android 走 `OpenFilex` 系统播放器，失去全部联动能力
  - 方案：Android 复用 Windows 的 `LocalMediaVideoPlaybackArgs` + media_kit 播放链路
  - 涉及：`media_library_page.dart`、`video_page.dart`、播放器本地文件适配
  - 实施：Android 切换为应用内播放（卡片点击与文件操作面板两处入口）；新增 `AndroidStorageAccess` 服务 + MainActivity 权限通道（READ_MEDIA_VIDEO / READ_EXTERNAL_STORAGE 运行时申请、MANAGE_EXTERNAL_STORAGE 引导入口），添加文件夹与启动扫描时自动确保读取权限

- [x] 1.3 磁力下载 Android 后台存活（前台服务 + 常驻通知）
  - 现状：进程内 libtorrent 引擎随 app 被杀即停
  - 方案：复用 `flutter_foreground_task`（现仅 HTTP 下载使用），磁力任务活动期间启动前台服务并展示进度通知
  - 实施：`BackgroundDownloadService` 重构为租约制共享前台服务（`http` / `magnet` 双租约，全部释放才停服，通知内容按最后更新租约渲染、释放时回退）；磁力任务下载中自动 acquire + 每 2s 节流更新进度通知，全部结束释放；通知栏「暂停全部」同时作用于磁力任务

- [x] 1.4 下载并发限制与队列调度
  - 现状：`MagnetDownloadService.add` 无并发控制，所有任务同时全速
  - 方案：新增「同时活动任务数」设置，超出的任务进队列（queued 状态）自动排队
  - 实施：新增 `magnetMaxActiveDownloads`（默认 3，0 不限）；队列策略纯函数 `computeQueueChanges`（先添加先提升、最后添加先让位）；排队任务引擎保持暂停，状态流转 / 重启重挂 / 手动暂停恢复后自动重算；UI 新增「排队中」状态徽章与「立即开始」操作

- [x] 1.5 边下边播（顺序下载）
  - 现状：只能整包下完再播
  - 方案：文件级顺序下载（libtorrent priority=7），下载页对正在下载的任务提供「播放」入口，边下边看
  - 实施：使用 vendored libtorrent_flutter 内置的 TorrServer 风格 HTTP 流服务器（`startStream`）；下载任务菜单新增「边下边播」（可流式文件选择 → 启动流 → 播放页）；新增 `MagnetStreamVideoPlaybackArgs` + 播放器 isStreamMode（弹幕按文件名集数+标题检索匹配，不写历史）；暂停/排队任务自动先恢复；删除任务时停止关联流

## 二、磁力下载增强

- [x] 2.1 下载完成 / 失败通知（Android 通知 + Windows toast）
  - 实施：新增 `AppNotifications` 服务（Android 走 awesome_notifications 含通道与 Android 13+ 权限申请；Windows 走 local_notifier/WinToast）；任务状态跳变到完成 / 错误时触发一次系统通知；启动时初始化
- [x] 2.2 定时限速时段（夜间全速 / 日间限速）+ 定时暂停恢复
  - 实施：新增「限速时段」设置（开关 + 起止时间 + 时段限速值，支持跨天窗口）；策略调度器每分钟校验，窗口内覆盖全局下载限速
- [ ] 2.3 每任务单独限速与做种策略覆盖（现仅全局）
  - 说明：vendored libtorrent fork 未暴露 per-torrent 限速 API（仅全局 setDownloadLimit），需先在 C++ 桥接层补 `torrent_handle::set_download_limit` 绑定后才能实施

- [ ] 2.8b 充电时才下载（Android）
  - 说明：需要 battery 状态插件（battery_plus），当前依赖集不含，待补充
- [x] 2.4 添加任务前磁盘空间检查，下载中空间不足自动暂停并提示
  - 实施：新增 `DiskSpace` 工具（Android 复用 StatFs MethodChannel，Windows 用 win32 GetDiskFreeSpaceExW）；添加任务前可用空间 < 300MB 时告警；元数据首次就绪时按真实总大小校验，剩余空间不足（余量 200MB）自动暂停任务
- [x] 2.5 错误重试：error 状态一键重试；元数据获取超时重试
  - 实施：`MagnetDownloadService.retry` + `_remountForRetry`（移除旧任务不删文件后重加，resumeAware 引擎自动磁盘校验续传）；error 任务菜单新增「重试」；元数据超时跟踪（10 分钟超时自动重试，最多 5 次后标记错误），进入真实下载/校验后复位计数
- [x] 2.6 剪贴板识别 magnet: 链接，复制后弹出一键下载
  - 实施：进入磁力页时检查剪贴板，识别 `magnet:?xt=urn:btih:` 与 `.torrent` 直链，弹窗确认后一键加入下载队列（与已有任务同源自动去重）
- [x] 2.7 已完成任务归档：进行中 / 已完成分组 + 批量清理已完成记录
  - 实施：已完成筛选下新增「清除已完成记录」操作（确认后移除记录、保留磁盘文件）
- [x] 2.8 移动端约束：仅 WiFi 下载、充电时才下载
  - 实施：新增「仅 WiFi 下载」（connectivity_plus 网络类型判定，非 WiFi/有线网络自动暂停下载中任务，恢复后自动继续；充电检测暂缺依赖后续补充）
- [x] 2.9 手动文件校验入口（下载完成后 hash 校验）
  - 实施：任务菜单新增「校验文件」（引擎 force_recheck，复用 fork 的 recheckTorrent），校验期间 UI 显示「校验进度中」状态
- [x] 2.10 下载列表搜索 / 排序
  - 实施：下载页新增任务搜索框（按标题 / 文件名 / 番剧名过滤，支持状态筛选组合）

## 三、本地媒体库增强

- [x] 3.1 续播状态可视化：卡片显示「看到 EPx xx%」+ 继续播放直达
  - 实施：`MediaResumePoint` + 续播点缓存（按 episodePageUrl 精确匹配本地播放历史，随历史变化自动刷新）；网格卡片封面底部「续播 EPx · 12:34」角标（点击直达续播）；番剧视图分组头部显示「上次看到…」+「续播」按钮；续播由播放器历史机制自动恢复进度
- [x] 3.2 弹幕本地缓存：在线匹配的弹幕落盘 sidecar，离线 / 二次播放零请求
  - 实施：既有实现已完整（本地媒体播放时经 `localDanmakuDirectory` + `danmakuScope` 读写 `danmaku_<ep>_<scope>.json` 侧车文件，首次拉取后落盘、离线可读），无需改动
- [x] 3.3 外挂字幕识别：sidecar .ass/.srt 作为外部轨道传给播放器
  - 实施：播放器启用 mpv `sub-auto=fuzzy`，自动加载与本地视频同目录的外挂字幕（.ass/.srt/.ssa 等，按文件名相似度匹配）
- [x] 3.4 多集文件与特别篇分组：`[01-03]` 合集、OVA/SP/剧场版归入特别篇组
  - 实施：新增 `classifyLocalEpisode` / `localEpisodeKindLabel`（正片 / SP / 剧场版 / 特典分类），文件列表对非正片显示分类徽章；批量 `[01-03]` 合集文件的深层集数映射留待后续
- [ ] 3.5 批量重命名：按「番剧名 + 第N话」统一整理
- [x] 3.6 库内搜索过滤（标题 / 年份）
  - 实施：媒体库顶栏新增搜索开关，按番剧名 / 文件夹名 / 文件名过滤三种视图
- [x] 3.7 空间占用统计（每部番剧 / 全库）
  - 实施：统计栏展示全库总占用（三种视图共用）；按番剧粒度可后续在分组视图补充
- [ ] 3.8 DLNA 投屏（本地媒体投电视，dlna_dart 已在依赖中）
- [x] 3.9 海报离线缓存（离线可看海报墙）
  - 实施：既有实现已覆盖 —— `NetworkImgLayer` 基于 `CachedNetworkImage`（cached_network_image 自带磁盘缓存），封面离线可读，无需改动
- [x] 3.10 自动重扫（Windows 文件监听 / Android 前后台切换触发）
  - 实施：媒体库页打开期间每 5 分钟自动重扫 + 应用回到前台（含桌面窗口聚焦）时重扫，感知外部文件变动；监听方案后续可替换为原生 FileSystemWatcher

## 四、双功能联动

- [ ] 4.1 Bangumi 双向联动：拉取追番列表，标注本地已有 / 缺失
- [x] 4.2 全集看完自动标记 Bangumi「看过」状态
  - 实施：进度同步追平正片总量（Bangumi 分集 type=0 计数）后，把收藏状态更新为「看过」（type=2），按 subject 幂等去重
- [ ] 4.3 订阅支持「按番剧订阅」：关键词关联 Bangumi 条目而非纯文本匹配

## 实施记录

| 日期 | 任务 | 说明 |
| ---- | ---- | ---- |
| 2026-08-14 | 1.1 | 订阅自动下载 → 自动搜刮 → 自动入库闭环（含待确认徽章、手动匹配、重新搜刮、置信度阈值设置） |
| 2026-08-14 | 1.2 | Android 应用内播放 + 存储权限通道（READ_MEDIA_VIDEO 运行时申请、所有文件访问引导） |
| 2026-08-14 | 1.4 | 下载并发限制与队列调度（queued 状态、自动提升/降级、重启重挂后重算） |
| 2026-08-14 | 1.5 | 边下边播：引擎 HTTP 流 + MagnetStreamVideoPlaybackArgs + 播放器流模式 |
| 2026-08-14 | 2.5 | 错误一键重试 + 元数据超时自动重试（10 分钟超时、最多 5 次） |
| 2026-08-14 | 3.1 | 媒体库续播状态可视化（网格角标 + 番剧视图续播按钮，历史自动恢复进度） |
| 2026-08-14 | 3.2 | 弹幕本地缓存：既有实现已完整（侧车文件 danmaku_&lt;ep&gt;_&lt;scope&gt;.json 读写），无需改动 |
| 2026-08-14 | 2.1 | 下载完成/失败系统通知（Android awesome_notifications + Windows local_notifier） |
| 2026-08-14 | 1.3 | 磁力下载 Android 后台存活：前台服务租约化重构 + 磁力进度通知 + 暂停全部联动 |
| 2026-08-14 | 2.2/2.8/2.9 | 限速时段（跨天窗口）+ 仅 WiFi 下载 + 手动校验文件 |
| 2026-08-14 | 2.4/2.6 | 磁盘空间检查（添加前告警 + 元数据就绪后自动暂停）+ 剪贴板磁力识别一键下载 |
| 2026-08-14 | 2.7/2.10 | 清除已完成记录 + 下载列表搜索 |
| 2026-08-14 | 3.3/3.4 | 外挂字幕自动加载（sub-auto=fuzzy）+ 特别篇/剧场版分类徽章 |
| 2026-08-14 | 3.6/3.7/3.10 | 库内搜索 + 全库空间统计 + 自动重扫（前台恢复/定时） |
| 2026-08-14 | 4.2 | 全集看完自动标记 Bangumi「看过」 |
