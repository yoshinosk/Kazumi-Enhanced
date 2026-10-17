# 《媒体库搜刮策略分析》核验报告

核验对象：`MEDIA_SCRAPER_ANALYSIS.md`（17 条问题：P1-1~P1-7、P2-1~P2-10）
核验方式：逐条对照源码 + Dart 正则/相似度探针 + Bangumi / trace.moe 官方文档
核验时间：2026-10-18

**总结论：17 条中 12 条成立、4 条部分成立、1 条不成立。** 报告对「打分过松、请求成本高、图片兜底无节制」的判断整体准确，但 P1-1 是误报（未读到模型层的中文名回退），P1-5 的支撑论据（无超时、无短路）与代码不符，另有若干计数、行号与测试覆盖描述错误，并漏掉了 7 个可复现的问题。

---

## 一、结论一览

| 编号 | 报告主张（摘要） | 核验 | 关键依据 |
| --- | --- | --- | --- |
| P1-1 | 搜索接口丢弃无中文名条目 | **不属实** | `BangumiItem.fromJson` 已把 `nameCn` 回退为 `name`，过滤条件几乎永不为假 |
| P1-2 | `sort=heat` 让冷门番进不了 top20 | **属实（有条件）** | 默认 `sort='heat'`；仅当关键词命中数 > 20 时才会挤掉正片 |
| P1-3 | 子串分支无长度门槛，短名误命中 | **属实** | `keyword.contains(name)` 直接给 0.75，远高于 0.4 阈值；探针复现 |
| P1-4 | LCS 分母用 `name.length`，长名易配短条目 | **属实** | 探针：`进击的巨人最终季` vs `进击的巨人第二季` → LCS 5/8×0.8=0.5，过阈值 |
| P1-5 | 全串行、最坏 6N、无超时、无短路 | **部分属实** | 串行属实；但网络层有 12~15s 超时、命中即返回；候选上限可达 13 而非 6 |
| P1-6 | 全链路无缓存 | **属实** | `bangumi_api.dart` / `media_scraper.dart` / `request/core` 均无关键词缓存 |
| P1-7 | 图片兜底默认开且无节流 | **属实（比报告更严重）** | 默认 `true` 且 **UI 无开关**；trace.moe 匿名额度 10/分钟、150/天 |
| P2-1 | 0.4 阈值硬编码 | **属实** | 与可调的磁力阈值 0.7 完全独立（语义也不同，见下） |
| P2-2 | 无次优差距校验 | **属实** | `_bestMatch` 只保留最高分，无第二名校验 |
| P2-3 | 候选命中即 return | **属实** | 首个 ≥0.4 的候选直接返回，后续更精确候选不再尝试 |
| P2-4 | 点号分隔集数剥不掉 | **属实（影响有限）** | 探针确认 `Show.Name.-.01` 残留；但 `expandKeyword` 会二次剥离，代价是多一次请求 |
| P2-5 | 无负缓存 / 无退避 | **属实（且漏了磁力侧更严重的一条）** | 搜刮侧无重试；磁力侧网络错误每 2s 无限重试 |
| P2-6 | 搜刮结果无失效机制 | **部分属实** | 应用内删除会清理；仅「外部改名/移动/删除」会留下永久残留 |
| P2-7 | `_normalize` 去掉 `x + *` 误伤正名 | **部分属实** | 机制属实，但 `HUNTER×HUNTER` 不受影响；真实风险是碰撞与 `X`→空串 |
| P2-8 | LCS 每次新建 O(n·m) 二维表 | **属实（实际影响低）** | 分配属实；数据规模（20 条 × 数个别名 × 短标题）下开销可忽略 |
| P2-9 | 缺「中文名→日文原名」桥接 | **属实（作为缺口）** | 仅图片兜底路径有 AniList 标题桥接，纯文本路径没有 |
| P2-10 | 分组键粒度偏细（繁简/副标题） | **部分属实** | 繁简已通过 `toSimplifiedChinese` 归一；副标题、季数差异才会拆组 |

