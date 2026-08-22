# 修改日志

每次修改后在此文件**最顶部**追加日志，格式见 `AGENTS.md`。

## 2026.8.22

- 修复磁力任务「边下边播后瞬间 100% / 已完成」的根因：libtorrent 官方语义中 `finished/seeding` 仅表示**优先级 > 0 的片段已下完**（可伴随「部分片段被过滤未下载」），而边下边播启动流时原生引擎（`lt_start_stream`）会把非流窗口片段全部降为 `dont_download`，流窗口（头部 + 尾部 + 起播关键片段，通常仅数十 MB）下完引擎即如实上报 `finished/progress=1.0`；应用层此前把它当作整包完成，`completedLength` 被对齐到整包大小导致假 100%，文件实际只有流窗口数据。新增完成态覆盖校验（`completionCoversExpected`）：引擎的 `totalWanted` 与 `totalDone` 未覆盖期望下载集（全部文件或已选择文件之和）的完成上报一律按下载中处理，任务保持真实进度，停止播放恢复优先级后继续下载剩余部分；已处于完成 / 做种态的任务不受影响。另将「原生完成上报」诊断日志改为 `forceLog` 持久化（INFO 默认不落盘，导致此前复现无据可查）
  - 相关文件: lib/services/magnet/magnet_download_service.dart, test/magnet_download_entry_test.dart

## 2026.8.22

- 修复磁力任务「文件不完整却显示做种中 / 100%」：`_onTorrents` 中「完成态可信」证据含 `checking` 状态，而当目标目录已残留（可能不完整）同名文件时引擎校验阶段的 `totalDone` 会从 0 爬升，据此置位后引擎一报 `finished/seeding` 即被直接信任导致假做种；收严为**仅当 `active` 且 `hasMetadata` 且 `totalDone > 0`**（真实进入下载并校验 / 下载出字节）才置位可信，`checking` / 空 `active` 不再充当完成证据，交给「可疑瞬时报完成」检测强制 `recheck` 按磁盘真实情况转成续传缺失。另新增完成态上报的现场诊断日志便于确认引擎的 `state/progress/totalDone/totalWanted/isFinished/hasMetadata`。
  - 相关文件: lib/services/magnet/magnet_download_service.dart

## 2026.8.22

- 修复创建磁力下载任务时磁盘空间校验误判「空间不足」的问题：Animes Garden 搜索源的 `size` 字段单位为字节（API 实测直接返回字节数，如 781398016 ≈ 745 MB），原 `_formatKbSize` 误当作 KB 乘以 1024，导致磁力任务体积被放大 1024 倍，磁盘空间校验用错误体积对比而误报「空间不足」；改为按字节处理（重命名为 `formatAnimesGardenSize`），并补充回归测试
  - 相关文件: lib/services/magnet/animes_garden_service.dart, test/animes_garden_size_test.dart

## 2026.8.19

- 调整磁力 RSS 订阅功能：新增自动检查更新间隔设置（默认 1 小时，可在设置中调整为 30 分钟～1 天），定时检查发现新条目时自动提交下载
  - 相关文件: lib/services/storage/settings_keys.dart, lib/services/magnet/magnet_subscription_service.dart, lib/pages/magnet/magnet_controller.dart, lib/pages/settings/magnet_settings.dart

## 2026.8.19

- 磁力 RSS 订阅：打开软件时立即检查一次订阅更新；添加订阅时立即检查并自动下载当前 feed 条目（按订阅的自动下载开关决定是否下载，引擎未启用等失败场景不推进游标、下次定时检查自动重试）
  - 相关文件: lib/services/magnet/magnet_subscription_service.dart, test/magnet_subscription_service_test.dart

## 2026.8.19

- 播放器弹幕面板「弹幕池 / 切换分集」按钮上方增加边距，避免紧贴分隔线
  - 相关文件: lib/pages/player/episode_danmaku_sheet.dart

