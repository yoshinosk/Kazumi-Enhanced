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

## 五、2026-10-25 复核：抓到了具体丢失的条目

### 取证方式（比截图可靠，可复用）

1. 桌面端侧：`%APPDATA%/com.example/kazumi/hive/histories.hive` 直接正则解出全部 key，
   得到桌面端 `local<id>::offline` 共 26 条。
2. 手机端侧：release 包非 debuggable，Hive 读不到，日志也不在可读目录。于是临时用
   Python 冒充桌面端（占用 `45870`，实现 `/api/v1/info`、`/api/v1/ping`、`/api/v1/sync`），
   手机端启动后按已存地址直连上来，**完整抓到 25 条、1.08MB 的上传请求体**
   （注意 Dart `HttpClient` 用 `Transfer-Encoding: chunked`，`Content-Length` 为 0，
   解析必须按 chunk 解块）。抓完把桌面端真实快照原样回给手机，避免污染数据。

### 结论

| 方向 | 事实 | 原因 |
| --- | --- | --- |
| 手机 → 电脑 | 手机 26 条本地媒体历史只上传了 25 条；某本地媒体库条目（`local486347::offline`）从未上传 | 该条目在手机上的 `episodePageUrl` 不是 `kazumi-lan://<当前serverId>/f/...`，而 `exportForServer` 用路径判定归属，直接 `continue` |
| 电脑 → 手机 | 桌面端 26 条都在手机上存在，但这一条在手机上停在旧进度且没有「看到 xx:xx」 | 合并按 `lastWatchTime` 取整条记录，手机这条更新 → 保留手机的失效路径；失效路径又让它无法上传，形成自我固化的死循环 |

即：**路径既当身份又当数据**。路径一旦失效（换过配对 / serverId 变化 / 旧版本写入真实路径 / 被本机文件覆盖），该条目就永久退出同步，而且合并会把这个状态锁死。

### 已修复

1. `LanHistoryEntry.merge`：路径不参与「谁更新」判断，取非空的一方；`lastWatchEpisode`
   与其分集进度不一致时按最新进度回填（恢复「看到」显示）。
2. `LanHistoryStore.applyEntries`：客户端收到远端条目时，若本地同 key 条目的路径已失效
   （空 / 属于其它桌面端 / 指向本机不存在的文件），**以远端伪路径为准**并计数日志。
   本机真实存在的文件不会被改写。→ 失联条目下次同步自愈，随后正常上传。
3. 日志：服务端新增 `LanSyncServer: history keys differ localOnly=[...] remoteOnly=[...]`
   （仅在有差异时写）；客户端新增 `LanSync: exported M/N local history (skipped ...)`
   （跳过集合变化时才写）。这两行本来就能一眼定位问题。

### 仍然存在（未处理）

- 历史删除依旧没有墓碑：一端删除，另一端会推回来。
- 插件下载缓存（`AGE` / `MXdm` 等 adapter）与在线历史不参与局域网同步，属当前设计范围
  （设置页写明只同步「本地播放进度」）；若需全量镜像需另行设计。
