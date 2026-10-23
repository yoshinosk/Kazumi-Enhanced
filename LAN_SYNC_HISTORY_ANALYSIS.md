# 局域网同步：播放历史不生效排查报告

排查时间：2026-10-23
范围：`lib/services/lan/*`、历史仓储与历史页控制器
结论：**历史合并 / 落库的核心逻辑本身是通的，问题出在「同步时机」与「落库后的界面刷新」两处**，另外发现若干会造成「进度被旧数据覆盖」「删除后又复活」的合并缺陷。

## 一、验证方式

1. 用真实 `GStorage` + 真实 `LanSyncServer` 写了临时集成测试，跑通两条链路：
   - 手机 `POST /api/v1/sync` 上传历史 → 桌面端 `mergeLanHistory` + `applyEntries` → 桌面端 Hive 里出现「第 1 集 + 第 2 集」的合并结果（通过）。
   - 桌面端响应快照 → 手机端 `lanFilePath()` 还原伪路径 → `applyEntries` 落库（通过）。
   - `LanHistoryStore.exportForServer()` 能把 `kazumi-lan://<serverId>/f/<base64>` 还原成桌面端真实路径再上传（通过）。
2. 取了本机真实数据取证：
   - `%APPDATA%/com.example/kazumi/hive/histories.hive` 里存在大量 `local<id>::offline` 条目与真实路径，**没有任何 `kazumi-lan://` 残留**（说明路径转换没有反向污染）。
   - `setting.hive` 里 `lanSyncServerEnable / ServerId / Token / PairingCode / Port` 均已写入，说明桌面端服务确实起过。
3. 关键结论：既然客户端状态只有在 `_syncWithServer()` 完整跑完才会变成 `connected`，那么「显示已连接」= 数据往返成功过，用户看到的「没同步」只能是**界面没刷新**或**还没到下一次同步**。

## 二、确认并已修复的缺陷

| 级别 | 位置 | 问题 | 后果 | 修复 |
| --- | --- | --- | --- | --- |
| P1 | `LanSyncService` | 只有「启动 / 回到前台 / 切后台 / 每 3 分钟」四个同步时机，播放进度落库后不推送 | 手机看完一集后 3 分钟内电脑上毫无变化；手机后台被杀则最后一次进度永远推不上去 | 订阅 `histories` 变更，按 20 秒节流追加一次同步（不是防抖——播放时每秒写一次，防抖会永远不触发） |
| P1 | `HistoryController` | 只在 `initState` 读一次存储，不订阅 Hive 变更 | 首页「继续观看」是常驻页面，同步落库后一直显示旧进度，直到重启应用 | 订阅 `IHistoryRepository.changes`，400ms 去抖 + 内容指纹比对后重建列表 |
| P1 | `HistoryPage` / `ContinueWatchingSection` | 打开页面时不触发补同步 | 桌面端刚看的进度要等 3 分钟定时器 | 打开时静默 `syncNow(quiet: true)`（非手机端自动 no-op） |
| P2 | `LanProgressData.fromProgress` | 旧数据的 `Progress.updatedAtMs == 0` 被 `History.lastWatchTime` 兜底，等于把「条目最后观看时间」当成「这一集的更新时间」 | 几个月前的旧进度会被判定为「比对方刚看的还新」，合并后进度回退 | 未知时间如实保留 0（视为最旧），时间相同再按进度大小决胜 |
| P2 | `LanHistoryStore.applyEntries` | `try/catch` 包住整个循环 | 一条脏数据（异常 key / 适配失败）会让**整批**历史都写不进去，且只在日志里留一行 warning | 改为逐条捕获，失败条数汇总记录 |
| P3 | `KazumiLogger` 使用 | `KazumiLogOutput.output()` 只把 `>= warning`（或 `forceLog`）写文件，而局域网同步的关键日志全是 `i` | 现场日志里搜不到任何 `LanSync` 字样，这次排查只能靠读代码 + 数据取证 | 服务启动 / 配对 / 同步结果 / 历史合并统计改为 `forceLog: true` |

## 三、未改动、建议后续处理的问题

| 级别 | 问题 | 说明 |
| --- | --- | --- |
| P2 | **同一番剧「本机本地文件」与「桌面端文件」共用历史 key** | key 是 `local<bangumiId>::offline`（不含路径）。手机本地也存了同一部番时，两种来源互相覆盖 `episodePageUrl`，导致该条 LAN 进度不再被 `exportForServer` 上传（它要求路径是 LAN 伪路径）。彻底修需要把 key 扩展成 `local<id>::offline::<source>`，涉及历史迁移，风险较高。 |
| P2 | **历史删除没有墓碑** | 收藏同步有 `collectTombstones`，历史没有。在一端删掉一条历史，下一次同步会被另一端原样推回来。 |
| P2 | **跨设备时钟无校正** | `lastWatchTime` / `updatedAtMs` 直接比较两台的本地时钟。手机时钟明显偏差时，进度合并方向会错。 |
| P3 | 手动「立即同步」可能空转 | `_discoverAndSync` 里有 `if (_syncing) return;`，后台定时同步进行中点按钮会直接返回，界面无提示。 |
| P3 | `_isAllowedMediaPath` 丢弃条目后无感知 | 文件被移出媒体库根目录、或扩展名不在白名单时整条历史被丢。已加 warning 计数，但更友好的做法是回传给客户端提示。 |

## 四、下次现场排查方法

同步链路现在会往 `logs/kazumi_logs.log` 写（需要 `forceLog`，已加上）：

```
LanSyncServer: started on port <port> (discovery on)
LanSyncServer: paired with <device> (<ip>)
LanSyncServer: sync incoming=<N> local=<M> merged=<K> applied=<X>
LanSyncServer: dropped <N> history entries (path outside media roots or invalid)
LanSync: synced <F> folders / <N> files from <name> (<ip>), <H> history entries, wrote <X>
LanSync: apply history entry failed (<key>)
```

`incoming=0` → 手机端没有可上传的历史（检查手机历史条目的 `episodePageUrl` 是否 `kazumi-lan://` 开头）；
`dropped>0` → 路径被媒体库根目录校验拦掉；
`applied=0` 但 `merged` 有变化 → 合并后与本地一致，属于正常空转。