---

## 二、不成立：P1-1「搜索接口丢弃无中文名的条目」

报告引用的是：

```dart
// lib/request/apis/bangumi_api.dart:458（报告写的 452 行）
if (bangumiItem.nameCn != '') {
  bangumiList.add(bangumiItem);
}
```

但 `BangumiItem.fromJson` 在解析阶段已经做了回退：

```dart
// lib/modules/bangumi/bangumi_item.dart:172-174
nameCn: (json['name_cn'] ?? '') == ''
    ? (((json['nameCN'] ?? '') == '') ? json['name'] : json['nameCN'])
    : json['name_cn'],
```

即 `name_cn` 为空时会取 `name`（日文原名）；`name` 再为空（异常条目）才会得到空串。因此该过滤条件实际只丢弃「连原名都没有」的坏数据，**不会丢弃纯日文名条目**。P1-1 应从问题清单中删除。

> 注意：这不代表「中文关键词搜不到只有日文名的条目」这件事不存在——只是原因不是「结果被过滤」，而是「Bangumi 全文检索本身就没有命中」。报告 P2-9 描述的桥接缺口才是真正的问题，保留 P2-9、删除 P1-1 即可。

另有两处小错：文件实际路径是 `lib/request/apis/bangumi_api.dart`（报告只写了文件名），过滤代码在 458 行而非 452 行。

---

## 三、部分成立的四条

### P1-5「全串行，最坏 6N 次往返」——串行属实，三个支撑论据有两个不成立

| 子主张 | 核验 | 依据 |
| --- | --- | --- |
| 文件夹级全串行 | 成立 | `media_scraper.dart:759-777`，`for` 循环内 `await scrapeFolder` |
| 无超时 | 不成立 | 主通道走 `NetworkConfig.fromSettings()`，connect/receive 各 12s（`network_config.dart:11-12`）；官方回退 15s（`bangumi_client.dart:84-85`）；传输层还有总 deadline |
| 无提前短路 | 不成立 | `media_scraper.dart:415-423` 命中即 `return`；跨文件夹也只在每轮循环开头检查取消 |
| 最坏 6N | 低估 | `_kMaxKeywordVariants=6` 是**单次 `expandKeyword`** 的上限；`_buildCandidates` 在短名/占位名时还会追加「首个文件名」展开（再 6 条）+ 去方括号原名，最坏约 **13N** |

真正成立的是「串行且无并发」：200 个文件夹、每个 1~2 个常见候选时，也是 200+ 次串行往返；若每请求 200ms，就是 40s 以上。取消操作也只在「当前文件夹全部候选跑完」后才生效。

### P2-6「搜刮结果无失效机制」——只对外部文件系统变更成立

- 应用内删除根目录：`MediaController.removeFolder()`（`media_controller.dart:686-712`）会按路径前缀清理 `scrapeResults` / `fileScrapeResults`。
- 应用内删除番剧组：`deleteAnimeGroup`（`media_controller.dart:1386-1405`）同样做精确匹配 + 整树前缀清理。
- 扫描时：`scan()` 只做分组键迁移（`_migrateScrapeResultsForRegrouping`，`media_controller.dart:764-803`），**不会**清理已不存在的路径。

所以报告应改为：「在应用外改名/移动/删除后，旧路径键会永久残留」。这是真实问题，但不像报告写得那样无差别。

### P2-7「`_normalize` 去掉 x/+/*」——机制属实，例子举错

`media_scraper.dart:308` 的正则确实包含 `+×x*`。但 `_normalize` 对**关键词和条目名同时**执行，`HUNTER×HUNTER` 两边都会变成 `hunterhunter`，仍然精确匹配，不存在「误伤」。

真实风险是另外两个，报告没说出来：