## 2026.8.19

- 修复本地媒体库播放时弹幕池绑定到其它番剧的问题（弹幕正常关联但不显示 / 轴对不上）：
  - 策略链原为「侧车缓存 → 下载缓存 → 文件哈希匹配 → BGM 映射 → 标题检索」，文件哈希匹配 / 标题检索可能把弹幕池绑到与搜刮结果不同的番剧，且侧车缓存会固化这种错误绑定 —— 改为优先按「搜刮的番剧」绑定：先解析搜刮 BGM ID 对应的弹弹番剧 ID，命中且该集有弹幕时直接采用，文件匹配 / 标题检索仅作兜底
  - 侧车缓存新增番剧一致性校验：搜刮番剧的弹弹 ID 已知且侧车 `danDanBangumiID` 与之不符时丢弃侧车（历史错误绑定），改按搜刮番剧重新绑定
  - 在线播放路径行为不变（文件匹配本就只用于本地文件）
  - 相关文件: lib/pages/player/controller/player_danmaku_controller.dart

## 2026.8.18

- 修复磁力下载重复任务与「刚创建就显示做种中」问题：
  - 同磁力链（info-hash 相同、tracker 不同）重复提交会创建重复任务：新增按 `xt=urn:btih` 归一化的去重（忽略大小写 / tracker / dn 差异），`add()` 直接忽略重复，搜索界面重复提交提示「该资源已在下载队列中」
  - 新建任务几秒内即显示「做种中 / 100%」而文件实际是空占位：元数据未就绪时引擎把「0 片（无内容可下）」的磁力上报为 `progress=1.0 / is_finished`，`_mapStatus` 不再对无元数据任务判完成；元数据到达后引擎可能跳过磁盘校验直接报完成 —— 新增「可疑瞬时报完成」检测，任务从未下载、也未经过引擎校验却被报完成时强制 `recheck` 校验磁盘（空文件转下载、数据完整维持做种），重挂 / 重试后重新评估
  - 相关文件: lib/services/magnet/magnet_download_service.dart, lib/pages/magnet/magnet_controller.dart, test/magnet_download_entry_test.dart

## 2026.8.16

- 修复本地文件手动绑定弹幕库（弹幕检索 / 弹幕切换）后弹幕不显示的问题：
  - `getDanDanmakuByEpisodeID` 绑定成功后不写回弹弹番剧 ID：本地播放自动加载失败（`bangumiID=0`）后手动绑定，弹幕面板仍显示「未绑定弹幕」、弹幕轴偏移作用域落到 `0:episodeId` 与其它本地文件互相污染 —— 新增 `bangumiId` 参数并在绑定成功时写回，`bindDanmakuToEpisode` 及各调用点补传番剧 ID
  - 弹幕池整体替换后发射代次不复位：播放器发射追踪误以为当前秒已发射，绑定瞬间当前秒的弹幕被跳过 —— 绑定成功后清空画布残留弹幕并递增发射代次，追踪复位后从当前秒重新发射
  - 弹幕面板以 `bangumiID <= 0` 判定「未绑定弹幕」：弹幕池非空（侧车文件 / 手动绑定，bangumiID 可能为 0）也被隐藏 —— 改为按弹幕池是否为空判定，空态文案仍区分「未绑定 / 池为空」
  - 相关文件: lib/pages/player/controller/player_danmaku_controller.dart, lib/pages/player/controller/player_danmaku_controller.g.dart, lib/pages/player/danmaku_switch_dialog.dart, lib/pages/player/episode_danmaku_sheet.dart

## 2026.8.16

