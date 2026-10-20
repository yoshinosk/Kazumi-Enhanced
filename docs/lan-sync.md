# 局域网同步与桌面媒体库串流

本文档记录 Kazumi 增强分支的局域网同步设计（Android 手机端 + Windows 桌面端）。
功能目标是：同一 Wi-Fi 下，桌面端开启共享后，手机端打开应用即可自动同步
媒体库、收藏状态与本地播放进度，并直接串流播放桌面端媒体库中的视频。

## 1. 范围

### 已实现

- Windows 桌面端作为 HTTP / UDP 服务端，共享本地媒体库。
- Android 手机端自动发现桌面端，一次配对后自动同步。
- 同步内容：
  - 媒体库目录、文件元数据（名称、大小、修改时间）；
  - 目录级 / 文件级搜刮结果（番剧标题、封面、Bangumi ID 等）；
  - `adapterName == local` 的本地媒体播放历史与逐集进度（双向合并）；
  - 收藏状态（在看 / 想看 / 搁置 / 看过 / 抛弃）与删除墓碑（双向合并）。
- 手机端把桌面端媒体库合并进现有「本地媒体库」页面，支持文件夹 / 番剧 /
  网格视图、续播、缺集检测与详情页「本地剧集」入口。
- 视频通过 HTTP Range 串流播放，支持拖动进度、续播与弹幕。
- 断线后仍展示上次同步的媒体库快照；重新连上后自动刷新。
- 手动填写 IP:PORT，兼容路由器关闭广播 / 跨网段场景。

### 非目标（后续可扩展）

- 不同步在线播放历史、WebDAV 配置等；这些已有独立同步链路。
- 收藏状态采用「最后修改时间优先」；不提供逐条手动选择冲突结果（可关闭同步开关）。
- 同一时间只连接一个桌面端（单 token / 单快照）；多桌面端切换需要重新配对。
- 不做公网穿透、账号体系或云端中转；只在可信局域网内使用。
- 暂不传播「删除观看记录」：进度按较新时间合并，删除需要额外的墓碑协议。
- 暂不同步外挂字幕 / 弹幕侧车文件；远程播放读取视频内嵌字幕，弹幕走在线源。

## 2. 总体架构

```text
┌────────────────────┐        UDP 45871 广播发现       ┌────────────────────┐
│ Android Kazumi     │ ──────────────────────────────▶ │ Windows Kazumi     │
│                    │ ◀────────────────────────────── │                    │
│ LanSyncService     │        HTTP 45870（可选端口）     │ LanSyncServer      │
│  ├ LanDiscovery    │ ──────────────────────────────▶ │  ├ /api/v1/info    │
│  ├ LanSyncClient   │   POST /api/v1/pair  (配对码)    │  ├ /api/v1/pair    │
│  ├ LanHistoryStore │   POST /api/v1/sync  (媒体库+历史)│  ├ /api/v1/sync    │
│  ├ LanCollectStore │   GET  /api/v1/stream (Range)    │  └ /api/v1/stream  │
│  └ LanLibraryCache │                                  │                    │
└─────────┬──────────┘                                  └─────────┬──────────┘
          │                                                       │
          ▼                                                       ▼
   MediaController（本地 + 远程合并视图）                 MediaController（本地库）
   HistoryRepository（local 历史合并）                    HistoryRepository
   CollectController（收藏状态合并）                      CollectController
   media_kit ◀── HTTP Range 串流 ──────────────────────── File.openRead
```

关键代码：

| 文件 | 职责 |
| --- | --- |
| `lib/services/lan/lan_media_paths.dart` | 远程文件伪路径、流地址生成 |
| `lib/services/lan/lan_sync_models.dart` | 协议模型、媒体库快照、历史序列化/合并、缓存 |
| `lib/services/lan/lan_discovery.dart` | UDP 广播发现与手动地址探测 |
| `lib/services/lan/lan_sync_server.dart` | 桌面端 HTTP 服务、Range 串流、配对 |
| `lib/services/lan/lan_history_store.dart` | 本地媒体历史的导出与写回 |
| `lib/services/lan/lan_collect_store.dart` | 收藏状态 / 删除墓碑的导出与写回 |
| `lib/services/lan/lan_sync_service.dart` | 总控：服务生命周期、配对、自动同步 |
| `lib/pages/settings/lan_sync_page.dart` | 设置界面 |
| `lib/pages/media/media_controller.dart` | 本地 / 远程媒体库合并与播放保护 |