1. **碰撞**：`xxxHOLiC` → `holic`，与 `HOLiC` 完全相等（探针已验证），不同作品会被判为 1.0。
2. **单字符标题归零**：`X`（CLAMP 的《X》）→ `""`，`_scoreItem` 里 `if (name.isEmpty) continue`，永远无法匹配。

### P2-10「分组键粒度偏细（繁简、副标题）」——繁简这半句是错的

`local_media_scanner.dart:294-298` 的 `_normalize` 第一步就是 `toSimplifiedChinese(title)`，繁简版本会落进同一分组。真正会拆组的是：

- 副标题有无：`无职转生` vs `无职转生～到了异世界就拿出真本事～`（波浪号本身会被剥掉，但副标题文字仍参与归一化，键仍不同）；
- 季数标记：`Show S2` vs `Show`（`cleanName` 不会剥 `S2`）。

---

## 四、成立但需要修正描述的几条

| 编号 | 需要修正的点 |
| --- | --- |
| P1-2 | 「冷门番进不了 top20」是**条件性**的：只有关键词命中数 > 20 时才会发生。长标题通常只有几条结果，正片不会被挤出。降为 P2 或与 P1-3/P1-4 合并处理更合理 |
| P1-4 | 「×0.8 后最高 0.8」不精确：整名被包含时会先走 `contains` 分支（0.75），LCS 分支实际最高略低于 0.8；但只要 LCS 达到条目名长度的 60%，得分就 ≥0.48，已足以越过 0.4，结论不变 |
| P2-4 | 清洗漏洞真实存在（探针确认 `Show.Name.-.01` → `Show Name - 01`），但 `expandKeyword` 的 `stripSubtitle` 会把 ` - 01` 当副标题剥掉，生成第二候选 `Show Name`。实际代价是**多一次无效请求**，不是「搜不到」。另外 `Show.Name.01`（无连字符）确实无兜底，问题比报告举的例子更广 |
| P2-8 | O(n·m) 二维表属实，但单次比较的字符串通常 < 40 字符、条目 20 条、别名数个，估算开销远小于一次 HTTP 请求；作为 P3 微优化即可 |
| P2-1 | 「与磁力侧不统一」需要说明：0.4 是**匹配阈值**，`magnetAutoImportConfidence`（默认 0.7）是**自动入库阈值**，两者语义不同。真正的问题是媒体库搜刮阈值没有暴露给用户 |
| P2-5 | 支撑描述属实，但漏了磁力侧更严重的一条：见下文 S4 |

---

## 五、报告自身的硬伤

1. **P1 数量自相矛盾**：开头写「其中 4 项属 P1」，正文实际列了 7 条 P1。
2. **候选数上限错误**：1.1 与 P1-5 写「最多 6 个关键词」，实际是「每次 `expandKeyword` 最多 6 个」，`_buildCandidates` 可叠加出约 13 个（`media_scraper.dart:561-633`）。
3. **季数解析描述与代码不符**：1.2 写「支持 `2期`」，但 `parseSeason` 的正则 `\b(?:[1-9１-９])(?:期)\b` 在 Dart 里匹配不到 `2期`（`期` 不是 ASCII 单词字符，尾部 `\b` 不成立；探针返回 `false`）。注释里提到的 `1st Season` 也没有实现。**这是报告漏掉的真 bug**。
4. **测试数量与覆盖描述错误**：`test/media_scraper*.dart` 实际只有 3 个（报告写 4 个）；`media_scraper_test.dart` 只测 `cleanName` / `parseSeason` / `parseYear` / `isGenericTitle`，**没有任何打分测试**（报告写「清洗与基础打分」）。事实比报告更糟：`_bestMatch` / `_nameSimilarity` 是私有方法，整个打分链路零直接测试。
5. **P1-5 与 P2-3 自相矛盾**：一处说「无提前短路」，另一处说「命中即 return」。后者才是代码事实。
6. **行号/路径漂移**：P1-1 的 452→458、缺目录；P1-7 的 1061 是 key 字符串、默认值在 1062；页面引用 418/2629 各差 1~2 行。不影响结论，但说明报告不是逐行核对产物。