- 修复审查确认的 9 个问题：
  - 自动入库会移动 / 重命名正在被边下边播流读取的文件导致断流：`MagnetDownloadService` 新增 `isStreaming()`，`shouldAutoImport` 对在播任务跳过入库（不标记失败，流停止后下一轮状态同步自动重试）
  - `clearCompleted()` 不停止在播任务的流服务器 / 做种句柄导致端口泄漏至进程退出：清除前逐个调用 `stopStreamsForTask()` 补做流停止与引擎移除
  - tracker 定时器回调在 `dispose()` 之后重建调度链、退出后继续联网且无 try/catch：调度入口加 `_disposed` 检查，回调包 try/catch，更新失败也继续下一周期自愈
  - 新订阅首拉 feed 为空时 `lastGuid=null`、下一轮把整个 feed 当新条目全量自动下载：游标未初始化时本轮只建立游标、不上报新条目
  - 媒体库标题分组「假路径」键随目录文件集合变化（单标题 ↔ 多标题）失效、搜刮 / 历史迁移按旧键永久丢失：扫描结果新增分组快照（目录 → 归一化标题 → 分组路径，新增设置 `localMediaLastGrouping`），每次扫描按标题对齐新旧快照并迁移搜刮结果到新键
  - 弹幕池面板每次 build 全量 flatten + O(N log N) 排序（数万条弹幕时卡顿）：`PlayerDanmakuController` 新增弹幕池版本计数，面板按版本缓存排序结果
  - WebView 旧页面在导航切换期间迟到的解析事件被新 resolve 接受、可能播错 URL/offset：新增页面代际（`beginPageLoad` / `markPageStarted` / `canAcceptResolve`），Android 实现以新页面脚本启动标记、通用回退实现以 `onLoadStart` 为界丢弃旧页面迟到消息
  - 播放中每秒 2 行历史同步事件写入、约 1 小时触发 1MB checkpoint 全量重写：进度事件按（条目, 分集, 线路）10 秒窗口合并，中间重复写入直接丢弃（事件为幂等 upsert，不影响最终一致性）
  - 前台服务拒绝通知权限后每批任务重复弹窗、acquire 失败后租约悬挂：权限询问改为会话级记忆（拒绝后不再重复弹自定义窗），`acquire` 启动失败时回滚本次新增租约，避免 `isHeldBy` 门控误判服务可用而不再重试
  - 相关文件: lib/services/magnet/magnet_download_service.dart, lib/pages/magnet/magnet_controller.dart, lib/services/magnet/magnet_subscription_service.dart, lib/services/media/local_media_scanner.dart, lib/services/media/local_media_models.dart, lib/pages/media/media_controller.dart, lib/services/storage/settings_keys.dart, lib/pages/player/controller/player_danmaku_controller.dart, lib/pages/player/episode_danmaku_sheet.dart, lib/webview/video/video_webview_controller.dart, lib/webview/video/impl/video_webview_android_impl.dart, lib/webview/video/impl/video_webview_impl.dart, lib/services/sync/history_sync_service.dart, lib/services/download/background_download_service.dart

## 2026.8.16

- 修复「仅 WiFi 下载」策略完全失效的问题：非 WiFi 分支先置 `_pausedByWifi = true` 再调用 `pause()`，而 `pause()` 同步段第一句就把该标记清除（注释本意只清用户手动暂停），导致 WiFi 恢复 / 关闭开关时按标记续传的分支永不命中、被策略暂停的任务永远卡在暂停态。抽出内部 `_pauseEntry()`（不清标记），策略暂停改走内部实现，`pause()` 仅用户手动暂停时清标记
  - 相关文件: lib/services/magnet/magnet_download_service.dart
- 修复磁盘空间自动暂停对新任务永不生效的问题：防重标记 `_diskSpaceCheckedTaskIds.add` 在 `applyTorrentStatus` 之前执行，而任务总量在 `applyTorrentStatus` 中才写入，元数据就绪首个 tick 里 `totalLength` 仍为 0，检查提前 return 但标记已下发导致会话内永不复查；磁盘空间校验移到 `applyTorrentStatus` 之后
  - 相关文件: lib/services/magnet/magnet_download_service.dart