## 3. 发现与配对

### 发现

- 桌面端在 UDP `45871` 监听 `KAZUMI_LAN_DISCOVER_V1`。
- 手机端向 `255.255.255.255` 及常见 `/24` 广播地址发送探测，收到响应后
  按 `serverId` 去重。
- 响应包含协议版本、`serverId`、主机名、HTTP 端口；主机 IP 取 UDP 报文
  源地址，服务端不需要自报 IP。
- 若广播被防火墙 / 路由器隔离，可在设置页手动填写 `IP:PORT` 直连。

### 配对

1. 桌面端首次开启共享时生成 `serverId`、访问 token（24 字节随机数）和
   6 位数字配对码。
2. 手机端 `POST /api/v1/pair` 提交配对码与设备名，桌面端校验后返回 token。
3. 手机端保存 token、serverId、主机与端口；后续请求携带
   `X-Kazumi-Token`（串流因 mpv 请求头不便而使用 query token）。
4. 桌面端可刷新配对码（新设备需要新码）或重新生成 token（所有已配对
   设备失效，需要重新配对）。
5. 配对接口按来源 IP 做 1 分钟 10 次限流，token 比较使用常量时间实现。

> 安全边界：这是局域网明文 HTTP 协议，token 可能被同网段抓包获取。
> 适用于家庭 / 可信局域网；不要直接暴露到公网。桌面端首次监听时
> Windows 防火墙会询问，请只允许专用网络。

## 4. 同步协议

### `GET /api/v1/info`

无需鉴权。返回 `LanServerInfo`，用于手动探测与发现响应。

### `POST /api/v1/pair`

```json
{ "code": "123456", "deviceName": "Pixel" }
```

响应：

```json
{
  "token": "...",
  "server": { "protocol": 1, "serverId": "...", "name": "...", "httpPort": 45870 }
}
```

### `POST /api/v1/sync`

需要鉴权。请求：

```json
{
  "protocol": 1,
  "history": [ /* 手机端当前桌面端的本地媒体历史（真实路径） */ ],
  "collectibles": [
    { "bangumiItem": { /* BangumiItem */ }, "type": 4, "timeMs": 1760000000000 }
  ],
  "collectTombstones": [
    { "bangumiId": 9001, "updatedAtMs": 1760000000000 }
  ]
}
```

响应：

```json
{
  "server": { "...": "..." },
  "folders": [
    {
      "path": "E:\\Anime\\某番剧",
      "name": "某番剧",
      "files": [
        { "path": "E:\\Anime\\某番剧\\01.mkv", "name": "01.mkv", "size": 123, "modifiedAtMs": 0 }
      ]
    }
  ],
  "scrapeResults": { "E:\\Anime\\某番剧": { /* MediaScrapeInfo */ } },
  "fileScrapeResults": { "E:\\Anime\\某番剧\\01.mkv": { /* ... */ } },
  "history": [ /* 合并后的桌面端全部本地媒体历史（真实路径） */ ],
  "collectibles": [ /* 合并后的收藏状态 */ ],
  "collectTombstones": [ /* 合并后的删除墓碑 */ ],
  "generatedAtMs": 0
}
```

同步流程：

1. 手机端导出属于当前桌面端的远程播放历史，伪路径还原为真实路径；
   同时导出收藏状态与删除墓碑。
2. 桌面端把手机历史与本地历史合并、写回 Hive；收藏状态按最后修改时间
   合并并写回，再构建当前媒体库快照。
3. 手机端缓存快照，转换为伪路径并合并进 `MediaController`；历史与收藏
   状态写回手机 Hive 后刷新续播点与收藏页。

### `GET/HEAD /api/v1/stream?path=<base64url>&token=...`

- 仅允许访问媒体库根目录下、扩展名受支持的视频文件（防目录穿越）。
- 支持单段 `Range: bytes=...`，返回 `206` + `Content-Range`；无 Range
  返回完整 `200`。
- `Content-Type` 按扩展名映射（mkv / mp4 / ts 等）。
- mpv 拖动进度、续播与多线程读取均使用 Range。

## 5. 历史合并规则

只处理 `adapterName == local` 的条目，在线播放历史仍由 Bangumi / WebDAV
链路负责。

- 同一个番剧 + adapter + `entryKind` 视为同一条历史，key 与现有
  `History.key` 一致。
- 顶层观看状态（最后观看集数、时间、集名、页面地址）取 `lastWatchTime`
  较新的一方。
