# Kazumi 项目规则

## 平台约束（重要）

- 本项目的所有修改**只考虑 Android 和 Windows** 两个平台。
- 除非用户明确要求，不要修改或关心 iOS、macOS、Linux、Web 平台的代码与配置（如 `ios/`、`macos/`、`linux/`、`web/` 目录）。
- 新增依赖或平台相关代码时，只保证 Android 和 Windows 可用。

## 修改日志（必须）

- 每次修改完成后，**必须**在根目录 `CHANGELOG.md` 的**最顶部**追加一条日志。
- 日志格式如下（日期用 `年.月.日`，如 2026.8.14）：

```markdown
## 2026.8.14

- 修复xxx问题
  - 相关文件: lib/xxx/yyy.dart, lib/zzz.dart
```

- 一条日志可以包含多个修改点，每个修改点都要列出涉及的**所有文件**（相对路径）和**修改说明**。

## 验证

- 修改前阅读 `analysis_options.yaml`，遵循项目 Dart / Flutter 规范。
- 修改完成后运行 `flutter analyze`，确保无新增警告或错误。
- 有相关测试时运行 `flutter test` 验证。
- 每次修改完后提交改动的代码。
- 运行`tools/build_windows_local.ps1`，确保在 Windows 本地构建成功。
