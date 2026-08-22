import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/pages/magnet/magnet_controller.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:kazumi/services/magnet/libtorrent_engine.dart';
import 'package:kazumi/services/magnet/magnet_search_sources.dart';
import 'package:kazumi/services/storage/storage.dart';

class MagnetSettingsPage extends StatefulWidget {
  const MagnetSettingsPage({super.key});

  @override
  State<MagnetSettingsPage> createState() => _MagnetSettingsPageState();
}

class _MagnetSettingsPageState extends State<MagnetSettingsPage> {
  late String mikanBaseUrl;
  late String defaultSourceId;
  late String animesGardenFansub;
  late bool engineEnabled;
  late String downloadDir;
  late int listenPort;
  late int maxPeers;
  late int maxUploadLimitKb;
  late int maxDownloadLimitKb;
  late int maxActiveDownloads;
  late bool scheduledLimitEnabled;
  late String scheduledLimitStart;
  late String scheduledLimitEnd;
  late int scheduledLimitKb;
  late bool wifiOnly;
  late String seedingStopMode;
  late int seedingStopHours;
  late double seedingStopRatio;
  late bool enableDht;
  late bool enableUpnp;
  late bool forceEncrypt;
  late bool enableIpv6;
  late bool trackerAutoUpdate;
  late int trackerUpdateHours;
  late String trackerSources;
  late bool autoImportToLibrary;
  late String autoImportRoot;
  late bool autoScrapeOnComplete;
  late double autoImportConfidence;
  late bool syncBangumiProgress;
  late bool thumbnailsEnabled;
  late bool watchFolderEnabled;
  late bool diskSpaceCheck;
  late bool groupDownloads;
  late int subscriptionCheckIntervalMinutes;
  bool isPickingDir = false;

  MagnetController get _controller => inject<MagnetController>();

  MediaController get _mediaController => inject<MediaController>();

  @override
  void initState() {
    super.initState();
    mikanBaseUrl = GStorage.getSetting(SettingsKeys.mikanBaseUrl);
    defaultSourceId = GStorage.getSetting(SettingsKeys.magnetDefaultSource);
    if (!MagnetSearchSources.all.any((s) => s.id == defaultSourceId)) {
      defaultSourceId = MagnetSearchSources.mikan.id;
    }
    animesGardenFansub = GStorage.getSetting(SettingsKeys.animesGardenFansub);
    _loadFromSettings();
  }

