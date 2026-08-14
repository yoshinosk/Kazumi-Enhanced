# libtorrent_flutter（Kazumi vendor 副本）

Kazumi 本地 vendor 的 `libtorrent_flutter` 1.9.2，用于「重启续做种」修复（详见仓库根目录《重启续做种实施方案.md》）。

## 与上游的差异

1. **原生层**（`src/torrent_bridge.cpp`，`lt_create_session`）：`no_recheck_incomplete_resume` 由 `true` 改为 `false`。
   - 效果：重挂无 resume data 的种子时，libtorrent 校验磁盘已有文件（`mmap_disk_io.cpp` / `posix_disk_io.cpp` 的 `async_check_files`：无 resume data 且磁盘存在任何文件 → `need_full_check`）——完整文件校验后直接做种（不重下），部分文件从已验证字节续传。
   - 注意：**prebuilt 目录下的预编译 DLL 仍是旧行为**，此改动需从源码重编后才生效。
2. **Dart 层**（`lib/src/libtorrent_flutter_base.dart`）：新增能力开关 `static const bool resumeAware`。
   - 使用 prebuilt DLL 构建时保持 `false`（Kazumi 应用层的续做种 gate 不激活，行为与上游一致）；
   - **从源码重编原生库后，将此开关翻为 `true`**。

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
4. 构建成功后，将 `lib/src/libtorrent_flutter_base.dart` 的 `resumeAware` 翻为 `true`，再次构建。

## 验证

重编后按《重启续做种实施方案.md》§3.4「探针 E」验证：重挂完整文件应出现 `checking` 状态、校验后直接做种、期间 `downloadRate ≈ 0`（无网络重下）。