---

## 六、报告漏掉的问题（本次核验新增）

### S1. `parseSeason` 实际不支持 `2期` / `1st Season`（P2，真实 bug）

```dart
// media_scraper.dart:264-268
final suffix = RegExp(r'\b(?:[1-9１-９])(?:期)\b').firstMatch(base);
```

Dart 的 `\b` 是 ASCII 单词边界，`期` 属于非单词字符，结尾 `\b` 不成立。探针结果：

```text
parseSeason "2期" match: false
parseSeason "2期 01" match: null
```

影响：`2期` 命名的文件夹拿不到季数提示，季数加分/降权失效，容易匹配到第一季。

### S2. 置信度可超过 1.0，UI 会显示「126%」（P3）

`_scoreItem` 最高可返回 `1.0 + 0.18（季数）+ 0.08（年份）= 1.26`（`media_scraper.dart:708`），`_bestMatch` 未 clamp；磁力页直接乘 100 展示（`magnet_controller.dart:921`）。精确匹配 + 季数/年份吻合时会出现大于 100% 的置信度。

### S3. 第 1 季没有季数校验（P2）

```dart
// media_scraper.dart:688
if (season != null && season > 1) { ... }
```

文件夹写 `S1`/`第一季` 时 `season == 1`，整段季数加减分被跳过；条目是第三季也不会被降权，只剩名称相似度兜底。

### S4. 磁力自动搜刮网络错误时每 2s 无限重试（P2）

`_runAutoScrape` 的错误分支刻意不置 `scrapeAttempted`（`magnet_controller.dart:903-910`、`936-939`），而 `_syncCompletedToLibrary` 由 `onChanged` 驱动（约 2s 一轮）。镜像持续失败时，同一任务会每 2 秒重发一轮「6 候选 + 图片兜底」，没有退避或熔断。这比 P2-5 描述的「批量搜刮连续失败」更具体、也更费流量。

### S5. 镜像失败会为每个候选再打一次官方接口（P2，成本翻倍）

`bangumiSearch` 的 catch 分支会回退到 `postDirect`（`bangumi_api.dart:431-446`）。镜像不可用且用户已登录时，每个候选变成 2 次 HTTP；再叠加 6~13 个候选，单文件夹可到 26 次请求。报告的成本模型没有计入这一层。

### S6. trace.moe 有每日配额，不只是速率限制（P1-7 的加重项）

官方文档：匿名/无 token 为 **10 次/分钟、150 次/天**（早期文档为 5/分钟）。一个 200 个未匹配文件夹的媒体库，只要走图片兜底就会在一天内耗尽配额，之后全部 429。报告只写了「有速率限制」，低估了批量场景的后果。

### S7. 图片兜底设置没有 UI 入口

`localMediaTraceFallback` 只在 `settings_keys.dart:1060` 定义、在 `media_scraper.dart:458` 读取；`lib/pages/settings/` 下没有任何引用。用户既不知道它默认开启，也无法关闭。这一点比「默认开」更值得修。

---

## 七、修正后的处理建议

1. **删除 P1-1**，把 P2-9 提为「召回缺口」唯一入口（中文关键词 vs 只有日文名的条目）。
2. **先修打分**（风险最低、收益最直接）：
   - P1-3 加长度门槛（短名必须相等或 ≥0.9）；
   - P1-4 分母改 `max(lenA, lenB)`，门槛提到 0.7；
   - P2-2 加次优差距；
   - S2 clamp 到 1.0；S3 把 `season > 1` 改为 `season >= 1`。
