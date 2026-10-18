# 媒体库搜刮策略分析（media_scraper）

分析对象：`lib/services/media/`（扫描 + 搜刮）与 `lib/pages/media/media_controller.dart`（编排 + 持久化）。
结论：整体骨架（清洗 → 多候选 → 打分 → 兜底 → 持久化）设计合理，但**召回、准确率与请求成本三处存在明确优化空间**，其中 4 项属 P1。

---

## 一、实现全景

### 1.1 链路总览

```text
磁盘目录
  │ LocalMediaScanner.scanWithGroupings()        [compute → 后台 isolate]
  │   ├─ _walkVideoFilesSync()  逐层遍历，符号链接去重，坏目录隔离
  │   └─ _splitIntoTitleGroups() 按「清洗后标题」把混合目录拆成逻辑分组
  ▼
List<LocalMediaFolder>（path 可能是 dir，也可能是 dir/标题 的逻辑路径）
  │ MediaController.scrapeAll() / MagnetController._runAutoScrape()
  ▼
MediaScraper.scrapeFolder()
  ├─ _buildCandidates()   生成最多 6 个关键词（含 season/year 提示）
  ├─ BangumiApi.bangumiSearch(kw, limit: 20)   ← 逐个串行请求
  ├─ _bestMatch() → _scoreItem() → _nameSimilarity()  打分取最高
  └─ 全落空 → _scrapeByImageTrace()  ffmpeg 抽帧 → trace.moe → AniList 标题再搜
  ▼
FolderScrapeResult → MediaController.scrapeResults（ObservableMap）
  │ MediaScrapeStore.save()   JSON 持久化到设置盒
  ▼
消费：媒体库展示 / 播放历史 / 弹幕关联 / 缺集检测 / 磁力自动入库
```

### 1.2 各层职责与关键实现

| 层 | 文件 | 关键实现 |
| --- | --- | --- |
| 扫描 | `local_media_scanner.dart` | `compute(_scanRoot)` 后台 isolate；逐层 `listSync`（不用 recursive，坏目录只 skip 该层）；`resolveSymbolicLinksSync` 防 junction 环 |
| 分组 | `local_media_scanner.dart:_splitIntoTitleGroups` | 按 `cleanName(file.name)` 归一化后分组；**单标题 = 整目录一个 folder**（保持旧行为），**多标题 = 拆 `dir/标题` 逻辑分组**；产出 `titleKeys` 快照供旧键迁移 |
| 去重 | `scanAllWithGroupings` | 多根目录按 `localMediaPathKey`（Windows 小写）按文件去重 |
| 清洗 | `media_scraper.dart:cleanName/_process` | 剥 `[] () （） 【】 {}`；剥分辨率/编码/集数/来源/语言标记；全角标点归一；`.`→空格；方括号内藏标题时 `_longestBracketTitle` 兜底 |
| 季/年 | `parseSeason` / `parseYear` | 支持 `S2` / `Season 2` / `第二季` / `第二期` / `2期`；年份取 1990~now+1 |
| 候选 | `expandKeyword` / `_buildCandidates` | 逐层剥离：原标题 → 去季数 → 去副标题；每层出「简体 + 原文」两版，**简体优先**（Bangumi 条目名以简体/日文原名为主）；上限 `_kMaxKeywordVariants = 6`；`_kGenericTitles` 拦截 `test`/`新建文件夹` 等占位名；短名/占位时回落「首个视频文件名」与「去方括号原名」 |
| 打分 | `_bestMatch` / `_scoreItem` / `_nameSimilarity` | 对 `item.nameCn`、`item.name`、`item.alias[]` 分别算相似度取最大；季数吻合 +0.18 / 不符 −0.12 / 无标记 −0.06；年份吻合 +0.08；**阈值 0.4 以下判未命中** |
| 相似度 | `_nameSimilarity` | 相等 1.0；包含关系 0.9（短⊂长）/ 0.75（长⊃短）；否则最长公共子串 `lcs/name.length ≥ 0.6` → `×0.8` |
| 图片兜底 | `_scrapeByImageTrace` + `video_frame_extractor.dart` | `localMediaTraceFallback` **默认 true**；ffmpeg 抽 30%~70% 处一帧 → trace.moe（`similarity ≥ 0.8`）→ AniList 的 chinese/romaji/english/native/synonyms **逐个再搜 Bangumi** → 全失败则用 AniList 信息直出（`source=anilist`，`playbackId` 取负，不参与同步） |
| 持久化 | `local_media_models.dart:MediaScrapeStore` | `路径 → MediaScrapeInfo` JSON 存设置盒；文件夹级 `localMediaScrapeResults` + 文件级 `localMediaFileScrapeResults` 两层，播放时文件级优先 |
| 编排 | `media_controller.dart:scrapeAll` | `onlyUnmatched` 默认开（只搜未匹配）；未匹配/出错的路径**清除旧结果**；已匹配的原样保留；支持 `cancelScrape()` |

