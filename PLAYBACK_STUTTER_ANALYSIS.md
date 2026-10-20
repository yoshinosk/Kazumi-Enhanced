# Kazumi Windows 播放卡顿原因分析

- 日期：2026.10.19
- 现象：运行 `build\windows\x64\runner\Release\kazumi.exe` 播放视频时，音频与画面出现卡顿
- 分析方式：只做现场取证与代码审查，未改动任何代码

## 结论（TL;DR）

卡顿不是播放内核/解码/GPU 的问题，而是 **MagnetDownloadService 的「完成态诊断日志」在无限刷屏**，叠加 `playerDebugMode=true` 全量落盘与 3.5GB 巨型日志文件，造成持续性的 CPU 与文件系统开销；再被本机高负载的常驻软件（Wallpaper Engine、火绒等）放大。

你的直觉「应该不是代码问题」恰好反了——**这确实是一个代码问题**（外加环境放大因素）。

## 关键证据

| # | 证据 | 数值 | 来源 |
|---|------|------|------|
| 1 | 日志文件体积 | **3.5 GB**（3,546,474,809 字节） | `C:\Users\Yoshino\AppData\Roaming\com.example\kazumi\logs\kazumi_logs.log` |
| 2 | 「native completion」刷屏条数 | **8,053,352 行** | rg 全文统计 |
| 3 | 实测刷屏速率 | **~65 行/秒（17.2 KB/s）持续写**，文件仍在增长 | 10 秒前后文件大小差 |
| 4 | kazumi 进程 CPU | **139%（≈1.4 个核心）**，远超本地硬解播放正常水平（<15%） | Win32_PerfFormattedData_PerfProc_Process |
| 5 | 日志末尾 3MB 内容 | **0 条播放器日志，100% 磁力刷屏** | 字节级采样 |
| 6 | playerDebugMode | **true**（全量 INFO 强制落盘） | setting.hive 二进制判读 |
| 7 | 硬解/GPU | hAenable=true（默认）、hwdec='auto-safe'，GPU 利用率仅 13%，RTX 5070 温度 50℃ | 设置默认值 + nvidia-smi |
| 8 | 磁盘 | 播放所用 F 盘（老 Hitachi 500GB HDD）当时完全空闲 | PerfDisk 计数器 |

## 根因链

### 1. 诊断日志打点条件写错（P1，直接根因）

`lib/services/magnet/magnet_download_service.dart:1483-1500`：

```dart
// 诊断：……仅在完成态上报时打点，量可控。
if (nativeStatus == 'complete' || nativeStatus == 'seeding') {
  KazumiLogger().i('MagnetDownloadService: native completion of …', forceLog: true);
}
```

注释假设「完成态只上报一次，打点量可控」，但**状态同步循环每一轮都会对已处于 complete/seeding 的任务重新上报同样的状态**，条件恒真 → 每轮轮询 × 每个做种任务都打一条日志，永不停止。

- 本机有 13+ 个已完成的做种任务 → 实测 5 批/秒、65 行/秒。
- 每条日志 ~300 字符：MobX observable 属性读取 + 长字符串构建 → `KazumiLogger` 全局锁排队 → `print()` → 异步 append。
- 高频小写入每次都要穿过火绒（HipsDaemon/HipsTray）/Defender 的文件系统过滤驱动，开销被安全软件放大。
- 该循环与播放器共用同一 isolate 与同一把日志锁，持续性侵蚀播放帧调度的时间片。

### 2. playerDebugMode = true（P1，放大器）

setting.hive 中 `playerDebugMode = true`：所有 INFO 级日志带 `forceLog` 强制写盘。诊断日志本设计为「复现后回溯」，但调试开关常开 + 打点条件失效 = 无限落盘。

### 3. 日志系统无轮转、无上限（P1）

`lib/services/logging/logger.dart` 只 append，无大小上限/轮转 → 单文件 3.5GB。每次 append 都要打开句柄、seek 到 3.5GB 处再写。

### 4. 环境放大因素（P2，次要）