  void _loadFromSettings() {
    engineEnabled = GStorage.getSetting(SettingsKeys.magnetEngineEnabled);
    downloadDir = GStorage.getSetting(SettingsKeys.magnetDownloadDir);
    listenPort = GStorage.getSetting(SettingsKeys.magnetListenPort);
    maxPeers = GStorage.getSetting(SettingsKeys.magnetMaxPeers);
    maxUploadLimitKb = GStorage.getSetting(SettingsKeys.magnetMaxUploadLimitKb);
    maxDownloadLimitKb =
        GStorage.getSetting(SettingsKeys.magnetMaxDownloadLimitKb);
    maxActiveDownloads =
        GStorage.getSetting(SettingsKeys.magnetMaxActiveDownloads);
    scheduledLimitEnabled =
        GStorage.getSetting(SettingsKeys.magnetScheduledLimitEnabled);
    scheduledLimitStart =
        GStorage.getSetting(SettingsKeys.magnetScheduledLimitStart);
    scheduledLimitEnd =
        GStorage.getSetting(SettingsKeys.magnetScheduledLimitEnd);
    scheduledLimitKb =
        GStorage.getSetting(SettingsKeys.magnetScheduledLimitKb);
    wifiOnly = GStorage.getSetting(SettingsKeys.magnetWifiOnly);
    seedingStopMode = GStorage.getSetting(SettingsKeys.magnetSeedingStopMode);
    seedingStopHours = GStorage.getSetting(SettingsKeys.magnetSeedingStopHours);
    seedingStopRatio = GStorage.getSetting(SettingsKeys.magnetSeedingStopRatio);
    enableDht = GStorage.getSetting(SettingsKeys.magnetEnableDht);
    enableUpnp = GStorage.getSetting(SettingsKeys.magnetEnableUpnp);
    forceEncrypt = GStorage.getSetting(SettingsKeys.magnetForceEncrypt);
    enableIpv6 = GStorage.getSetting(SettingsKeys.magnetEnableIpv6);
    trackerAutoUpdate = GStorage.getSetting(SettingsKeys.magnetTrackerAutoUpdate);
    trackerUpdateHours = GStorage.getSetting(SettingsKeys.magnetTrackerUpdateHours);
    trackerSources = GStorage.getSetting(SettingsKeys.magnetTrackerSources);
    autoImportToLibrary =
        GStorage.getSetting(SettingsKeys.magnetAutoImportToLibrary);
    autoImportRoot = GStorage.getSetting(SettingsKeys.magnetAutoImportRoot);
    autoScrapeOnComplete =
        GStorage.getSetting(SettingsKeys.magnetAutoScrapeOnComplete);
    autoImportConfidence =
        GStorage.getSetting(SettingsKeys.magnetAutoImportConfidence);
    syncBangumiProgress =
        GStorage.getSetting(SettingsKeys.localMediaSyncBangumiProgress);
    thumbnailsEnabled =
        GStorage.getSetting(SettingsKeys.localMediaThumbnails);
    watchFolderEnabled =
        GStorage.getSetting(SettingsKeys.localMediaWatchFolder);
    diskSpaceCheck = GStorage.getSetting(SettingsKeys.magnetDiskSpaceCheck);
    groupDownloads = GStorage.getSetting(SettingsKeys.magnetGroupDownloads);
    subscriptionCheckIntervalMinutes = GStorage.getSetting(
        SettingsKeys.magnetSubscriptionCheckIntervalMinutes);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('磁力下载'),
      body: SettingsList(
        sections: [
          _searchSourceSections(),
          _engineSection(),
          if (engineEnabled) ...[
            _connectionSection(),
            _trackerSection(),
            _downloadManageSection(),
            _libraryLinkSection(),
          ],
          _subscriptionSection(),
          _infoSection(),
        ],
      ),
    );
  }

  // ---------------- 搜索源 ----------------
  Widget _searchSourceSections() {
    return SettingsSection(
      title: const Text('搜索源'),
      tiles: [
        SettingsTile(
          leading: Icons.language_rounded,
          title: const Text('Mikan 站点地址'),
          description: Text(
            mikanBaseUrl.isEmpty ? '未设置，使用默认地址' : mikanBaseUrl,
          ),
          onPressed: (_) => _editMikanBaseUrl(),
        ),
        SettingsTile(
          leading: Icons.dns_rounded,
          title: const Text('默认搜索源'),
          description: Text(MagnetSearchSources.byId(defaultSourceId).baseUrl),
          value: DropdownButton<String>(
            value: defaultSourceId,
            underline: const SizedBox.shrink(),
            isDense: true,
            items: [
              for (final source in MagnetSearchSources.all)
                DropdownMenuItem(
                  value: source.id,
                  child: Text(source.name),
                ),
            ],
            onChanged: (value) async {
              if (value == null || value == defaultSourceId) return;
              setState(() => defaultSourceId = value);
              await GStorage.putSetting(
                  SettingsKeys.magnetDefaultSource, value);
              await _controller.setSearchSource(value);
            },
          ),
        ),
      ],
    );
  }

  // ---------------- 下载引擎 ----------------
  Widget _engineSection() {
    return SettingsSection(
      title: const Text('下载引擎'),
      tiles: [
        SettingsTile.switchTile(
          leading: Icons.bolt_rounded,
          title: const Text('启用磁力下载引擎'),
          description: const Text('基于 libtorrent 的进程内引擎，随 Kazumi 启动/停止'),
          initialValue: engineEnabled,
          onToggle: (value) async {
            final v = value ?? !engineEnabled;
            setState(() => engineEnabled = v);
            await GStorage.putSetting(SettingsKeys.magnetEngineEnabled, v);
            await _controller.applyMagnetSettingsChanged();
          },
        ),
        if (engineEnabled)
          Observer(builder: (_) {
            final running = _controller.engineRunning;
            final state = _controller.engineState;
            return SettingsTile(
              leading: Icons.wifi_tethering_rounded,
              title: const Text('引擎状态'),
              description: Text(_engineStateText(running, state)),
              trailing: running
                  ? FilledButton.tonal(
                      onPressed: () => _controller.stopBuiltinEngine(),
                      child: const Text('停止'),
                    )
                  : FilledButton.tonal(
                      onPressed: () => _controller.startBuiltinEngine(),
                      child: const Text('启动'),
                    ),
            );
          }),
      ],
    );
  }

  String _engineStateText(bool running, LibtorrentEngineState state) {
    if (running) return '引擎运行中 · libtorrent 2.x';
    return switch (state) {
      LibtorrentEngineState.starting => '正在启动…',
      LibtorrentEngineState.stopping => '正在停止…',
      LibtorrentEngineState.error => _controller.engineError ?? '引擎出错',
      _ => '未运行（点击“启动”或进入磁力搜索页自动启动）',
    };
  }

  // ---------------- 连接与下载 ----------------
  Widget _connectionSection() {
    return SettingsSection(
      title: const Text('连接与限速'),
      tiles: [
        SettingsTile(
          leading: Icons.storage_rounded,
          title: const Text('下载目录'),
          description: Text(downloadDir.isEmpty
              ? '未设置，使用系统下载目录'
              : downloadDir),
          onPressed: (_) => _pickDownloadDir(),
          trailing: isPickingDir
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        SettingsTile(
          leading: Icons.hub_outlined,
          title: const Text('监听端口'),
          description: Text(listenPort <= 0
              ? '自动选择（推荐）'
              : 'TCP+UDP $listenPort'),
          onPressed: (_) => _promptNumber(
            '监听端口',
            listenPort <= 0 ? 0 : listenPort,
            (v) async {
              setState(() => listenPort = v);
              await GStorage.putSetting(SettingsKeys.magnetListenPort, v);
              await _controller.applyMagnetSettingsChanged();
            },
          ),
        ),
        SettingsTile(
          leading: Icons.groups_rounded,
          title: const Text('最大对等连接数'),
          description: Text('$maxPeers'),
          value: DropdownButton<int>(
            value: maxPeers,
            underline: const SizedBox.shrink(),
            isDense: true,
            items: const [
              DropdownMenuItem(value: 25, child: Text('25')),
              DropdownMenuItem(value: 50, child: Text('50')),
              DropdownMenuItem(value: 100, child: Text('100')),
              DropdownMenuItem(value: 200, child: Text('200')),
              DropdownMenuItem(value: 400, child: Text('400')),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setState(() => maxPeers = value);
              await GStorage.putSetting(SettingsKeys.magnetMaxPeers, value);
              await _controller.applyMagnetSettingsChanged();
            },
          ),
        ),
        SettingsTile(
          leading: Icons.format_list_numbered_rounded,
          title: const Text('同时下载任务数'),
          description: const Text('超出的任务自动排队，有任务完成时按添加顺序开始'),
          value: DropdownButton<int>(
            value: maxActiveDownloads,
            underline: const SizedBox.shrink(),
            isDense: true,
            items: const [
              DropdownMenuItem(value: 1, child: Text('1')),
              DropdownMenuItem(value: 2, child: Text('2')),
              DropdownMenuItem(value: 3, child: Text('3')),
              DropdownMenuItem(value: 5, child: Text('5')),
              DropdownMenuItem(value: 0, child: Text('不限')),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setState(() => maxActiveDownloads = value);
              await GStorage.putSetting(
                  SettingsKeys.magnetMaxActiveDownloads, value);
              await _controller.applyMagnetSettingsChanged();
            },
          ),
        ),
        SettingsSliderTile(
          title: const Text('全局上传限速'),
          description: const Text('0 表示不限制上传速度'),
          value: maxUploadLimitKb.toDouble(),
          valueLabel: maxUploadLimitKb == 0
              ? '不限'
              : '$maxUploadLimitKb KiB/s',
          min: 0,
          max: 8192,
          divisions: 64,
          onChanged: (v) async {
            final rounded = v.round();
            setState(() => maxUploadLimitKb = rounded);
            await GStorage.putSetting(
                SettingsKeys.magnetMaxUploadLimitKb, rounded);
            await _controller.applyMagnetSettingsChanged();
          },
        ),
        SettingsSliderTile(
          title: const Text('全局下载限速'),
          description: const Text('0 表示不限制下载速度'),
          value: maxDownloadLimitKb.toDouble(),
          valueLabel: maxDownloadLimitKb == 0
              ? '不限'
              : '$maxDownloadLimitKb KiB/s',
          min: 0,
          max: 8192,
          divisions: 64,
          onChanged: (v) async {
            final rounded = v.round();
            setState(() => maxDownloadLimitKb = rounded);
            await GStorage.putSetting(
                SettingsKeys.magnetMaxDownloadLimitKb, rounded);
            await _controller.applyMagnetSettingsChanged();
          },
        ),
        SettingsTile.switchTile(
          leading: Icons.schedule_rounded,
          title: const Text('限速时段'),
          description: const Text('在指定时间段内自动套用较低的下载限速（如白天限速、夜间全速）'),
          initialValue: scheduledLimitEnabled,
          onToggle: (value) async {
            final v = value ?? scheduledLimitEnabled;
            setState(() => scheduledLimitEnabled = v);
            await GStorage.putSetting(
                SettingsKeys.magnetScheduledLimitEnabled, v);
            await _controller.applyMagnetSettingsChanged();
          },
        ),
        if (scheduledLimitEnabled) ...[
          SettingsTile(
            leading: Icons.timer_outlined,
            title: const Text('限速时段'),
            description: Text('$scheduledLimitStart ～ $scheduledLimitEnd'
                '（支持跨天，如 23:00 ～ 08:00）'),
            onPressed: (_) => _pickLimitWindow(),
          ),
          SettingsSliderTile(
            title: const Text('时段限速'),
            description: const Text('时段内下载速度上限，0 表示不限'),
            value: scheduledLimitKb.toDouble(),
            valueLabel: scheduledLimitKb == 0
                ? '不限'
                : '$scheduledLimitKb KiB/s',
            min: 0,
            max: 8192,
            divisions: 64,
            onChanged: (v) async {
              final rounded = v.round();
              setState(() => scheduledLimitKb = rounded);
              await GStorage.putSetting(
                  SettingsKeys.magnetScheduledLimitKb, rounded);
              await _controller.applyMagnetSettingsChanged();
            },
          ),
        ],
        SettingsTile.switchTile(
          leading: Icons.wifi_rounded,
          title: const Text('仅 WiFi 下载'),
          description: const Text('非 WiFi 网络下自动暂停磁力下载，恢复 WiFi 后自动继续'),
          initialValue: wifiOnly,
          onToggle: (value) async {
            final v = value ?? wifiOnly;
            setState(() => wifiOnly = v);
            await GStorage.putSetting(SettingsKeys.magnetWifiOnly, v);
            await _controller.applyMagnetSettingsChanged();
          },
        ),
        SettingsTile(
          leading: Icons.hourglass_bottom_rounded,
          title: const Text('做种停止条件'),
          description: Text(_seedingStopDescription()),
          value: DropdownButton<String>(
            value: seedingStopMode,
            underline: const SizedBox.shrink(),
            isDense: true,
            items: const [
              DropdownMenuItem(
                  value: 'ratio', child: Text('分享率达到阈值')),
              DropdownMenuItem(value: 'time', child: Text('做种指定时长')),
              DropdownMenuItem(value: 'none', child: Text('不自动停止')),
            ],
            onChanged: (value) async {
              if (value == null || value == seedingStopMode) return;
              setState(() => seedingStopMode = value);
              await GStorage.putSetting(
                  SettingsKeys.magnetSeedingStopMode, value);
              await _controller.applyMagnetSettingsChanged();
            },
          ),
        ),
        if (seedingStopMode == 'time')
          SettingsTile(
            leading: Icons.timer_rounded,
            title: const Text('做种时长'),
            value: DropdownButton<int>(
              value: seedingStopHours,
              underline: const SizedBox.shrink(),
              isDense: true,
              items: const [
                DropdownMenuItem(value: 6, child: Text('6 小时')),
                DropdownMenuItem(value: 12, child: Text('12 小时')),
                DropdownMenuItem(value: 24, child: Text('1 天')),
                DropdownMenuItem(value: 48, child: Text('2 天')),
                DropdownMenuItem(value: 168, child: Text('1 周')),
                DropdownMenuItem(value: 720, child: Text('1 个月')),
              ],
              onChanged: (value) async {
                if (value == null) return;
                setState(() => seedingStopHours = value);
                await GStorage.putSetting(
                    SettingsKeys.magnetSeedingStopHours, value);
                await _controller.applyMagnetSettingsChanged();
              },
            ),
          ),
        if (seedingStopMode == 'ratio')
          SettingsSliderTile(
            title: const Text('分享率阈值'),
            description: const Text('做种率达到该值后停止上传并标记完成'),
            value: seedingStopRatio,
            valueLabel: seedingStopRatio.toStringAsFixed(1),
            min: 0.1,
            max: 10.0,
            divisions: 99,
            onChanged: (v) async {
              final rounded = (v * 10).round() / 10.0;
              setState(() => seedingStopRatio = rounded);
              await GStorage.putSetting(
                  SettingsKeys.magnetSeedingStopRatio, rounded);
              await _controller.applyMagnetSettingsChanged();
            },
          ),
        SettingsTile.switchTile(
          leading: Icons.radar_rounded,
          title: const Text('启用 DHT'),
          description: const Text('无 tracker 时也能发现对等节点'),
          initialValue: enableDht,
          onToggle: (value) async {
            final v = value ?? enableDht;
            setState(() => enableDht = v);
            await GStorage.putSetting(SettingsKeys.magnetEnableDht, v);
            await _controller.applyMagnetSettingsChanged();
          },
        ),
        SettingsTile.switchTile(
          leading: Icons.network_ping_rounded,
          title: const Text('UPnP / NAT-PMP'),
          description: const Text('自动映射端口，提升内网连通性'),
          initialValue: enableUpnp,
          onToggle: (value) async {
            final v = value ?? enableUpnp;
            setState(() => enableUpnp = v);
            await GStorage.putSetting(SettingsKeys.magnetEnableUpnp, v);
            await _controller.applyMagnetSettingsChanged();
          },
        ),
        SettingsTile.switchTile(
          leading: Icons.enhanced_encryption_rounded,
          title: const Text('强制加密连接'),
          description: const Text('仅接受加密对等连接'),
          initialValue: forceEncrypt,
          onToggle: (value) async {
            final v = value ?? forceEncrypt;
            setState(() => forceEncrypt = v);
            await GStorage.putSetting(SettingsKeys.magnetForceEncrypt, v);
            await _controller.applyMagnetSettingsChanged();
          },
        ),
        SettingsTile.switchTile(
          leading: Icons.language_rounded,
          title: const Text('IPv6 监听'),
          description: const Text('开启 IPv6 地址的监听'),
          initialValue: enableIpv6,
          onToggle: (value) async {
            final v = value ?? enableIpv6;
            setState(() => enableIpv6 = v);
            await GStorage.putSetting(SettingsKeys.magnetEnableIpv6, v);
            await _controller.applyMagnetSettingsChanged();
          },
        ),
      ],
    );
  }

  // ---------------- 下载管理 ----------------
  Widget _downloadManageSection() {
    return SettingsSection(
      title: const Text('下载管理'),
      tiles: [
        SettingsTile.switchTile(
          leading: Icons.group_work_outlined,
          title: const Text('按番剧分组展示任务'),
          description: const Text('下载页把同一部番的多个任务聚合为一组，方便查看缺集'),
          initialValue: groupDownloads,
          onToggle: (value) async {
            final v = value ?? groupDownloads;
            setState(() => groupDownloads = v);
            await GStorage.putSetting(SettingsKeys.magnetGroupDownloads, v);
          },
        ),
        SettingsTile.switchTile(
          leading: Icons.storage_outlined,
          title: const Text('提交下载前检查磁盘空间'),
          description: const Text('目标分区剩余空间不足时弹出确认，避免下载到一半失败'),
          initialValue: diskSpaceCheck,
          onToggle: (value) async {
            final v = value ?? diskSpaceCheck;
            setState(() => diskSpaceCheck = v);
            await GStorage.putSetting(SettingsKeys.magnetDiskSpaceCheck, v);
          },
        ),
      ],
    );
  }

  // ---------------- 媒体库联动 ----------------
  Widget _libraryLinkSection() {
    return SettingsSection(
      title: const Text('媒体库联动'),
      tiles: [
        SettingsTile.switchTile(
          leading: Icons.video_library_rounded,
          title: const Text('下载完成后自动入库'),
          description: const Text('把「已搜刮」任务的下载文件移动到媒体库文件夹并按集数命名'),
          initialValue: autoImportToLibrary,
          onToggle: (value) async {
            final v = value ?? autoImportToLibrary;
            setState(() => autoImportToLibrary = v);
            await GStorage.putSetting(
                SettingsKeys.magnetAutoImportToLibrary, v);
          },
        ),
        if (autoImportToLibrary)
          SettingsTile(
            leading: Icons.folder_rounded,
            title: const Text('入库目标根目录'),
            description: Text(
              autoImportRoot.isEmpty
                  ? '未设置，使用媒体库的第一个文件夹'
                  : autoImportRoot,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: (_) => _pickAutoImportRoot(),
          ),
        SettingsTile.switchTile(
          leading: Icons.auto_awesome_rounded,
          title: const Text('完成后自动搜刮番剧信息'),
          description: const Text('未携带番剧信息的任务（订阅自动下载 / 手动添加）完成后按标题自动匹配，'
              '未命中时标记「待确认」可在下载页手动匹配'),
          initialValue: autoScrapeOnComplete,
          onToggle: (value) async {
            final v = value ?? autoScrapeOnComplete;
            setState(() => autoScrapeOnComplete = v);
            await GStorage.putSetting(
                SettingsKeys.magnetAutoScrapeOnComplete, v);
          },
        ),
        if (autoScrapeOnComplete)
          SettingsSliderTile(
            title: const Text('自动入库置信度阈值'),
            description: const Text('自动搜刮匹配置信度达到该值才自动入库；'
                '低于阈值只同步搜刮结果、不移动文件'),
            value: autoImportConfidence,
            valueLabel: autoImportConfidence.toStringAsFixed(1),
            min: 0.5,
            max: 1.0,
            divisions: 10,
            onChanged: (v) async {
              final rounded = (v * 10).round() / 10.0;
              setState(() => autoImportConfidence = rounded);
              await GStorage.putSetting(
                  SettingsKeys.magnetAutoImportConfidence, rounded);
            },
          ),
        SettingsTile.switchTile(
          leading: Icons.cloud_sync_rounded,
          title: const Text('本地看完联动 Bangumi 进度'),
          description: const Text('媒体库播完一集后，把 Bangumi 收藏的 EP 进度更新为该集数'),
          initialValue: syncBangumiProgress,
          onToggle: (value) async {
            final v = value ?? syncBangumiProgress;
            setState(() => syncBangumiProgress = v);
            await GStorage.putSetting(
                SettingsKeys.localMediaSyncBangumiProgress, v);
          },
        ),
        SettingsTile.switchTile(
          leading: Icons.image_outlined,
          title: const Text('未匹配卡片视频缩略图'),
          description: const Text('用 ffmpeg 为未匹配番剧的文件夹生成视频首帧缩略图，替代默认占位图标'),
          initialValue: thumbnailsEnabled,
          onToggle: (value) async {
            final v = value ?? thumbnailsEnabled;
            setState(() => thumbnailsEnabled = v);
            await GStorage.putSetting(SettingsKeys.localMediaThumbnails, v);
            await _mediaController.setThumbnailsEnabled(v);
          },
        ),
        SettingsTile.switchTile(
          leading: Icons.watch_outlined,
          title: const Text('监听媒体库目录变化'),
          description: const Text('Windows 下实时感知文件新增 / 删除并自动重扫（Android 使用定时轮询）'),
          initialValue: watchFolderEnabled,
          onToggle: (value) async {
            final v = value ?? watchFolderEnabled;
            setState(() => watchFolderEnabled = v);
            await GStorage.putSetting(SettingsKeys.localMediaWatchFolder, v);
            await _mediaController.setWatchFolder(v);
          },
        ),
      ],
    );
  }

  Future<void> _pickAutoImportRoot() async {
    if (isPickingDir) return;
    isPickingDir = true;
    final picked = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择入库根目录');
    isPickingDir = false;
    if (picked == null) return;
    setState(() => autoImportRoot = picked);
    await GStorage.putSetting(SettingsKeys.magnetAutoImportRoot, picked);
  }

  String _seedingStopDescription() {
    return switch (seedingStopMode) {
      'time' => '做种满 $seedingStopHours 小时后停止上传并标记完成',
      'none' => '下载完成后持续做种，不自动停止',
      _ => '做种率达到 ${seedingStopRatio.toStringAsFixed(1)} 后停止上传并标记完成',
    };
  }

  // ---------------- Tracker ----------------
  Widget _trackerSection() {
    return SettingsSection(
      title: const Text('Tracker 自动更新'),
      tiles: [
        SettingsTile.switchTile(
          leading: Icons.sync_rounded,
          title: const Text('自动更新 tracker'),
          description: const Text('定期从公开列表抓取可用 tracker 节点'),
          initialValue: trackerAutoUpdate,
          onToggle: (value) async {
            final v = value ?? trackerAutoUpdate;
            setState(() => trackerAutoUpdate = v);
            await GStorage.putSetting(SettingsKeys.magnetTrackerAutoUpdate, v);
            await _controller.applyMagnetSettingsChanged();
          },
        ),
        SettingsTile(
          leading: Icons.schedule_rounded,
          title: const Text('更新间隔'),
          value: DropdownButton<int>(
            value: trackerUpdateHours,
            underline: const SizedBox.shrink(),
            isDense: true,
            items: const [
              DropdownMenuItem(value: 6, child: Text('6 小时')),
              DropdownMenuItem(value: 12, child: Text('12 小时')),
              DropdownMenuItem(value: 24, child: Text('1 天')),
              DropdownMenuItem(value: 72, child: Text('3 天')),
              DropdownMenuItem(value: 168, child: Text('1 周')),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setState(() => trackerUpdateHours = value);
              await GStorage.putSetting(
                  SettingsKeys.magnetTrackerUpdateHours, value);
              await _controller.applyMagnetSettingsChanged();
            },
          ),
        ),
        SettingsTile(
          leading: Icons.link_rounded,
          title: const Text('更新源'),
          description: const Text('每行一个 tracker 列表 URL'),
          onPressed: (_) => _editTrackerSources(),
        ),
        Observer(builder: (_) {
          final last = _controller.trackerUpdatedAt;
          return SettingsTile(
            leading: Icons.verified_rounded,
            title: const Text('当前 tracker 节点'),
            description: Text(
              '已缓存 ${_controller.trackerCount} 个'
              '${last == null ? '' : ' · 更新于 ${_formatTime(last)}'}',
            ),
            trailing: _controller.trackerUpdating
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton.tonal(
                    onPressed: () => _controller.updateTrackers(),
                    child: const Text('立即更新'),
                  ),
          );
        }),
      ],
    );
  }

  String _formatTime(DateTime t) {
    return '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  // ---------------- RSS 订阅 ----------------
  Widget _subscriptionSection() {
    final minutes = subscriptionCheckIntervalMinutes;
    return SettingsSection(
      title: const Text('RSS 订阅'),
      tiles: [
        SettingsTile(
          leading: Icons.autorenew_rounded,
          title: const Text('自动检查更新间隔'),
          description: Text(minutes % 60 == 0
              ? '每 ${minutes ~/ 60} 小时检查一次订阅更新，发现新内容时自动下载'
              : '每 $minutes 分钟检查一次订阅更新，发现新内容时自动下载'),
          value: DropdownButton<int>(
            value: minutes,
            underline: const SizedBox.shrink(),
            isDense: true,
            items: const [
              DropdownMenuItem(value: 30, child: Text('30 分钟')),
              DropdownMenuItem(value: 60, child: Text('1 小时')),
              DropdownMenuItem(value: 120, child: Text('2 小时')),
              DropdownMenuItem(value: 360, child: Text('6 小时')),
              DropdownMenuItem(value: 720, child: Text('12 小时')),
              DropdownMenuItem(value: 1440, child: Text('1 天')),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setState(() => subscriptionCheckIntervalMinutes = value);
              await GStorage.putSetting(
                  SettingsKeys.magnetSubscriptionCheckIntervalMinutes, value);
              await _controller.applyMagnetSettingsChanged();
            },
          ),
        ),
      ],
    );
  }

  // ---------------- 说明 ----------------
  Widget _infoSection() {
    return SettingsSection(
      title: const Text('说明'),
      tiles: [
        SettingsTile(
          leading: Icons.info_outline_rounded,
          title: const Text('使用提示'),
          description: const Text(
            '• 内置引擎基于 libtorrent 2.x，随应用自动启动/停止\n'
            '• DHT / UPnP 可提升无 tracker 资源的下发成功率\n'
            '• libtorrent 自带公共 tracker 抓取，此处缓存用于参考\n'
            '• 删除任务不会删除已下载的文件',
          ),
        ),
      ],
    );
  }

  // ---------------- 交互 ----------------
  Future<void> _editMikanBaseUrl() async {
    final controller = TextEditingController(text: mikanBaseUrl);
    final result = await KazumiDialog.show<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mikan 站点地址'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://mikanani.me',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: ''),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                KazumiDialog.dismiss(popWith: controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    setState(() => mikanBaseUrl = result);
    await GStorage.putSetting(SettingsKeys.mikanBaseUrl, result);
  }

  Future<void> _editTrackerSources() async {
    final finalController = TextEditingController(text: trackerSources);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tracker 更新源'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: finalController,
            maxLines: 6,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '每行一个 tracker 地址\n'
                  'https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all.txt',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, finalController.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() => trackerSources = result);
    await GStorage.putSetting(SettingsKeys.magnetTrackerSources, result);
    await _controller.applyMagnetSettingsChanged();
  }

  /// 选择限速时段的起止时间。
  Future<void> _pickLimitWindow() async {
    TimeOfDay parse(String value) {
      final parts = value.split(':');
      final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
      final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
      return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
    }

    final start = parse(scheduledLimitStart);
    final end = parse(scheduledLimitEnd);
    final pickedStart = await showTimePicker(
      context: context,
      initialTime: start,
      helpText: '限速时段开始',
    );
    if (pickedStart == null || !mounted) return;
    final pickedEnd = await showTimePicker(
      context: context,
      initialTime: end,
      helpText: '限速时段结束',
    );
    if (pickedEnd == null || !mounted) return;
    String fmt(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() {
      scheduledLimitStart = fmt(pickedStart);
      scheduledLimitEnd = fmt(pickedEnd);
    });
    await GStorage.putSetting(
        SettingsKeys.magnetScheduledLimitStart, scheduledLimitStart);
    await GStorage.putSetting(
        SettingsKeys.magnetScheduledLimitEnd, scheduledLimitEnd);
    await _controller.applyMagnetSettingsChanged();
  }

  Future<void> _pickDownloadDir() async {    if (mounted) setState(() => isPickingDir = true);
    try {
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择默认下载目录',
      );
      if (dir == null) return;
      setState(() => downloadDir = dir);
      await GStorage.putSetting(SettingsKeys.magnetDownloadDir, dir);
      await _controller.applyMagnetSettingsChanged();
    } finally {
      if (mounted) setState(() => isPickingDir = false);
    }
  }

  Future<void> _promptNumber(String title, int initial, Function(int) onSave) async {
    final controller = TextEditingController(text: '$initial');
    final result = await KazumiDialog.show<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '端口号'),
        ),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed == null) return;
              KazumiDialog.dismiss(popWith: parsed);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) await onSave(result);
  }
}