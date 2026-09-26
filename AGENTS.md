# Kazumi 项目规则

## 项目概况

- 本项目是 [Kazumi](https://github.com/Predidit/Kazumi) 的增强分支（fork 自上游 2.2.6，上游功能已同步至 2.3.4，进度见 `UPSTREAM_SYNC.md`）：在上游番剧在线观看（插件源解析）的基础上，重点增强**本地媒体库**、**磁力下载（libtorrent）**与**播放器**能力。
- 技术栈：Flutter **3.47.2**（`pubspec.yaml` 精确锁定）+ Dart ≥ 3.10；状态管理 **MobX**（`mobx_codegen` 生成 `.g.dart`，生成产物需提交）；存储 **Hive CE**；播放内核 **media_kit**（mpv，Predidit fork，pubspec 固定 git ref）；弹幕 canvas_danmaku；路由与依赖注入 **flutter_modular**（`lib/pages/router.dart`、`lib/app_module.dart`）。

## 平台约束（重要）

- 本项目的所有修改**只考虑 Android 和 Windows** 两个平台。
- 除非用户明确要求，不要修改或关心 iOS、macOS、Linux、Web 平台的代码与配置（如 `ios/`、`macos/`、`linux/`、`web/` 目录）。
- 新增依赖或平台相关代码时，只保证 Android 和 Windows 可用。
- 桌面端判断使用 `lib/utils/device.dart` 的 `isDesktop()` 等工具；写平台差异逻辑时注意 Android / Windows 双端行为一致。

## 目录速览

- `lib/pages/` 页面 UI（播放器在 `lib/pages/player/`，播放核心为 `player_controller.dart` 与 `controller/`）；`lib/services/` 服务层（`magnet/` 下载引擎、`media/` 媒体库、`sync/` 同步、`player/`、`storage/` 设置存储等）；`lib/modules/` MobX 模型与控制器；`lib/request/` 网络层；`lib/repositories/` 数据仓库；`lib/bean/` 通用组件；`lib/plugins/` 插件体系；`lib/webview/` WebView 视频解析（Android / Windows 双实现）。
- `third_party/libtorrent_flutter/`：vendored 的 libtorrent Flutter 封装（原生 C++ 桥 + prebuilt so/dll，经 `dependency_overrides` 指向本地路径，修改原生代码后需重新编译原生库）。
- `tools/`：本地构建与辅助脚本；`tools/_flutter_sdk/` 是 git-ignored 的本地 Flutter SDK（已加入 analyzer exclude，其中的报错无需关心）。
- `UPSTREAM_SYNC.md`：上游同步进度台账（按批次、逐上游提交登记状态），同步上游前先阅读。

## 常用命令

- `flutter analyze`：提交前必须无新增 error / warning。
- `flutter test`：改动涉及对应测试时必须全部通过（测试在 `test/`）。
- `dart run build_runner build --delete-conflicting-outputs`：**改动 MobX（`@observable` / `@action`）或 Hive 模型后必须重跑**，漏跑会导致字段不响应、action 未包装等运行时异常。
- `tools/build_windows_local.ps1`：Windows release 构建；`tools/build_android_local.ps1`：Android APK 构建。两者读取 git-ignored 的 `local_dandan_credentials.env` 注入 `DANDANAPI_APPID` / `DANDANAPI_KEY` dart-defines（文件缺失时警告并继续构建）。
- `python tools/fetch_upstream.py <sha> <rel_path>...`：按 commit 拉取上游文件到本地镜像（上游同步辅助，进度记录见 `UPSTREAM_SYNC.md`）。

## Git 约定

- 日常开发在 `dev` 分支，`main` 为主分支（PR 目标）；提交信息用中文 + conventional 前缀（`feat:` / `fix:` / `docs:` / `refactor:`）。
- `local_dandan_credentials.env`（`local_*.env`）与 `tools/_flutter_sdk/` 已 git-ignored，不要提交，也不要把其中的凭据写入代码。

## 修改日志（必须）

- `CHANGELOG.md` **面向最终用户阅读**：只记录用户可感知的变化（新功能、体验优化、问题修复、上游同步）；纯开发侧改动（内部重构、文档、构建脚本、CI 等）**不写入**。
- 每次有用户可感知的修改后，**必须**在 `CHANGELOG.md` **最顶部**追加条目；同一天的多次修改**合并进同一日期章节**（当天章节已存在时，直接在其中追加条目即可）。
- 每条以「新增：」「优化：」「修复：」「同步上游 …」开头，用一句话讲清用户视角的变化与效果；**不写实现细节、不列文件清单**，技术细节放在提交信息与代码注释里。
- 格式示例（日期格式 `年.月.日`）：

```markdown
## 2026.9.28

- 新增：播放器支持 xxx
- 修复：Windows 上 xxx 的问题
```

## 验证

- 修改前阅读 `analysis_options.yaml`，遵循项目 Dart / Flutter 规范（flutter_lints；`**/*.g.dart` 等生成文件已排除分析）。
- 修改完成后运行 `flutter analyze`，确保无新增警告或错误。
- 有相关测试时运行 `flutter test` 验证。
- 涉及代码行为的修改，运行 `tools/build_windows_local.ps1`，确保在 Windows 本地构建成功；纯文档（Markdown）修改可跳过 analyze / test / 构建。
- 每次修改完后提交改动的代码。