### 1.3 触发点

- 媒体库页手动「搜刮全部 / 搜刮未匹配」（`media_library_page.dart:418`）
- 单个文件夹手动匹配对话框，推荐关键词复用 `expandKeyword`（`media_library_page.dart:2629`）
- 磁力任务完成后自动搜刮 `MagnetController._runAutoScrape`，用 `scrapeAttempted` 标记防每 2s 重发；命中后按 `magnetAutoImportConfidence` 决定是否自动入库

---

## 二、问题清单（按优先级）

### P1 — 影响召回或产生错误匹配

| # | 问题 | 位置 | 说明 | 建议 |
| --- | --- | --- | --- | --- |
| P1-1 | **搜索接口丢弃无中文名的条目** | `bangumi_api.dart:452`<br>`if (bangumiItem.nameCn != '') bangumiList.add(...)` | 纯日文原名、无 `nameCn` 的冷门条目**永远搜不到**，而这类恰恰最需要搜刮 | 为搜刮单开一条不过滤的搜索路径（或加 `includeUntranslated: true` 参数），UI 搜索保持原行为 |
| P1-2 | **排序用 `heat`，冷门番进不了 top20** | `bangumi_api.dart:406` `sort = 'heat'` | 搜刮要的是「文本最像」，不是「最热门」；热门番的剧场版/衍生条目会挤掉正片 | 搜刮场景改用相关度排序（Bangumi 的 `match`/`rank`），或先按 `limit=20` 取两页再打分 |
| P1-3 | **子串分支无长度门槛 → 短名条目被误命中** | `media_scraper.dart:715` `keyword.contains(name) → 0.75` | 只要条目名是关键词的连续子串就给 0.75，远超 0.4 阈值。例：关键词「关于我转生变成史莱姆这档事」vs 条目「史莱姆」→ 直接命中 | 加绝对长度门槛（如短名 ≤4 字要求相等或相似 ≥0.9），并按 `min(lenA, lenB)` 归一化 |
| P1-4 | **LCS 分母用 `name.length`** | `media_scraper.dart:722` `ratio = lcs.length / name.length` | 关键词越长、条目名越短，比值越容易满分（同样导致长名误配短条目）；且 `×0.8` 后最高 0.8 仍 > 0.4 | 改用 `lcs.length / max(lenA, lenB)` 或 Jaccard；并把 0.6 门槛提到 0.7+ |

### P1 — 请求成本

| # | 问题 | 位置 | 说明 | 建议 |
| --- | --- | --- | --- | --- |
| P1-5 | **全串行，最坏 6N 次往返** | `media_scraper.dart:759` `for (... ) await scrapeFolder()`；`scrapeFolder` 内再串行遍历候选 | 200 个未匹配文件夹 × 6 候选 = 最多 1200 次串行 HTTP；中途无并发、无超时、无提前短路 | 文件夹级有限并发（3~5，用 `Future.wait` 分批）；单文件夹内命中高置信度（如 ≥0.9）即停 |
| P1-6 | **无任何缓存** | 全局 | 同一番剧的多个目录/多季/多分组会重复搜同一关键词；重跑「搜刮未匹配」时上一轮已查过的关键词也重查 | 加进程内 LRU：`keyword → List<BangumiItem>`（正缓存）+ 负缓存（`keyword → notFound`，可带 TTL） |
| P1-7 | **图片兜底默认开且无节流** | `settings_keys.dart:1061` 默认 `true`；`_scrapeByImageTrace` | 每个未匹配文件夹：1 次 ffmpeg 抽帧 + 1 次 trace.moe + **最多十余个 AniList 标题各一次 Bangumi 搜索**。批量时成本爆炸，且 trace.moe 有速率限制 | ① 默认关闭或限制「每批最多 N 次 / 仅手动触发」；② trace 结果按帧 hash 缓存；③ AniList 标题去重后限量（如取 chinese + romaji + native 三条） |

### P2 — 准确率与健壮性