- 逐集进度按 `updatedAtMs` 取较新值；时间相同则取进度更大的值。
- 两端写回都采用「同 key 合并后 put」而不是整表替换，手机本地视频历史、
  其他桌面端历史不会被误删。
- 手机端只上传属于当前桌面端的历史；桌面端返回全部本地媒体历史。

已知限制：删除历史不会同步（无墓碑），删除后可能被另一端重新带回；
收藏状态则使用墓碑协议，删除可以同步。

## 6. 收藏状态合并规则

- 同一 Bangumi ID 只保留一个收藏状态。
- 比较 `CollectedBangumi.time`（最后一次设置状态的时间），较新的一方获胜。
- 时间完全相同时，按固定优先级决胜：
  `在看 > 看过 > 想看 > 搁置 > 抛弃`，保证两端最终得到同一个结果。
- 删除：`collectChanges` 中最近的 `action=3` 作为墓碑；墓碑严格晚于现役
  状态时才删除。同一秒内重新收藏视为收藏方获胜。
- 写回时只有新增 / 类型变化才追加 WebDAV 变更日志；单纯时间推进不会产生
  多余的收藏变更。
- 手机 / 桌面端设置页均可关闭「同步收藏状态」。
- 冲突判断依赖设备本地时钟；两端时间偏差过大会影响「最新优先」的结果。
- 删除墓碑只删除本地收藏。若同时启用 Bangumi 同步，Bangumi 远端不支持
  删除收藏，下次 Bangumi 同步可能把远端收藏重新补回本地。

示例：手机把某番剧标为「看过」（时间较新），电脑标为「抛弃」，同步后两端
都会变为「看过」；若电脑的「抛弃」时间更晚，则两端都变为「抛弃」。

## 7. 远程播放路径

1. 同步时把桌面文件映射为稳定伪路径：
   `kazumi-lan://<serverId>/f/<base64(真实路径)>`。
   目录使用 `/d/`。
2. `LocalMediaFile` 同时保存：
   - `path`：伪路径，用于历史、续播、搜刮结果与去重；
   - `playbackUrl`：带 token 的 HTTP 流地址，仅本次连接有效；
   - `remoteFolderName/Path`：详情页按目录分组展示。
3. 播放器路由参数 `LocalMediaVideoPlaybackArgs.remote = true`：
   - `Road.data` 放播放地址，`Road.pageUrls` 放稳定伪路径；
   - 历史使用伪路径，视频使用 HTTP 地址；
   - 关闭本地 fuzzy 字幕扫描与同目录弹幕侧车读写；
   - 设置 `isLanPlayback`，跳过用户 HTTP / 系统代理（内网直连）。
4. 历史页恢复远程条目时，从当前媒体库快照找到同目录文件重建选集列表；
   快照不存在或 token/端口失效时提示重新同步。
5. 远程播放期间产生的进度每 3 分钟、回到前台和退到后台时回传桌面端。

## 8. 状态与失效处理

- 桌面端离线：手机端保留上次快照，媒体库可浏览；播放前提示桌面端未连接。
- token 失效：同步返回 `401`，客户端清 token，状态变为「需要重新配对」。
- 端口冲突：桌面端自动改绑临时端口，发现响应与设置页展示真实端口；
  手动连接需使用新端口。
- 桌面端媒体库尚未扫描完成：第一次同步会先等待一次扫描，避免返回空库。
- 手机端关闭同步或取消配对：清理快照与远程搜刮结果，不删除手机本地数据。

## 9. 设置入口

- `设置 → 同步设置 → 局域网同步`。
- Windows：开启共享、查看访问地址与配对码、刷新配对码、同步收藏状态开关。
- Android：开启同步、查看连接状态、自动同步开关、同步收藏状态开关、
  发现列表、手动地址、立即同步、取消配对。
- 媒体库页顶部状态条与右上角路由器图标提供快捷入口 / 同步。

## 10. 测试

`test/lan_sync_test.dart` 覆盖：

- 伪路径编解码与路径身份；
- 流地址中的 token / base64 路径；
- Range 头解析（普通、后缀、越界、非法）；
- 历史序列化与逐集合并规则；
- 收藏状态最后修改优先、同时间优先级、墓碑删除与重新收藏；
- 本地 HTTP 服务的配对、鉴权、媒体库 / 收藏同步与 Range 串流集成；
- 手动地址解析。