- 修复倍速 ≠ 1 时弹幕系统性丢失或重复的问题：弹幕发射由固定 1s Timer 驱动且每次只采样当前秒桶，2x 时奇数秒整桶丢失、0.5x 时同秒重复发射、缓冲停滞时同秒反复发射。改为记录上次发射的源秒，逐 tick 补发区间内所有整秒弹幕（跳变超过 5 秒视为 seek 只发当前秒），弹幕池代次变化（seek / 偏移调整 / 弹幕重载）后重置追踪
  - 相关文件: lib/pages/player/player_item.dart
- 修复弹幕轴检测结论写入全局持久设置、一次应用后永久自废的问题：推荐偏移改为按「bangumiID:episodeId」作用域存储（新增设置 `danmakuTimeOffsetByEpisode`，JSON 字符串），命中顺序为精确分集 → 同番剧（episodeId 未知）→ 全局手动偏移；单集检测结果不再作用于之后所有剧集，其他番剧 / 分集仍会自动触发检测
  - 相关文件: lib/services/storage/settings_keys.dart, lib/pages/player/controller/player_danmaku_controller.dart, lib/pages/player/danmaku_axis_dialog.dart
- 修复同步关闭期间的删除不落墓碑、重新开启后已删历史复活的问题：`appendSafely` 新增 `requireEnabled` 参数，删除 / 清空的墓碑无条件写盘（同步开关只控制上传与高频进度事件），重新开启同步后事件日志中的墓碑会抑制远程快照 putAll 复活
  - 相关文件: lib/services/sync/history_sync_service.dart, lib/repositories/history_repository.dart
- 修复占位历史迁移覆盖更新的真实历史的问题：`_repairPlaceholderHistories` 迁移前先按真实番剧查询既有条目，若匹配后用户已重新播放过（真实条目更新）则跳过迁移、直接丢弃占位条目，避免 `updateHistory` 无条件写 `lastWatchTime=now` 并用陈旧占位进度覆盖新历史；迁移路径改为迁移全部集数进度并按占位条目的 watch-state 收尾
  - 相关文件: lib/pages/media/media_controller.dart
- 修复本地媒体库扫描单个无权限子目录（如 Android/data）导致整个根目录扫描失败清空媒体库的问题：`listSync(recursive: true)` 改为逐层手动遍历，单个子目录无权限 / 损坏只跳过该目录；同时以真实路径（resolveSymbolicLinks）去重，防止 Windows junction 符号链接环导致无限遍历
  - 相关文件: lib/services/media/local_media_scanner.dart
- 修复 Android 13+ 首次启动并发请求通知（POST_NOTIFICATIONS）与媒体读取（READ_MEDIA_VIDEO）权限时后发弹窗被系统静默取消、媒体库首次扫描无权限的问题：`_initializeApp` 改为先 `await AppNotifications.init()` 完成通知权限请求，再进入 `mediaController.init()` 的媒体权限请求，串行化启动时的权限对话框
  - 相关文件: lib/pages/init_page.dart

## 2026.8.16

- 开始维护当前分支版本号：项目版本由上游 `2.2.6+20206` 改为 `0.0.1+1`（`pubspec.yaml`、`lib/request/config/api_endpoints.dart` 同步为 `0.0.1`），README 顶部标注本分支基于上游 [2.2.6](https://github.com/Predidit/Kazumi/releases/tag/2.2.6) 版本开发
  - 相关文件: pubspec.yaml, lib/request/config/api_endpoints.dart, README.md

## 2026.8.16

- 根据 CHANGELOG 同步更新 README：更新「项目特点」「开发状态」，将本地媒体库与磁力下载中已完成的开发项（外挂字幕、续播可视化、边下边播、队列调度、限速时段、仅 WiFi、自动搜刮入库、通知与后台保活、按番剧分组等）标记为已完成并调整待办项
  - 相关文件: README.md

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