| # | 问题 | 位置 | 说明 | 建议 |
| --- | --- | --- | --- | --- |
| P2-1 | 置信度阈值 0.4 **硬编码** | `media_scraper.dart:662` | 与磁力侧的 `magnetAutoImportConfidence` 设置项不统一，用户无法调 | 提升为设置项（媒体库搜刮阈值），复用既有 key 或新增 |
| P2-2 | **无「次优差距」校验** | `_bestMatch` 仅取最高分 | 最高 0.42 / 次高 0.41 也照样采纳 | 要求 `best - second ≥ 0.1`，否则判未命中并继续下一候选 |
| P2-3 | 候选短路风险 | `scrapeFolder` 命中即 return | 第一个候选（简体去季数版）若误配 0.75，后面更精确的候选不再尝试 | 收集全部候选结果取全局最优，或首候选提高阈值（≥0.9 才短路） |
| P2-4 | **清洗漏洞：点号分隔的尾部集数剥不掉** | `media_scraper.dart:204` vs `231` | `[-_]\d{1,3}$` 在 `.`→空格 **之前**执行，`Show.Name.-.01` 中 `-` 与 `01` 隔着 `.` 匹配不到，最终关键词残留 `Show Name 01` | 在 `.`→空格 之前先剥 `[.\-_]\s*\d{1,3}\s*(v\d+)?\s*$`，或把点号归一提前 |
| P2-5 | 无负缓存 / 无重试退避 | `scrapeFolder` 的 `catch` 只吞异常 | `notFound` 每轮重搜；网络抖动时整批连续失败，且每个 folder 都照发 | 指数退避 + 连续失败熔断（如连错 5 次暂停并提示） |
| P2-6 | 搜刮结果**无失效机制** | `MediaScrapeStore` | 文件夹改名/移动/删除后，旧路径键永久残留（分组迁移只覆盖 `titleKeys` 场景） | 扫描后对已不存在的路径做清理，或按 `identityKey` 做路径迁移 |
| P2-7 | `_normalize` 去掉 `x` `+` `*` | `media_scraper.dart:308` | 会误伤含这些字符的正名（如 `HUNTER×HUNTER` 的 ×、带 `x` 的标题） | 仅对装饰性符号去重，保留 `×`/`x` 或单独归一 `×→x` |
| P2-8 | LCS 性能 | `_longestCommonSubstring` | 每个 item × 每个别名都新建 `O(n·m)` 二维 `List`；`alias` 多的条目开销明显 | 滚动数组（两行）+ 长度预筛（`min(len) < 阈值` 直接跳过） |
| P2-9 | 缺「中文名 → 日文原名」的替代路径 | 全局 | 中文关键词搜不到只有日文名的条目时（P1-1 修复前尤其明显），除图片识别外无兜底 | 增加 AniList GraphQL 标题桥接：拿 romaji/native 再回 Bangumi 搜索（复用 trace 兜底里已有的标题转换逻辑，无需抽帧） |
| P2-10 | 分组键粒度偏细 | `_splitIntoTitleGroups` | 同一部番因命名习惯差异（繁简、副标题有无）仍可能拆成多个分组 → 各搜一次 | 分组时先 `stripSeasonSuffix`/`stripSubtitle` 再归一化，提高聚合率 |

---

## 三、建议实施顺序

1. **先修准确率**：P1-3 + P1-4（相似度归一化与长度门槛）+ P2-2（次优差距）。改动集中在 `_nameSimilarity` / `_bestMatch`，测试覆盖好（`test/media_scraper*.dart` 共 4 个），风险最低。
2. **再修召回**：P1-1 + P1-2（搜索接口）。注意 `bangumiSearch` 被 UI 搜索共用，需加参数隔离，避免影响线上搜索体验。
3. **然后降成本**：P1-6 缓存 → P1-5 并发 → P1-7 兜底节流。这三项决定大媒体库的可用性。
4. **最后补健壮性**：P2-4 清洗、P2-5 退避、P2-6 失效清理、P2-9 桥接。

## 四、回归保障

现有测试（`test/`）已覆盖较多搜刮行为，改造时应同步更新：

- `media_scraper_test.dart` — 清洗与基础打分
- `media_scraper_anime_names_test.dart` — 真实番名匹配
- `media_scraper_ani_traditional_test.dart` — 繁体标题（台配源）
- `media_trace_pipeline_test.dart` — trace.moe 兜底链路
- `local_media_scanner_test.dart` — 扫描与分组
- `media_metadata_source_test.dart` — 来源（bangumi / anilist / legacy）持久化

建议为 P1-3/P1-4 新增一组「负例」测试（长关键词 vs 短条目名必须判未命中），这是当前唯一没有防线的误匹配路径。
