# 检查更新「最新版仍弹窗」问题分析

日期：2026-11-11

## 结论

**版本号比较逻辑本身没有 bug。** 按当前代码与已发布的 v1.0.5 核对，安装 1.0.5 时 `needUpdate('1.0.5', 'v1.0.5')` 返回 `false`，不会弹出"发现新版本"。

但**确实存在会导致"反复弹窗"的机制缺陷**，其中 Windows 便携版（zip）的更新链路最可能造成"我明明更新了却还一直弹"的观感。

## 验证过程与证据

| 验证项 | 方法 | 结果 |
| --- | --- | --- |
| 本地版本来源 | 读 `lib/request/config/api_endpoints.dart:5` | `appBuildName`（Flutter 编译期注入的 pubspec `version` 中 `+` 之前的部分） |
| 注入是否生效 | 在 v1.0.5 发布包 `data/app.so` 中检索 UA 常量 | 命中 `Predidit/Kazumi/1.0.5 (Android) (...)`，证明版本常量为 `1.0.5`，不是 `0.0.0` |
| 本机运行版本 | `build/windows/x64/runner/Release/data/app.so` 同为上法 | 同样为 `1.0.5` |
| 远端最新版本 | GitHub API `releases/latest` | `tag_name = v1.0.5`，非 prerelease，10-25 发布，CI 最终成功 |
| 比较函数 | 读 `lib/utils/version.dart:12` | 已剥离 `v`/`V` 前缀，逐段数字比较，`1.0.5` vs `v1.0.5` 相等 |
| 构建脚本 | `tools/build_*.ps1`、`.github/workflows/release.yaml` | 未传 `--build-name` / `--build-number` 覆写，Flutter 自动注入 pubspec 版本 |

结论：**「最新版仍判定需要更新」在当前代码 + v1.0.5 发布物上不成立。**

## 真实缺陷（按影响排序）

### P1｜Windows 便携版「立即安装」并不会安装

`lib/services/update/auto_updater.dart:439-457`：

```dart
if (Platform.isWindows) {
  if (installationType == InstallationType.windowsMsix) {
    ... launchUrl(fileUri) ...
  } else {
    // windowsPortable：仅用资源管理器打开下载好的 zip
    await Process.start('explorer.exe', [filePath], runInShell: false);
  }
  await Future.delayed(const Duration(seconds: 1));
  exit(0);
}
```

- zip 分支只是**打开压缩包**，随后应用退出，文件留在 `%TEMP%` 目录。
- 提示文案写的是「准备安装更新，应用即将退出...」，用户会以为已经自动装好了。
- 若用户没有手动解压覆盖（或在资源管理器里选了"跳过已存在文件"，`data/app.so` 就不会替换），本地版本永远是旧版 → **每次启动继续弹**。
- 附加问题：`_detectAvailableInstallationTypes()` 在 Windows 返回 `[msix, portable]`，默认推荐类型是 `availableTypes.first`，即 **MSIX**；zip 用户点"更新"默认下载的是 msix，容易装成另一份并存的安装，而不是替换原目录。

### P1｜没有「跳过此版本 / 稍后提醒」记忆

- `autoCheckForUpdates()` 每次启动都会请求一次 GitHub API（`lib/services/update/auto_updater.dart:178`），没有检查间隔。
- `_showUpdateDialog()`（同文件 `205-222`）只处理"不再自动检查"一个开关；对话框的「稍后」按钮（`lib/bean/dialog/update_available_dialog.dart:107-112`）纯粹关闭弹窗，**不记录任何状态**。
- 结果：只要 `needUpdate` 为真（含上面 P1 导致的"假性新版本"），每次启动都会再弹一次，用户感知就是"一直弹"。

### P2｜版本解析遇到非纯数字标签会静默失败

`lib/utils/version.dart:17-20` 使用 `int.parse`：

- tag 若为 `v1.0.6-beta`、`v1.0.6.1-rc1` 这类形式，`int.parse` 抛 `FormatException`。
- `checkForUpdates` 的 `catch` 会 `rethrow`，自动检查只写一条 warning 日志（不弹窗），手动检查则提示"检查更新失败"。
- 现有发布流程只用纯数字 tag，所以目前不触发，但属于脆弱点。

### P2｜规则更新提示可能反复出现

`lib/plugins/plugins_controller.dart:288-294` 的 `_remoteIsNewer` 在比较抛异常时回退为字符串不等判断：

```dart
try {
  return needUpdate(localVersion, remoteVersion);
} catch (_) {
  return localVersion != remoteVersion;
}
```

- 版本字符串带后缀或格式差异时回退分支会误判为"可更新"。
- 表现是启动时反复出现「检测到 N 条规则可以更新」的 toast（`lib/pages/init_page.dart:333-343`），不是对话框，但同样属于"总提示更新"。

### P3｜下载强制要求 SHA256

`lib/services/update/update_downloader.dart` 要求 asset 的 `digest` 为 64 位 hex，否则抛 `ArgumentError('更新缺少有效的 SHA256 校验值')`。v1.0.5 的 asset 带 digest，正常；旧 release（GitHub 早期不带 digest）会直接失败。

## 建议修复方案

1. **记录已提示版本**：新增 setting `lastPromptedUpdateVersion`，同一版本只自动弹一次；对话框增加「跳过此版本」。
2. **检查节流**：记录 `lastUpdateCheckAt`，自动检查最多 24 小时一次（手动检查不受限）。
3. **Windows 便携版更新落地**：下载 zip 后直接解压到临时目录并提示「已解压到 …，请关闭应用后覆盖」；或提供「打开所在文件夹」的明确文案，禁止默认推荐 MSIX 给 zip 安装。
4. **版本比较容错**：用正则提取数字段（如 `RegExp(r'\d+')`），非数字后缀忽略，避免 `int.parse` 抛异常。
5. **默认安装类型按当前安装形态推断**：Windows 下若检测到自身运行在解压目录（非 msix 安装路径），默认选 `windowsPortable`。

## 排查建议

若用户反馈"已是最新仍弹窗"，依次确认：

1. 「关于」页显示的版本号（`lib/pages/about/about_page.dart:124`）。若显示 `0.0.0`，说明构建未注入 `FLUTTER_BUILD_NAME`，属构建环境问题。
2. 弹窗里显示的版本号与关于页版本号是否相同。相同即为真 bug；不同说明本地确实是旧版。
3. Windows 便携版用户确认 `data/app.so` 的修改时间是否真的更新过（这是最常见的"没装成功"）。