| 因素 | 说明 |
|------|------|
| 整机 CPU 负载 87%（采样时刻） | Wallpaper Engine（wallpaper64.exe 动态壁纸）、火绒、多个 msedge/msedgewebview2、手机连接（PhoneExperienceHost）、GameViewer 虚拟显示器、ABDownloadManager、AI-Cubby 等常驻 |
| 2K@179Hz 高刷 + 动态壁纸 | DWM 合成负担大，视频帧呈现节奏易受干扰 |
| F 盘为 2010 年代 Hitachi 500GB 7200rpm HDD | 视频在 `F:\Animate\` 播放；若做种 I/O 与之并发（同一机械盘随机读）会加剧卡顿。当前做种 peer 少、盘空闲，非本次主因，但值得留意 |

### 已排除项

- **解码瓶颈**：硬解开启（默认 `auto-safe`），1080p HEVC-10bit 对 RTX 5070 NVDEC 毫无压力，GPU 13%。
- **Anime4K 超分**：`defaultSuperResolutionMode`/`superResolutionMode` 未出现在 setting.hive（= 从未修改，默认 off）。
- **磁盘读取瓶颈**：F 盘当时队列 0、空闲 99%。
- **网络流缓冲**：本次播放为本地文件（offline，`F:\Animate\...mkv`）。

## 复现/验证步骤

1. 把 3.5GB 的 `kazumi_logs.log` 移走或清空（先关 Kazumi）。
2. 在设置里**关闭播放器调试模式**（playerDebugMode）。
3. 磁力下载页暂停已完成任务的做种（或清掉已完成的 13 个任务）。
4. 重新播放同一文件，任务管理器观察 kazumi CPU：预期从 ~140% 降到 **<20%**，卡顿消失或显著缓解。
5. 若仍有残余卡顿：临时退出 Wallpaper Engine 与火绒再对比，可量化环境因素的占比。

## 引入时间溯源（git 考古）

| 日期 | 提交 | 内容 |
|------|------|------|
| 2026-07-20 | — | 日志系统上线，`kazumi_logs.log` 开始积累（当时量级正常） |
| 2026-08-12 | `a5f0a05` | 内置磁力引擎重构，建立 2s 前台 / 30s 后台状态轮询 |
| **2026-08-22** | **`b854e5a`** | **起刷点。修「文件不完整却显示做种中」误判 bug 时，在 `magnet_download_service.dart` 加入了 native completion 现场诊断打点（`forceLog: true`），打点条件恒真。该提交 28 文件 +1709 行** |
| 2026-09-03 | `962f9c8` | 动过 `_refreshInterval`（非根因） |
| 2026-10-19 | — | 现状：3.5GB / 805 万行，实测 65 行/s |

- `git log -S "native completion"` 仅命中 `b854e5a` 一个提交，即引入后近两个月**从未改动**。
- 数字印证：8-22 起共 58 天 ≈ 62 万批 → 平均 8.1 秒/批（大部分时间 app 在后台走 30s 低频轮询）；本次前台实测 0.2 秒/批，说明**前台/播放时刷屏最凶**——与「播放卡顿」症状时间上吻合。
- 补充：引擎 alert 状态流也会驱动 `refresh()`（2s 定时器只是兜底），做种时 peer 进出/tracker 响应使 alert 频率达 4-5 次/秒，这是前台 5 批/秒的来源。
- 注意：即使关闭 playerDebugMode（不落盘），每轮的字符串构建与 observable 读取照样烧 CPU，只是不再撑大日志文件。

## 为什么平时不卡、今天卡（底火 + 引信模型）

用户反馈「很少碰到今天这种卡顿」——这与结论不矛盾，反而补全了归因：

**底火（常驻，平时被余量吸收）**：刷屏 bug 自 8-22 起一直在，但它只持续烧小半个核 + 17KB/s 磁盘写。14600KF 有 20 线程，平时系统余量足够大，这笔「税」无感。

**今天的引信（实测叠加项）**：
1. **开机初期爬坡**：本机 12:38 才开机登录，13 点即开始播放。开机后 40 分钟内同时活跃：火绒全家桶（HipsTray/ARPProtection/PopBlock）、GameViewer（远程查看 + 虚拟显示器）、AI-Cubby、微信输入法、TranslucentTB、Wallpaper Engine、ABDownloadManager，以及 **TGitCache（TortoiseGit 缓存，今天已烧 268 秒 CPU——正在扫描含上万文件的 Kazumi 仓库）**。整机负载采样时 87%。
2. **做种高峰撞上播放**：kazumi 12:38 随开机自启，13 个任务全部处于完成态做种、多个有 peer 连接。启动后半小时正是 DHT 引导 + tracker 交互最密集的阶段——alert 流驱动刷屏达 **5 批/秒**，是历史平均（8 秒/批）的 **40 倍**。
3. **日志文件历史峰值**：3.5GB，每次写入穿过火绒过滤驱动的成本也处于历史最高点。

平时任一因素单独存在都不至于卡顿；今天全叠上了。**验证方法**：下次卡顿时立刻开任务管理器看两个数字——整机 CPU% 与 kazumi 的 CPU%，kazumi >100% 即为这组问题复现。

## 修复建议

| 级别 | 建议 | 位置 |
|------|------|------|
| P1 | 打点条件改为「状态发生跃迁时才打」：给 entry 增加 `_lastLoggedNativeStatus` 字段，仅当 `nativeStatus != entry._lastLoggedNativeStatus` 时打点并更新 | `magnet_download_service.dart:1488` |
| P1 | 日志文件增加大小上限 + 轮转（如 10MB × 5 份，超限删最旧），启动时检查 | `services/logging/logger.dart` |
| P2 | 该诊断打点属于临时排障用途，「文件不完整却显示做种」问题定位完成后可移除或降为 debug 级（不落盘） | 同上 |
| P2 | release 构建下跳过 `print()`（GUI 子系统下无意义） | `services/logging/logger.dart:117` |

## 附：现场快照（2026.10.19 13:04-13:12）

- GPU：NVIDIA RTX 5070，驱动 32.0.16.1664（2026-08-24），2K@179Hz，13% 利用率、46W、50℃
- CPU：i5-14600KF（14C/20T），整机负载峰值 87%
- 相关进程 CPU（单核归一）：kazumi 139%、System 44%、HipsTray 11%、DownloadSDKServer 11%、GameViewerServer 5%
- 磁盘：C/D=Kingston NVMe、E=WD_BLACK SN7100、G=Kioxia NVMe、F=Hitachi HDS721050CLA660 HDD（视频）、Z=Seagate ST4000VX015 4TB（监控盘）
