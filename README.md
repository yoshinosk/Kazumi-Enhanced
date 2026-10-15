# Kazumi

![Kazumi](static/logo_readme.png)

> [!IMPORTANT]
> **本项目是 [Kazumi](https://github.com/Predidit/Kazumi) 的一个分支版本（fork），基于上游 [2.2.6](https://github.com/Predidit/Kazumi/releases/tag/2.2.6) 版本开发，上游功能已同步至 [2.3.9](https://github.com/Predidit/Kazumi/releases/tag/2.3.9)。**
> 我们在上游项目的基础上进行**功能加强**，重点新增了**本地媒体库**与**磁力下载**能力。
> 🎉 **v1.0.0 已正式发布**，核心功能已基本可用，可前往 [Releases](https://github.com/yoshinosk/Kazumi-Enhanced/releases) 下载体验；项目仍在积极开发中，功能与规则请以[上游仓库](https://github.com/Predidit/Kazumi)为准。

使用 Flutter 开发的基于自定义规则的番剧采集与在线观看程序——在上游 Kazumi 的基础上，重点增强本地媒体库、磁力下载（libtorrent）与播放器能力。

## 支持平台

本分支仅针对以下平台构建与适配：

- Android 10 及以上
- Windows 10 及以上

> 上游还支持 macOS / Linux / iOS / HarmonyOS 等平台，如需使用请前往[上游仓库](https://github.com/Predidit/Kazumi)。

## 功能一览

### 继承自上游的功能

以下能力来自上游 [Kazumi](https://github.com/Predidit/Kazumi)（基于自定义规则的番剧采集与在线观看程序），随上游同步持续更新，规则与用法以上游仓库为准：

- **规则源观看**：基于 Xpath 的自定义规则编辑器、规则导入与分享、多视频源切换
- **番剧浏览**：番剧目录、搜索、时间表
- **播放**：分集播放、硬件加速、高刷新率适配、倍速播放、番剧字幕、Anime4K 实时超分辨率（基础档位）
- **互动与数据**：番剧弹幕、追番列表、播放历史、番剧下载、一起看
- **同步与扩展**：跨设备同步（WebDAV）、无线投屏（DLNA）、外部播放器播放、在线更新、配色方案

### 本分支新增 / 增强的功能

- **本地媒体库**：管理并播放本机已存储的番剧与视频文件——自动扫描分组、元数据搜刮、应用内播放（弹幕 / 历史 / 追番进度联动）、缺集检测一键磁力补集、续播角标、右键菜单管理、外挂字幕自动加载、未匹配封面缩略图、全库空间统计
- **磁力下载**：基于 libtorrent 的内置下载引擎——磁力搜索（Mikan / AnimesGarden，含搜索历史）与 RSS 订阅自动下载、队列调度与限速时段、仅 WiFi 下载、磁盘空间检查、边下边播、下载完成自动搜刮入库、按番剧分组与缺集检测、剪贴板磁力识别、Android 后台下载保活与系统通知
- **播放器增强**：字幕样式自定义（字号 / 加粗 / 颜色 / 描边 / 背景）、音轨与字幕轨道选择、字幕延迟、A-B 循环、播完动作（自动连播 / 单集循环 / 播完暂停）、画面旋转、自定义倍速（0.25 ~ 8x）、Windows 音量最高 200%、快捷键截图保存为文件、Anime4K 六档超分辨率（效率 → 极致）、Windows 渲染器可选（auto / gpu / gpu-next）
- **弹幕增强**：弹幕轴偏移自动检测与推荐校准（按番剧 / 分集记忆，附置信度）、倍速播放弹幕丢失 / 重复修复、弹幕池面板与时间轴快速调整
- **桌面端体验**：全局 ESC 返回、双击标题栏最大化 / 还原、播放画面与媒体库右键菜单、宽窗口侧边栏布局、磁力任务多选批量操作
- **其他**：首页「继续观看」一键续播、时间线「仅显示日漫」筛选、看完自动联动 Bangumi 收藏进度

## 截图

| 本地媒体库 | 磁力下载 | 追番统计 |
| :---: | :---: | :---: |
| ![本地媒体库](static/screenshot/%E5%AA%92%E4%BD%93%E5%BA%93.png) | ![磁力下载](static/screenshot/%E7%A3%81%E5%8A%9B%E4%B8%8B%E8%BD%BD.png) | ![追番统计](static/screenshot/%E8%BF%BD%E7%95%AA%E7%BB%9F%E8%AE%A1.png) |

## 下载

通过本仓库 [Releases](https://github.com/yoshinosk/Kazumi-Enhanced/releases/latest) 选项卡下载：

[![Get it on GitHub](static/svg/get_it_on_github.svg)](https://github.com/yoshinosk/Kazumi-Enhanced/releases/latest)

- **Android**：按设备架构分包，主流 64 位手机选择 `arm64-v8a`，老旧 32 位设备选择 `armeabi-v7a`，模拟器与少数设备选择 `x86_64`；不确定时优先选择 `arm64-v8a`。
- **Windows**：免安装 zip，解压后运行即可；安装包未经代码签名，首次运行如遇 SmartScreen 提示，选择「更多信息 → 仍要运行」即可，如对安全性有顾虑可自行从源码构建。
- 请仅从本仓库 Releases 下载安装包，谨防第三方渠道的捆绑篡改版本。

## 开发状态

本项目已发布 **v1.0.0**，核心功能基本可用，可前往 [Releases](https://github.com/yoshinosk/Kazumi-Enhanced/releases) 获取最新版本；项目仍在积极开发中，接口与行为仍可能在后续提交中发生变化。如需稳定可用的基础功能，请使用上游仓库 [Kazumi](https://github.com/Predidit/Kazumi) 的 Release。

**上游同步进度**：fork 基线为上游 2.2.6，上游功能已按提交逐个内容移植同步至 **2.3.9**，各批次明细与跳过项见 [UPSTREAM_SYNC.md](UPSTREAM_SYNC.md)。

## 更新日志

面向用户的更新日志整理于 [CHANGELOG.md](CHANGELOG.md)（最顶部为最新内容），可前往查看各版本的新功能、优化与修复记录。

## 开发路线与进度

> 以下进度基于当前代码库实际实现情况，仍处于积极开发中，接口与行为可能变化。

### 本地媒体库

- [x] 本地视频文件递归扫描，并按番剧标题特征自动分组（`services/media/local_media_scanner.dart`）
- [x] 本地剧集信息解析与特别篇分类（`utils/local_episode_parser.dart`）
- [x] 媒体库浏览页面（`pages/media/media_library_page.dart`）：搜索、空间统计、自动重扫、Windows 目录实时监听
- [x] 番剧元数据搜刮与匹配（`services/media/media_scraper.dart`）
- [x] 应用内播放、弹幕匹配（文件哈希 / BGM 映射 / 标题检索）、历史续播、续播状态可视化（`MediaResumePoint`）
- [x] 缺集检测 → 一键磁力补集、番剧详情页跳转
- [x] 本地看完联动 Bangumi 收藏 EP 进度（可选开启）、全集看完自动标记「看过」
- [x] 外挂字幕自动加载（mpv `sub-auto=fuzzy`）、多季目录排序、未匹配卡片首帧缩略图
- [x] 详情页直接展示本地资源（`LocalEpisodesSection`）、搜索页本地命中提示、追番角标
- [x] 媒体库番剧右键菜单删除（二次确认列出文件夹 / 视频数 / 体量，递归清理文件与目录、搜刮结果与缩略图缓存）
- [x] 无权限 / 符号链接子目录鲁棒扫描（逐层遍历，单目录失败仅跳过，避开 Windows junction 环导致的无限遍历）
- [x] 占位历史自动迁移到真实番剧条目（修复本地历史以占位番剧落库、重新开启同步后已删历史复活等问题）
- [ ] 媒体库「已看」标记、多端元数据迁移等仍在完善

### 磁力下载

- [x] 基于 libtorrent 的内置下载引擎（`services/magnet/libtorrent_engine.dart`，libtorrent_flutter）
- [x] 磁力链接解析、下载任务管理与进度持久化（`services/magnet/magnet_download_service.dart`）
- [x] Tracker 列表自动更新（`services/magnet/tracker_updater.dart`）
- [x] 磁力搜索源（Mikan / AnimesGarden）与订阅（封面、自动下载开关与去重）
- [x] 手动添加磁力链接 / 种子、剪贴板识别、文件选择（部分下载）、删除任务可选删文件、搜索与清理
- [x] 下载完成后自动搜刮并入库（`magnetAutoScrapeOnComplete`，可选开启；手动「匹配番剧」/「重新搜刮」）
- [x] 并发限制与队列调度（`queued` 排队状态、立即开始）、错误/元数据超时重试、手动校验文件
- [x] 边下边播（内置 HTTP 流服务器，不写历史）
- [x] 限速时段、按任务限速缓存、仅 WiFi 下载策略
- [x] 磁盘空间检查、下载完成/失败系统通知、Android 后台前台服务保活
- [x] 下载页「按番剧分组」视图（缺集检测联动）、「已入库」状态可视化
- [x] 种子元数据持久化（`.torrent` 导出缓存，重启 / 重试优先加载、磁盘续做种 / 续传）
- [x] 同磁力链去重（info-hash 归一化）、防「刚创建就假做种」（可疑瞬时报完成强制 recheck）
- [x] 下载列表按添加时间倒序、已完成任务本地播放（非边下边播）、集数范围标签
- [x] 磁力 RSS 订阅自动检查间隔（30 分钟 ~ 1 天）+ 打开即检查并自动下载
- [x] 做种指定时长最低 1 小时
- [ ] 任务级限速 UI、移动端存储权限进一步适配等仍在完善

### 播放器增强

- [x] Anime4K 六档超分辨率（效率 Mode C / 降噪 Mode C+A / 均衡 Mode B / 质量 Mode A / 均衡增强 Mode B+B / 极致 Mode A+A），档位链路按上游 GLSL 模板编排（`lib/pages/player/controller/player_super_resolution.dart`）
- [x] 新增 Anime4K 着色器（Restore_CNN_Soft、Upscale_Denoise_CNN_x2，MIT），并随更新整体覆盖重写（着色器版本文件 `anime_shaders/.shader_bundle_version`，旧用户升级自动生效）
- [x] Windows 端视频渲染器选项（自动 / gpu / gpu-next；随包 libmpv 内置 libplacebo 与 Vulkan）
- [x] 弹幕轴偏移推荐检测：基于弹幕时间分布头尾空白 / 越界信号与密度形态校验，给出推荐偏移与置信度，避免静默片头 / 片尾空窗误判（`lib/utils/danmaku_axis_checker.dart`）
- [x] 弹幕轴偏移按「番剧:分集」作用域持久化，单集检测结果不再污染其他剧集
- [x] 倍速播放弹幕丢失 / 重复修复（逐 tick 补发区间内整秒弹幕，跳变超 5 秒视为 seek）
- [ ] 超分辨率档位 UI 进一步打磨（如自定义链路）等仍在完善

### 近期计划（TODO）

- 媒体库「已看」标记与多端元数据迁移
- 任务级限速 UI、移动端存储权限进一步适配
- 超分辨率档位 UI 进一步打磨（自定义链路）
- 性能与稳定性打磨，补充单元测试（弹幕轴偏移、超分着色器等已补回归测试）

## 从源码构建

环境要求：Flutter 3.47.2（版本锁定，见 `pubspec.yaml` 的 `environment.flutter`）。

```bash
# 拉取依赖并生成代码
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Windows
flutter build windows --release

# Android（按架构分包）
flutter build apk --release --split-per-abi
```

- 弹幕匹配依赖 DanDanPlay 开放平台，凭据通过 `--dart-define` 注入（`DANDANAPI_APPID` / `DANDANAPI_KEY`），需自行申请后参考 `tools/build_windows_local.ps1` 与 `tools/build_android_local.ps1` 的注入方式传入；未提供时仅弹幕匹配相关功能不可用，其余功能不受影响。
- 编译依赖托管在 MavenCentral / GitHub / SourceForge 上的资源，如位于中国大陆，可能需要设置恰当的镜像地址。
- `third_party/libtorrent_flutter` 与 `third_party/ech_http` 为本地 vendored 依赖（经 `dependency_overrides` 指向），修改其中的原生代码后需重新编译原生库。

## 常见问题

### Q: 为什么少数番剧中有广告？

A: 本项目未插入任何广告，广告来自视频源。请不要相信广告中的任何内容，并尽量选择没有广告的视频源观看。

### Q: 为什么我启用超分辨率功能后播放卡顿？

A: 超分辨率功能对 GPU 性能要求较高，如果没有在高性能独立显卡上运行，请尽量选择效率档而非质量档。对低分辨率视频源而非高分辨率视频源使用超分，也可以降低性能消耗。

### Q: 为什么播放视频时内存占用较高？

A: 本程序在视频播放时会尽可能多地将视频缓存到内存，以提供较好的观看体验。如果内存较为紧张，可以在播放设置中启用低内存模式来限制缓存。

### Q: 为什么少数番剧无法通过外部播放器观看？

A: 部分视频源的番剧使用了反盗链措施，这可以被 Kazumi 解决，但无法被外部播放器解决。

### Q: 为什么磁力搜索没有结果或速度很慢？

A: 磁力搜索依赖第三方搜索源，下载速度取决于 BT 网络中该资源的做种数量，冷门资源无速度属正常现象。可以尝试更新 tracker 列表、稍后重试，或改用其他搜索源。

### Q: 为什么我的自定义规则无法实现检索，或无法观看？

A: 目前对 `Xpath` 语法的支持并不完整，仅支持以 `//` 开头的选择器，建议参照示例规则构建自定义规则。若可以检索但无法观看，可尝试关闭规则中的「使用内置播放器」选项，改用 WebView 播放提高兼容性；内置播放器可用时建议启用，以获得更流畅且带有弹幕的体验。

## 贡献指南

欢迎通过 Issue 与 Pull Request 参与本分支的开发。

- **问题反馈**：请通过 Issue 描述复现步骤与所处环境（平台、构建版本），便于定位。
- **分支策略**：从本仓库的默认分支切出功能分支进行开发，PR 合并回默认分支。
- **代码风格**：遵循 Dart / Flutter 规范，本项目已包含 `analysis_options.yaml`，提交前请通过 `flutter analyze`。
- **与上游同步**：本分支会定期从上游 [Kazumi](https://github.com/Predidit/Kazumi) 同步改动；涉及上游文件冲突时，以本分支的功能加强目标为准，必要时手动解决。
- **功能范围**：本分支聚焦本地媒体库与磁力下载的能力增强，相关改进优先；通用功能建议尽量回馈上游。
- **规则贡献**：番剧规则请提交至上游规则仓库 [KazumiRules](https://github.com/Predidit/KazumiRules)，规则编写教程见上游[规则开发文档](https://kazumi.app/docs/rules/develop-rules)。

## 免责声明

- 本项目基于 GNU 通用公共许可证第 3 版（GPL-3.0）授权。在法律允许的最大范围内，作者和贡献者不对本软件的适用性、可靠性或准确性作出任何明示或暗示的保证，亦不承担任何因使用本软件而产生的直接、间接、偶然、特殊或后果性的损害赔偿责任。
- 本项目是一个本地媒体播放与下载工具，本身不存储、不上传、不分发任何影视内容；所有内容均来自用户自行配置的第三方规则、搜索源或种子链接，与本项目无关。因使用本项目而产生的数据和缓存，建议在 24 小时内自行清除。
- 使用本项目时请遵守所在地法律法规，不得进行任何侵犯第三方知识产权的行为；因使用本软件下载、播放内容所产生的法律责任由使用者自行承担。
- 本项目仅供学习交流使用，请勿用于商业用途；如本项目的任何部分侵犯了您的合法权益，请通过 Issue 联系，我们将及时处理。

## 网络行为与隐私

- 本软件不收集任何用户数据，不使用任何遥测组件；观看记录、下载任务等数据仅保存在本地。
- 以下功能会在你主动使用时与第三方服务通信：弹幕匹配（弹弹play开放平台）、追番与收藏联动（Bangumi API）、跨设备同步（你自行配置的 WebDAV 服务）、在线更新检查（GitHub API）。
- 使用磁力下载时，本软件会按照 BitTorrent 协议与 tracker、DHT 网络及其他 peer 交换必要的连接信息（如 IP 地址），这是 P2P 下载的固有行为。

## 许可证

本项目基于 [GNU 通用公共许可证 v3.0（GPL-3.0）](https://www.gnu.org/licenses/gpl-3.0.html) 开源。完整条款见仓库根目录的 [LICENSE](LICENSE) 文件。

- 项目名称「Kazumi」沿用自上游，仅用于标识本分支与上游的渊源，相关权利归上游作者所有。
- 本项目应用图标与上游相同，来自插画作者 [Yuquanaaa](https://www.pixiv.net/users/66219277) 发表于 [Pixiv](https://www.pixiv.net/artworks/116666979) 的作品，版权归原作者所有。该图标为上游获得作者授权使用的非自由素材，本分支基于与上游的 fork 关系沿用；如原作者或上游作者提出异议，本分支将及时更换图标。
- 本项目内嵌字体为 [MiSans](https://hyperos.mi.com/font/zh/details/sc/) 字体，由 [Xiaomi](https://www.mi.com/index.html) 开发和拥有版权。
- 应用内「关于 → 第三方许可证」页面列出了所有依赖组件的开源许可；Anime4K 着色器基于 MIT 许可随包分发。

## 致谢

特别感谢上游 [Kazumi](https://github.com/Predidit/Kazumi) 的作者 [Predidit](https://github.com/Predidit) 与所有上游贡献者，本分支的一切增强都建立在他们的工作之上。

- [XpathSelector](https://github.com/simonkimi/xpath_selector)：规则解析的基石
- [弹弹play](https://www.dandanplay.com/)：弹幕交互来自弹弹play开放平台
- [Bangumi](https://bangumi.tv/)：番剧元数据来自 Bangumi 开放 API
- [Anime4K](https://github.com/bloc97/Anime4K)：实时超分辨率
- [media-kit](https://github.com/media-kit/media-kit)：跨平台媒体播放能力
- [libtorrent](https://github.com/arvidn/libtorrent)：磁力下载引擎
- [Mikan](https://mikanani.me/) 与 [AnimesGarden](https://animes.garden/)：磁力搜索源
- [Hive CE](https://pub.dev/packages/hive_ce)：持久化存储

## 上游项目

- 上游仓库：[Predidit/Kazumi](https://github.com/Predidit/Kazumi)
- 规则仓库：[Predidit/KazumiRules](https://github.com/Predidit/KazumiRules)
