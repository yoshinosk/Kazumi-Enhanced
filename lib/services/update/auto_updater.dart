import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/dialog/update_available_dialog.dart';
import 'package:kazumi/request/clients/download_http_client.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/update/update_download_source.dart';
import 'package:kazumi/services/update/update_downloader.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/version.dart';

enum InstallationType {
  windowsMsix('MSIX'),
  windowsPortable('ZIP'),
  linuxDeb('DEB'),
  linuxTar('TAR'),
  macosDmg('DMG'),
  androidApk('APK'),
  ios('IPA'),
  unknown('未知类型');

  const InstallationType(this.label);

  final String label;

  /// Types without a matching asset are updated from the release page.
  bool get downloadsInApp => getUpdateFilePatterns(this).isNotEmpty;
}

class UpdateInfo {
  final String version;
  final String description;
  final String downloadUrl;
  final String releaseNotes;
  final String publishedAt;
  final InstallationType? installationType;
  final List<InstallationType> availableInstallationTypes;
  final List<dynamic> assets;

  UpdateInfo({
    required this.version,
    required this.description,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    this.installationType,
    this.availableInstallationTypes = const [],
    this.assets = const [],
  });
  InstallationType get recommendedInstallationType {
    if (availableInstallationTypes.isNotEmpty) {
      return availableInstallationTypes.first;
    }
    return installationType ?? InstallationType.unknown;
  }
}

Map<String, dynamic>? getUpdateAssetForType(
    List<dynamic> assets, InstallationType type) {
  final patterns = getUpdateFilePatterns(type).map((p) => p.toLowerCase());

  try {
    final asset = assets.cast<Map<String, dynamic>>().firstWhere((asset) {
      final name = (asset['name'] as String?)?.toLowerCase() ?? '';
      return patterns.every((pattern) => name.contains(pattern));
    });
    return asset;
  } catch (_) {
    return null;
  }
}

String getUpdateFileHashFromAsset(Map<String, dynamic> asset) {
  final digest = asset['digest'] as String? ?? '';
  if (digest.startsWith('sha256:')) {
    return digest.substring(7);
  }
  return '';
}

List<String> getUpdateFilePatterns(InstallationType installationType) {
  switch (installationType) {
    case InstallationType.windowsMsix:
      return ['windows', '.msix'];
    case InstallationType.windowsPortable:
      return ['windows', '.zip'];
    case InstallationType.macosDmg:
      return ['macos', '.dmg'];
    case InstallationType.androidApk:
      return ['android', '.apk'];
    case InstallationType.linuxDeb:
    case InstallationType.linuxTar:
    case InstallationType.ios:
    case InstallationType.unknown:
      return [];
  }
}

class AutoUpdater {
  static final AutoUpdater _instance = AutoUpdater._internal();

  factory AutoUpdater() => _instance;

  AutoUpdater._internal();

  final DownloadHttpClient _downloadClient = DownloadHttpClient.instance;

