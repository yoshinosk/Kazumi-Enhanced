# libtorrent_flutter（Kazumi vendor 副本）

Kazumi 本地 vendor 的 `libtorrent_flutter` 1.9.2，用于「重启续做种」修复（详见仓库根目录《重启续做种实施方案.md》）。

## 与上游的差异

1. **原生层**（`src/torrent_bridge.cpp`，`lt_create_session`）：`no_recheck_incomplete_resume` 由 `true` 改为 `false`。
   - 效果：重挂无 resume data 的种子时，libtorrent 校验磁盘已有文件——完整文件校验后直接做种（不重下），部分文件从已验证字节续传。
   - 本仓库 `prebuilt/` 下的 Windows DLL 与 Android .so 均已从本源码重编，此行为在双端生效。
2. **Dart 层**（`lib/src/libtorrent_flutter_base.dart`）：新增能力开关 `static const bool resumeAware = true`（Kazumi 应用层的续做种 gate 激活）。

## Android .so 的重建（2026.10，重要）

**背景**：此前 `prebuilt/android/` 下放的是上游 release v2.0.0 的预编译 .so（libtorrent **2.1.1** 开发版 + 上游另一代 bridge）。它与 vendored Dart 绑定层不同源，引发了连环问题：缺少 `lt_add_trackers` / `lt_export_torrent` 符号、`lt_create_session` 强制要求 `SSL_CERT_FILE` 且 bundle < 100KB 直接抛异常、`resumeAware` 声称开启实际未生效；更严重的是**磁力下载进行数秒后原生层 SIGSEGV 闪退**（内部引擎为 2.1.1 开发版，上游 issue #7/#8 可佐证该系预编译库在 arm64 Android 的崩溃史）。Dart 层为此打了一堆补丁（TrustStore、可选符号降级）才勉强把会话拉起来。

**修复**：用 vendored `src/torrent_bridge.cpp` + 稳定版 **libtorrent 2.0.11**（与 Windows DLL 同版本）+ OpenSSL 3.2.1（静态）从源码重建三个 ABI 的 `liblibtorrent_flutter.so`（NDK 28.2、API 24、`-Wl,-z,max-page-size=16384` 16KB 页对齐、`-static-libstdc++`、`-fvisibility=hidden` 仅导出 `lt_` 符号）。重建后：

- `lt_add_trackers` / `lt_export_torrent` 存在（运行时注入 tracker、.torrent 元数据缓存恢复可用）；
- 不再需要 `lt_set_ssl_cert_path` / `SSL_CERT_FILE`（Dart 层 TrustStore 自动跳过）；
- `no_recheck_incomplete_resume=false`，`resumeAware=true` 在 Android 真实生效。

**重建脚本**：`tools/build_libtorrent_android.sh`（hostprep → prepare → openssl → lt → bridge 五步；工作区 `build_android/` 已 git-ignored）。流程：per-ABI 构建 OpenSSL 静态库（`android-arm64` / `android-arm no-asm` / `android-x86_64`，`no-shared no-tests`）→ CMake + Ninja 交叉编译 libtorrent 2.0.11 静态库（`c++_static`、`static_runtime=ON`、`deprecated-functions=ON`、`encryption=ON`）→ NDK clang++ 链接 bridge。

## Windows 从源码重编步骤

1. 安装 vcpkg 并安装 libtorrent 2.0：
   ```powershell
   git clone https://github.com/microsoft/vcpkg "D:\Program Files\vcpkg"
   & "D:\Program Files\vcpkg\bootstrap-vcpkg.bat"
   & "D:\Program Files\vcpkg\vcpkg.exe" install libtorrent-rasterbar:x64-windows
   ```
2. 删除 `prebuilt/` 目录（或构建时置 `LIBTORRENT_FLUTTER_SKIP_DOWNLOAD=ON`），使 `windows/CMakeLists.txt` 走 `add_subdirectory(src)` 从源码构建。
3. 设置 `VCPKG_ROOT` 环境变量后重新构建 Kazumi：
   ```powershell
   $env:VCPKG_ROOT = "D:\Program Files\vcpkg"
   flutter build windows
   ```

## 验证

重编后按《重启续做种实施方案.md》§3.4「探针 E」验证：重挂完整文件应出现 `checking` 状态、校验后直接做种、期间 `downloadRate ≈ 0`（无网络重下）。
