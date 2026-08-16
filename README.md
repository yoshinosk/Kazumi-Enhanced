# Kazumi

![logo](assets/images/logo/logo_rounded.png)

> [!IMPORTANT]
> **本项目是 [Kazumi](https://github.com/Predidit/Kazumi) 的一个分支版本（fork），基于上游 [2.2.6](https://github.com/Predidit/Kazumi/releases/tag/2.2.6) 版本开发。**
> 我们在上游项目的基础上进行**功能加强**，重点新增了**本地媒体库**与**磁力下载**能力。
> ⚠️ **当前正处于开发阶段，相关功能尚未完成**，可能存在不稳定或不可用的情况，请勿用于生产环境。功能与规则请以[上游仓库](https://github.com/Predidit/Kazumi)为准。

## 项目特点

- **分支版本**：基于 [Kazumi](https://github.com/Predidit/Kazumi) 的增强分支，继承其番剧采集与在线观看能力。
- **本地媒体库**：管理并播放本机已存储的番剧与视频文件，自动扫描分组、元数据搜刮、弹幕/历史/进度联动、缺集磁力补集。
- **磁力下载**：基于 libtorrent 的内置下载引擎，支持订阅、队列调度、限速、边下边播、自动入库与 Android 后台下载。

## 开发状态

本项目尚在积极开发中，核心功能已基本可用，但接口与行为仍可能在后续提交中发生变化。如需稳定可用的基础功能，请使用上游仓库 [Kazumi](https://github.com/Predidit/Kazumi) 的 Release。

## 更新日志

每次修改后会在 [CHANGELOG.md](CHANGELOG.md) 最顶部追加更新日志，包含修改说明与涉及文件，可前往查看完整的开发与修复记录。

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
- [ ] 任务级限速 UI、移动端存储权限进一步适配等仍在完善

### 近期计划（TODO）

- 提升本地媒体库的番剧匹配准确度，补全封面与元数据
- 媒体库「已看」标记与多端元数据迁移
- 性能与稳定性打磨，补充单元测试

## 贡献指南

欢迎通过 Issue 与 Pull Request 参与本分支的开发。

- **问题反馈**：请通过 Issue 描述复现步骤与所处环境（平台、构建版本），便于定位。
- **分支策略**：从本仓库的默认分支切出功能分支进行开发，PR 合并回默认分支。
- **代码风格**：遵循 Dart / Flutter 规范，本项目已包含 `analysis_options.yaml`，提交前请通过 `flutter analyze`。
- **与上游同步**：本分支会定期从上游 [Kazumi](https://github.com/Predidit/Kazumi) 同步改动；涉及上游文件冲突时，以本分支的功能加强目标为准，必要时手动解决。
- **功能范围**：本分支聚焦本地媒体库与磁力下载的能力增强，相关改进优先；通用功能建议尽量回馈上游。

## 许可证

本项目基于 [GNU 通用公共许可证 v3.0（GPL-3.0）](https://www.gnu.org/licenses/gpl-3.0.html) 开源。完整条款见仓库根目录的 [LICENSE](LICENSE) 文件。

## 上游项目

- 上游仓库：[Predidit/Kazumi](https://github.com/Predidit/Kazumi)
- 规则仓库：[Predidit/KazumiRules](https://github.com/Predidit/KazumiRules)