  List<InstallationType> _detectAvailableInstallationTypes() {
    if (Platform.isWindows) {
      // 默认类型跟随当前安装形态：MSIX 安装在 WindowsApps 目录下，便携版
      // （zip）位于任意解压目录。否则 zip 用户会被默认推荐 MSIX，装成
      // 另一份并存的副本，而不是替换原来的目录。
      final isMsixInstall =
          Platform.resolvedExecutable.toLowerCase().contains(r'\windowsapps\');
      return isMsixInstall
          ? [InstallationType.windowsMsix, InstallationType.windowsPortable]
          : [InstallationType.windowsPortable, InstallationType.windowsMsix];
    }
    if (Platform.isLinux) {
      return [InstallationType.linuxDeb, InstallationType.linuxTar];
    }
    if (Platform.isMacOS) return [InstallationType.macosDmg];
    if (Platform.isIOS) return [InstallationType.ios];
    if (Platform.isAndroid) return [InstallationType.androidApk];
    return [InstallationType.unknown];
  }

  Future<UpdateInfo?> checkForUpdates() async {
    try {
      final data = await _latestRelease();

      if (!data.containsKey('tag_name')) {
        throw Exception('无效的响应数据');
      }

      final remoteVersion = data['tag_name'] as String;
      final currentVersion = ApiEndpoints.version;

      if (needUpdate(currentVersion, remoteVersion)) {
        final assets = data['assets'] as List<dynamic>? ?? [];
        // 仅提供 release 中实际存在对应安装包的安装类型，
        // 避免展示永远找不到下载链接的死选项（如未发布 MSIX 时的 MSIX 项）。
        var availableTypes = _detectAvailableInstallationTypes()
            .where((type) => getUpdateAssetForType(assets, type) != null)
            .toList();
        if (availableTypes.isEmpty) {
          availableTypes = _detectAvailableInstallationTypes();
        }

        return UpdateInfo(
          version: remoteVersion,
          description: data['body'] ?? '发现新版本',
          downloadUrl: '',
          releaseNotes: data['html_url'] ?? '',
          publishedAt: data['published_at'] ?? '',
          installationType: availableTypes.first,
          availableInstallationTypes: availableTypes,
          assets: assets,
        );
      }

      return null;
    } catch (e) {
      KazumiLogger().e('Update: check for updates failed', error: e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _latestRelease() async {
    final raw = await _downloadClient.getPlain(ApiEndpoints.latestApp);
    final data = json.decode(raw);
    if (data is! Map) {
      throw Exception('Invalid update response');
    }
    return Map<String, dynamic>.from(data);
  }

  /// 自动检查更新的最小间隔。启动即检查、且每次启动都检查会让用户在
  /// 没有任何变化时反复看到同一个提示，这里限制为一天一次（手动检查
  /// 不受限制）。
  static const autoCheckInterval = Duration(hours: 24);

  bool _autoCheckInFlight = false;

  Future<void> autoCheckForUpdates() async {
    final autoUpdate = GStorage.getSetting(SettingsKeys.autoUpdate);
    if (!autoUpdate) return;
    if (_autoCheckInFlight) return;
    if (!_shouldAutoCheckNow()) return;

    _autoCheckInFlight = true;
    try {
      final updateInfo = await checkForUpdates();
      // 只有检查成功才记录时间；失败时保留旧值，下次启动仍可重试。
      await GStorage.putSetting(
        SettingsKeys.lastUpdateCheckAt,
        DateTime.now().millisecondsSinceEpoch,
      );
      if (updateInfo == null) return;

      // 同一版本只自动提醒一次：用户点「稍后」后，不会每次启动都被
      // 同一个弹窗打断；需要时仍可从「关于」页手动检查。
      final promptedVersion =
          GStorage.getSetting(SettingsKeys.lastPromptedUpdateVersion);
      if (promptedVersion == updateInfo.version) return;
      await GStorage.putSetting(
        SettingsKeys.lastPromptedUpdateVersion,
        updateInfo.version,
      );

      await _showUpdateDialog(updateInfo, isAutoCheck: true);
    } catch (e) {
      KazumiLogger().w('Update: auto check for updates failed', error: e);
    } finally {
      _autoCheckInFlight = false;
    }
  }

  bool _shouldAutoCheckNow() {
    final lastCheckAt = GStorage.getSetting(SettingsKeys.lastUpdateCheckAt);
    if (lastCheckAt <= 0) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastCheckAt;
    // 时钟回拨（elapsed 为负）时也重新检查，避免长期不再自动检查。
    return elapsed < 0 || elapsed >= autoCheckInterval.inMilliseconds;
  }

  Future<void> manualCheckForUpdates() async {
    try {
      final updateInfo = await checkForUpdates();
      // 手动检查也刷新计时，避免紧接着的启动又自动查一次。
      await GStorage.putSetting(
        SettingsKeys.lastUpdateCheckAt,
        DateTime.now().millisecondsSinceEpoch,
      );
      if (updateInfo != null) {
        _showUpdateDialog(updateInfo, isAutoCheck: false);
      } else {
        KazumiDialog.showToast(message: '当前已经是最新版本！');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '检查更新失败');
    }
  }

  Future<void> _showUpdateDialog(UpdateInfo updateInfo,
      {bool isAutoCheck = false}) async {
    var disableAutoUpdate = false;
    final choice = await KazumiDialog.show<UpdateDialogChoice>(
      builder: (context) => UpdateAvailableDialog(
        updateInfo: updateInfo,
        onDisableAutoUpdateChanged:
            isAutoCheck ? (value) => disableAutoUpdate = value : null,
      ),
    );
    if (disableAutoUpdate) {
      GStorage.putSetting(SettingsKeys.autoUpdate, false);
      KazumiDialog.showToast(message: '已关闭自动更新');
    }
    if (choice != null) {
      _downloadUpdateWithType(updateInfo, choice.type, choice.source);
    }
  }

  Future<void> _downloadUpdateWithType(
      UpdateInfo updateInfo, InstallationType selectedType,
      UpdateDownloadSource source) async {
    try {
      if (!selectedType.downloadsInApp) {
        String releaseUrl = updateInfo.releaseNotes;
        if (releaseUrl.isEmpty) {
          releaseUrl = ApiEndpoints.latestApp;
        }
        launchUrl(Uri.parse(releaseUrl), mode: LaunchMode.externalApplication);
        return;
      }

      final asset = getUpdateAssetForType(updateInfo.assets, selectedType);
      final downloadUrl = getUpdateDownloadUrlFromAsset(asset, source);
      if (asset == null || downloadUrl.isEmpty) {
        KazumiDialog.showToast(message: '没有找到 ${selectedType.label} 的下载链接');
        return;
      }

      final expectedHash = getUpdateFileHashFromAsset(asset);
      final downloadInfo = UpdateInfo(
        version: updateInfo.version,
        description: updateInfo.description,
        downloadUrl: downloadUrl,
        releaseNotes: updateInfo.releaseNotes,
        publishedAt: updateInfo.publishedAt,
        installationType: selectedType,
        availableInstallationTypes: [selectedType],
        assets: updateInfo.assets,
      );

      _downloadUpdate(downloadInfo, expectedHash);
    } catch (e) {
      KazumiDialog.showToast(message: '下载失败: ${e.toString()}');
      KazumiLogger().e('Update: download update failed', error: e);
    }
  }

  Future<void> _downloadUpdate(
      UpdateInfo updateInfo, String expectedHash) async {
    if (_downloadDialogs.isRunning) return;
    await _downloadDialogs.run((task) async {
      _downloadProgress.value = 0;
      final cancelToken = CancelToken();
      final downloadPath = await task.loading(
        action: () => _downloadFile(updateInfo.downloadUrl, updateInfo.version,
            expectedHash, cancelToken),
        onCancel: cancelToken.cancel,
        builder: (context) {
          return AlertDialog(
            title: const Text('正在下载更新'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _downloadProgress,
                  builder: (context, value, child) {
                    return Column(
                      children: [
                        LinearProgressIndicator(value: value),
                        const SizedBox(height: 8),
                        Text('${(value * 100).toStringAsFixed(1)}%'),
                      ],
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => KazumiDialog.dismiss(context: context),
                child: const Text('取消'),
              ),
            ],
          );
        },
      );

      _showDownloadCompleteDialog(downloadPath, updateInfo);
    }, onError: (e, stackTrace) {
      final errorMessage = getUpdateDownloadErrorMessage(e);

      // 下载失败时清掉「已提示」记录，让下次启动仍能提醒用户重试。
      unawaited(GStorage.putSetting(
        SettingsKeys.lastPromptedUpdateVersion,
        '',
      ));

      KazumiDialog.show(
        builder: (context) {
          return AlertDialog(
            title: const Text('下载失败'),
            content: Text(errorMessage),
            actions: [
              TextButton(
                onPressed: () => KazumiDialog.dismiss(context: context),
                child: const Text('确定'),
              ),
            ],
          );
        },
      );

      KazumiLogger().e(
          'Update: download failed | source=${updateInfo.downloadUrl} | '
          '${describeUpdateDownloadError(e, stackTrace)}',
          error: e);
    });
  }

  final ValueNotifier<double> _downloadProgress = ValueNotifier(0.0);
  final _downloadDialogs = KazumiDialogController();

  void _showDownloadCompleteDialog(String filePath, UpdateInfo updateInfo) {
    final isPortableZip = Platform.isWindows &&
        updateInfo.recommendedInstallationType ==
            InstallationType.windowsPortable;
    KazumiDialog.show(
      builder: (context) {
        return AlertDialog(
          title: const Text('下载完成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('新版本 ${updateInfo.version} 已下载完成'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                isPortableZip
                    ? '便携版需要解压后覆盖当前安装目录，应用不会自动退出'
                    : '安装过程中应用将会退出',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '文件位置:',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      filePath,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(),
              child: Text(
                '稍后安装',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            if (isDesktop())
              TextButton(
                onPressed: () {
                  KazumiDialog.dismiss(context: context);
                  _revealInFileManager(filePath);
                },
                child: const Text('打开文件夹'),
              ),
            TextButton(
              onPressed: () {
                KazumiDialog.dismiss();
                _installUpdate(
                    filePath, updateInfo.recommendedInstallationType);
              },
              child: Text(isPortableZip ? '解压更新包' : '立即安装'),
            ),
          ],
        );
      },
    );
  }

  Future<String> _downloadFile(String url, String version, String expectedHash,
      CancelToken cancelToken) async {
    final tempDir = await getTemporaryDirectory();
    return downloadUpdateFile(
      url: url,
      filePath: '${tempDir.path}/${_getFileNameFromUrl(url, version)}',
      expectedHash: expectedHash,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        _downloadProgress.value = total > 0 ? received / total : 0;
      },
    );
  }

  void _installUpdate(
      String filePath, InstallationType installationType) async {
    try {
      if (Platform.isWindows &&
          installationType != InstallationType.windowsMsix) {
        await _extractPortableUpdate(filePath);
        return;
      }

      KazumiDialog.showToast(message: '准备安装更新，应用即将退出...');

      await Future.delayed(const Duration(seconds: 2));

      if (Platform.isWindows) {
        final Uri fileUri = Uri.file(filePath);
        if (await canLaunchUrl(fileUri)) {
          await launchUrl(fileUri);
        } else {
          throw 'Could not launch $fileUri';
        }
        await Future.delayed(const Duration(seconds: 1));
        exit(0);
      } else if (Platform.isMacOS) {
        if (filePath.endsWith('.dmg')) {
          await Process.start('open', [filePath]);
          exit(0);
        }
      } else if (Platform.isAndroid) {
        final result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done) {
          KazumiDialog.showToast(message: '无法打开安装文件: ${result.message}');
          return;
        }
      }
    } catch (e) {
      KazumiDialog.showToast(message: '启动安装程序失败: ${e.toString()}');
      KazumiLogger().e('Update: launch installer failed', error: e);
    }
  }

  /// 便携版（zip）无法在运行中替换自身：把更新包解压到临时目录，再引导
  /// 用户关闭应用后覆盖当前安装目录。
  ///
  /// 此前只调用资源管理器打开 zip 就退出应用，用户容易以为更新已经完成，
  /// 实际 `data/app.so` 仍是旧版，于是每次启动都会继续提示更新。
  Future<void> _extractPortableUpdate(String zipPath) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      KazumiDialog.showToast(message: '更新文件不存在，请重新下载');
      return;
    }

    KazumiDialog.showToast(message: '正在解压更新文件...');
    final target = Directory(
      '${zipFile.parent.path}${Platform.pathSeparator}'
      'kazumi_update_${DateTime.now().millisecondsSinceEpoch}',
    );

    try {
      if (!await target.exists()) {
        await target.create(recursive: true);
      }
      // 路径通过环境变量传入 PowerShell，避免含空格或中文的路径在命令
      // 字符串里被拆开。
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'Expand-Archive -LiteralPath $env:KAZUMI_UPDATE_ZIP '
              r'-DestinationPath $env:KAZUMI_UPDATE_DIR -Force',
        ],
        environment: {
          'KAZUMI_UPDATE_ZIP': zipPath,
          'KAZUMI_UPDATE_DIR': target.path,
        },
      );
      if (result.exitCode != 0) {
        final stderr = '${result.stderr}'.trim();
        throw Exception(stderr.isEmpty ? '解压失败' : stderr);
      }
    } catch (e) {
      KazumiLogger().e('Update: extract portable update failed', error: e);
      KazumiDialog.show(
        builder: (context) {
          return AlertDialog(
            title: const Text('解压失败'),
            content: Text('无法解压更新包：${e.toString()}'),
            actions: [
              TextButton(
                onPressed: () => KazumiDialog.dismiss(context: context),
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
      return;
    }

    KazumiDialog.show(
      builder: (context) {
        return AlertDialog(
          title: const Text('更新包已解压'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('请关闭本应用，然后把解压目录中的文件覆盖到当前安装目录，'
                  '覆盖后重新启动即可完成更新。'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '解压位置:',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      target.path,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(context: context),
              child: const Text('知道了'),
            ),
            TextButton(
              onPressed: () {
                KazumiDialog.dismiss(context: context);
                _revealInFileManager(target.path);
              },
              child: const Text('打开文件夹'),
            ),
          ],
        );
      },
    );
  }

  void _revealInFileManager(String filePath) async {
    try {
      final type = await FileSystemEntity.type(filePath);
      String targetDirOrFile;
      if (type == FileSystemEntityType.notFound) {
        KazumiDialog.showToast(message: '文件或目录不存在');
        return;
      } else if (type == FileSystemEntityType.directory) {
        targetDirOrFile = filePath;
      } else {
        targetDirOrFile = File(filePath).parent.path;
      }

      if (Platform.isWindows) {
        if (type == FileSystemEntityType.file) {
          // /select, 与路径必须作为两个独立参数、且不经 shell 传递：
          // 合并参数或 runInShell 会把含空格的路径破坏，explorer 解析
          // 失败后回退打开默认目录（「我的文档」）。
          await Process.start(
            'explorer.exe',
            ['/select,', filePath.replaceAll('/', r'\')],
            runInShell: false,
          );
        } else {
          await Process.start(
            'explorer.exe',
            [targetDirOrFile.replaceAll('/', r'\')],
            runInShell: false,
          );
        }
      } else if (Platform.isMacOS) {
        if (type == FileSystemEntityType.file) {
          await Process.start('open', ['-R', filePath]);
        } else {
          await Process.start('open', [targetDirOrFile]);
        }
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [targetDirOrFile]);
      } else {
        KazumiDialog.showToast(message: '此平台不支持通过此方法打开文件管理器');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '无法打开文件管理器');
      KazumiLogger().w('Update: reveal in file manager failed', error: e);
    }
  }

  String _getFileNameFromUrl(String url, String version) {
    final uri = Uri.parse(url);
    final fileName = uri.pathSegments.last;

    if (fileName.isNotEmpty) {
      return fileName;
    }
    String extension = '';
    if (Platform.isWindows) {
      extension = '.msix';
    } else if (Platform.isMacOS) {
      extension = '.dmg';
    } else if (Platform.isLinux) {
      extension = '.deb';
    } else if (Platform.isAndroid) {
      extension = '.apk';
    }
    return 'Kazumi-$version$extension';
  }
}