3. **再修召回**：P1-2 改 `sort='match'`（保留 `heat` 作为兜底），只影响搜刮调用，不动 UI 搜索默认值。
4. **降成本**：P1-6 关键词 LRU（正/负缓存）→ P1-5 有限并发 + 候选循环内检查取消 → P1-7 默认关闭 / 加 UI 开关 / 按天配额计数。
5. **健壮性**：P2-4 把点号归一提前或补 `[.\-_]\s*\d{1,3}\s*$` → P2-6 扫描后清理不存在的键 → P2-5 + S4 退避与熔断。
6. **测试**：把 `_bestMatch` / `_nameSimilarity` 抽成 `@visibleForTesting` 纯函数，补负例（长关键词 vs 短条目、跨季、`X` 单字标题）与 `2期` 解析用例。

---

## 八、核验局限

- 未实际调用 Bangumi / trace.moe 接口，P1-2、P2-9 的「实际召回分布」属于代码路径推断，需联网样本验证。
- 未运行 `flutter test`；测试覆盖结论来自直接阅读 `test/` 文件。
- Dart 探针只复刻了 `_nameSimilarity` / `_longestCommonSubstring` 与相关正则，未加载完整 `MediaScraper`（其依赖存储层，纯 Dart VM 不可用），但被复刻部分与源码逐行一致。

---

## 九、修复实施记录（2026-10-18）

按第七节顺序已落地以下改动：

| 项目 | 状态 | 主要落点 |
| --- | --- | --- |
| P1-3 / P1-4 | 已修 | 子串片段加长度 + 占比门槛；LCS 分母改 `max(lenA, lenB)`、门槛 0.7 |
| P2-2 / P2-3 | 已修 | 中低置信度要求次优差距 ≥0.1；候选改为全局最优，仅 ≥0.9 短路 |
| S2 / S3 | 已修 | 置信度 clamp 到 1.0；第一季也参与季数校验 |
| P1-2 | 已修 | 搜刮搜索改 `sort=match`，失败回退 `heat`；UI 搜索不受影响 |
| P1-6 | 已修 | 关键词 LRU + 正/负 TTL 缓存 + 并发 in-flight 去重 |
| P1-5 | 已修 | 文件夹级并发 3；候选循环内响应取消；连续 5 错熔断 |
| P1-7 / S6 / S7 | 已修 | 每批 10 次、每天 100 次；trace 结果缓存；AniList 标题限量 6；设置页开关 |
| P2-4 / S1 | 已修 | 点号集数在 `.`→空格 之前剥离；`2期` / `1st Season` 解析 |
| P2-6 | 已修 | 扫描后清理失效的文件夹级/文件级结果（保守策略，避免误删未挂载磁盘） |
| P2-5 / S4 | 已修 | 搜刮侧连续失败熔断；磁力自动搜刮 5s/10s 退避，3 次后放弃 |
| P2-7 | 已修 | 保留 `x`、`×`→`x`，避免 `xxxHOLiC` / `HOLiC` 折叠 |
| P2-8 | 已修 | LCS 改滚动数组，去掉每对别名的 O(n·m) 二维表 |
| P2-9 / P2-10 / P2-1 | 未实施 | 属于新增召回能力 / 分组策略 / 阈值设置项，留作后续 |

验证情况：

- `dart analyze lib test`：无 error / warning（41 条既有 info）。
- 新增 `test/media_scraper_scoring_test.dart`：覆盖短名负例、跨季负例、次优差距、季数加减、置信度 clamp、点号清洗、`2期` / `1st Season`、`×` 归一化。
- `flutter test` 在本机被 media_kit 的 native assets 构建 hook 阻断（`cl.exe` 命令因环境变量过长被截断，报 `ProcessException`），与本改动无关；测试需在 native hook 可正常构建的环境执行。
- `flutter build windows --debug` 成功（`build\windows\x64\runner\Debug\kazumi.exe`），编译与链接均通过。
- `flutter build windows --release` 走到最终链接时因本机正在运行的 `kazumi.exe`（PID 19540）锁定输出文件报 `LNK1104`；关闭运行中的实例后重跑 `tools/build_windows_local.ps1` 即可完成 release 构建。

