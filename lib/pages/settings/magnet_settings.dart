import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/pages/magnet/magnet_controller.dart';
import 'package:kazumi/services/magnet/aria2_engine.dart';
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
  late String animesGardenType;
  late bool aria2Enable;
  late String aria2RpcUrl;
  late String aria2Secret;
  late String engineMode;
  late String aria2ExecutablePath;
  late int aria2RpcPort;
  late String aria2DownloadDir;
  late int aria2MaxConcurrentDownloads;
  late int aria2ListenPort;
  late int aria2MaxPeers;
  late int aria2MaxUploadLimitKb;
  late bool aria2EnableDht;
  late bool aria2EnableDht6;
  late bool aria2EnableUpnp;
  late bool aria2EnableNatPmp;
  late int aria2SeedTime;
  late double aria2SeedRatio;
  late bool aria2AutoTrackerUpdate;
  late int aria2TrackerUpdateHours;
  late String aria2TrackerSources;
  late bool aria2BanLeecher;
  late bool aria2BanAbnormalIp;
  late int aria2BanScanInterval;
  late int aria2BanThreshold;
  late int aria2BanObserveSeconds;
  late int aria2BanUploadThresholdKb;
  bool isPickingDir = false;

  MagnetController get _controller => inject<MagnetController>();

  @override
  void initState() {
    super.initState();
    mikanBaseUrl = GStorage.getSetting(SettingsKeys.mikanBaseUrl);
    defaultSourceId = GStorage.getSetting(SettingsKeys.magnetDefaultSource);
    if (!MagnetSearchSources.all.any((s) => s.id == defaultSourceId)) {
      defaultSourceId = MagnetSearchSources.mikan.id;
    }
    animesGardenFansub = GStorage.getSetting(SettingsKeys.animesGardenFansub);
    animesGardenType = GStorage.getSetting(SettingsKeys.animesGardenType);
    aria2Enable = GStorage.getSetting(SettingsKeys.magnetAria2Enable);
    aria2RpcUrl = GStorage.getSetting(SettingsKeys.magnetAria2RpcUrl);
    aria2Secret = GStorage.getSetting(SettingsKeys.magnetAria2Secret);
    _loadFromSettings();
  }

  void _loadFromSettings() {
    engineMode = GStorage.getSetting(SettingsKeys.magnetEngineMode);
    aria2ExecutablePath =
        GStorage.getSetting(SettingsKeys.aria2ExecutablePath);
    aria2RpcPort = GStorage.getSetting(SettingsKeys.aria2RpcPort);
    aria2DownloadDir = GStorage.getSetting(SettingsKeys.aria2DownloadDir);
    aria2MaxConcurrentDownloads =
        GStorage.getSetting(SettingsKeys.aria2MaxConcurrentDownloads);
    aria2ListenPort = GStorage.getSetting(SettingsKeys.aria2ListenPort);
    aria2MaxPeers = GStorage.getSetting(SettingsKeys.aria2MaxPeers);
    aria2MaxUploadLimitKb =
        GStorage.getSetting(SettingsKeys.aria2MaxUploadLimitKb);
    aria2EnableDht = GStorage.getSetting(SettingsKeys.aria2EnableDht);
    aria2EnableDht6 = GStorage.getSetting(SettingsKeys.aria2EnableDht6);
    aria2EnableUpnp = GStorage.getSetting(SettingsKeys.aria2EnableUpnp);
    aria2EnableNatPmp = GStorage.getSetting(SettingsKeys.aria2EnableNatPmp);
    aria2SeedTime = GStorage.getSetting(SettingsKeys.aria2SeedTime);
    aria2SeedRatio = GStorage.getSetting(SettingsKeys.aria2SeedRatio);
    aria2AutoTrackerUpdate =
        GStorage.getSetting(SettingsKeys.aria2TrackerAutoUpdate);
    aria2TrackerUpdateHours =
        GStorage.getSetting(SettingsKeys.aria2TrackerUpdateHours);
    aria2TrackerSources = GStorage.getSetting(SettingsKeys.aria2TrackerSources);
    aria2BanLeecher = GStorage.getSetting(SettingsKeys.aria2BanLeecher);
    aria2BanAbnormalIp = GStorage.getSetting(SettingsKeys.aria2BanAbnormalIp);
    aria2BanScanInterval = GStorage.getSetting(SettingsKeys.aria2BanScanInterval);
    aria2BanThreshold = GStorage.getSetting(SettingsKeys.aria2BanThreshold);
    aria2BanObserveSeconds =
        GStorage.getSetting(SettingsKeys.aria2BanObserveSeconds);
    aria2BanUploadThresholdKb =
        GStorage.getSetting(SettingsKeys.aria2BanUploadThresholdKb);
  }

  bool get _useBuiltIn => engineMode != 'remote';

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('磁力搜索'),
      body: SettingsList(
        sections: [
          _searchSourceSections(),
          _engineSection(),
          if (_useBuiltIn) ...[
            _networkSection(),
            _seedSection(),
            _trackerSection(),
            _peerBanSection(),
          ],
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
        SettingsRadioSection<String>(
          groupValue: engineMode,
          onChanged: (value) => _setEngineMode(value!),
          tiles: [
            const SettingsTile<String>.radioTile(
              radioValue: 'builtin',
              leading: Icons.memory_rounded,
              title: Text('内置引擎'),
              description: Text('随 Kazumi 启动/停止、自动管理 RPC 与设置'),
            ),
            const SettingsTile<String>.radioTile(
              radioValue: 'remote',
              leading: Icons.dns_outlined,
              title: Text('远程 Aria2'),
              description: Text('连接自建的 Aria2 RPC 服务'),
            ),
          ],
        ),
        if (_useBuiltIn) ...[
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
      ],
    );
  }

  String _engineStateText(bool running, Aria2EngineState state) {
    if (running) {
      final url = _controller.engineRpcUrl ?? '';
      return url.isNotEmpty ? '引擎运行中 · $url' : '引擎运行中';
    }
    return switch (state) {
      Aria2EngineState.starting => '正在启动…',
      Aria2EngineState.stopping => '正在停止…',
      Aria2EngineState.error => _controller.engineError ?? '引擎出错',
      _ => '未运行（点击“启动”或进入磁力搜索页自动启动）',
    };
  }

  Future<void> _setEngineMode(String mode) async {
    if (mode == engineMode) return;
    setState(() => engineMode = mode);
    await GStorage.putSetting(SettingsKeys.magnetEngineMode, mode);
    await _controller.applyAria2SettingsChanged();
  }

  // ---------------- 网络 / 端口 ----------------
  Widget _networkSection() {
    return SettingsSection(
      title: const Text('连接与端口'),
      tiles: [
        SettingsTile(
          leading: Icons.inbox_outlined,
          title: const Text('RPC 端口'),
          description: Text(aria2RpcPort == 0
              ? '自动选择（推荐）'
              : 'http://127.0.0.1:${aria2RpcPort}/jsonrpc'),
          value: DropdownButton<int>(
            value: aria2RpcPort == 0 ? 0 : aria2RpcPort,
            underline: const SizedBox.shrink(),
            isDense: true,
            items: const [
              DropdownMenuItem(value: 0, child: Text('自动')),
              DropdownMenuItem(value: 6800, child: Text('6800')),
              DropdownMenuItem(value: 6801, child: Text('6801')),
              DropdownMenuItem(value: 6802, child: Text('6802')),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setState(() => aria2RpcPort = value);
              await GStorage.putSetting(SettingsKeys.aria2RpcPort, value);
              await _controller.applyAria2SettingsChanged();
            },
          ),
        ),
        SettingsTile(
          leading: Icons.storage_rounded,
          title: const Text('BT / DHT 监听端口'),
          description: Text(aria2ListenPort <= 0
              ? '自动（6881 起）'
              : 'TCP+UDP ${aria2ListenPort}'),
          onPressed: (_) => _promptNumber(
            'BT / DHT 监听端口',
            aria2ListenPort <= 0 ? 6881 : aria2ListenPort,
            (v) async {
              setState(() => aria2ListenPort = v);
              await GStorage.putSetting(SettingsKeys.aria2ListenPort, v);
              await _controller.applyAria2SettingsChanged();
            },
          ),
        ),
        SettingsTile(
          leading: Icons.download_for_offline_outlined,
          title: const Text('下载目录'),
          description: Text(aria2DownloadDir.isEmpty
              ? '未设置，使用系统下载目录'
              : aria2DownloadDir),
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
          leading: Icons.horizontal_split_outlined,
          title: const Text('最大并发任务数'),
          value: DropdownButton<int>(
            value: aria2MaxConcurrentDownloads,
            underline: const SizedBox.shrink(),
            isDense: true,
            items: [
              for (var i = 1; i <= 10; i++)
                DropdownMenuItem(value: i, child: Text('$i')),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setState(() => aria2MaxConcurrentDownloads = value);
              await GStorage.putSetting(
                  SettingsKeys.aria2MaxConcurrentDownloads, value);
              await _controller.applyAria2SettingsChanged();
            },
          ),
        ),
      ],
    );
  }

  // ---------------- 做种 ----------------
  Widget _seedSection() {
    return SettingsSection(
      title: const Text('做种'),
      tiles: [
        SettingsRadioSection<int>(
          groupValue: aria2SeedTime,
          onChanged: (v) async {
            if (v == null) return;
            setState(() => aria2SeedTime = v);
            await GStorage.putSetting(SettingsKeys.aria2SeedTime, v);
            await _controller.applyAria2SettingsChanged();
          },
          title: const Text('做种时间'),
          tiles: const [
            SettingsTile<int>.radioTile(
              radioValue: 0,
              title: Text('下载完成后立即停止'),
              description: Text('不做种'),
            ),
            SettingsTile<int>.radioTile(
              radioValue: 60,
              title: Text('做种 1 小时'),
            ),
            SettingsTile<int>.radioTile(
              radioValue: 720,
              title: Text('做种 12 小时'),
            ),
            SettingsTile<int>.radioTile(
              radioValue: -1,
              title: Text('不限时做种'),
              description: Text('直到手动停止或达到分享率'),
            ),
          ],
        ),
        SettingsSliderTile(
          title: const Text('分享率（达到后停止做种）'),
          description: const Text('0 表示不限分享率'),
          value: aria2SeedRatio,
          valueLabel: aria2SeedRatio == 0 ? '不限' : aria2SeedRatio.toStringAsFixed(2),
          min: 0,
          max: 5,
          divisions: 100,
          onChanged: (v) async {
            setState(() => aria2SeedRatio = v);
            await GStorage.putSetting(SettingsKeys.aria2SeedRatio, v);
            await _controller.applyAria2SettingsChanged();
          },
        ),
        SettingsSliderTile(
          title: const Text('全局上传限速'),
          description: const Text('0 表示不限制上传速度'),
          value: aria2MaxUploadLimitKb.toDouble(),
          valueLabel: aria2MaxUploadLimitKb == 0
              ? '不限'
              : '${aria2MaxUploadLimitKb} KiB/s',
          min: 0,
          max: 8192,
          divisions: 64,
          onChanged: (v) async {
            setState(() => aria2MaxUploadLimitKb = v.round());
            await GStorage.putSetting(SettingsKeys.aria2MaxUploadLimitKb, v.round());
            await _controller.applyAria2SettingsChanged();
          },
        ),
      ],
    );
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
          initialValue: aria2AutoTrackerUpdate,
          onToggle: (value) async {
            setState(() => aria2AutoTrackerUpdate = value ?? aria2AutoTrackerUpdate);
            await GStorage.putSetting(SettingsKeys.aria2TrackerAutoUpdate,
                aria2AutoTrackerUpdate);
            await _controller.applyAria2SettingsChanged();
          },
        ),
        SettingsTile(
          leading: Icons.schedule_rounded,
          title: const Text('更新间隔'),
          value: DropdownButton<int>(
            value: aria2TrackerUpdateHours,
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
              setState(() => aria2TrackerUpdateHours = value);
              await GStorage.putSetting(SettingsKeys.aria2TrackerUpdateHours, value);
              await _controller.applyAria2SettingsChanged();
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

  // ---------------- 节点安全 ----------------
  Widget _peerBanSection() {
    return SettingsSection(
      title: const Text('节点安全'),
      tiles: [
        SettingsTile.switchTile(
          leading: Icons.shield_outlined,
          title: const Text('自动封禁吸血节点'),
          description: const Text('持续大量上传而对端几乎不回传数据的节点'),
          initialValue: aria2BanLeecher,
          onToggle: (value) async {
            setState(() => aria2BanLeecher = value ?? aria2BanLeecher);
            await GStorage.putSetting(SettingsKeys.aria2BanLeecher, aria2BanLeecher);
            await _controller.applyAria2SettingsChanged();
          },
        ),
        SettingsTile.switchTile(
          leading: Icons.security_rounded,
          title: const Text('自动封禁行为异常 IP'),
          description: const Text('peerId 频繁变化、同时扩散到多个任务等'),
          initialValue: aria2BanAbnormalIp,
          onToggle: (value) async {
            setState(() => aria2BanAbnormalIp = value ?? aria2BanAbnormalIp);
            await GStorage.putSetting(
                SettingsKeys.aria2BanAbnormalIp, aria2BanAbnormalIp);
            await _controller.applyAria2SettingsChanged();
          },
        ),
        SettingsSliderTile(
          title: const Text('扫描间隔'),
          valueLabel: '$aria2BanScanInterval 秒',
          value: aria2BanScanInterval.toDouble(),
          min: 10,
          max: 300,
          divisions: 29,
          onChanged: (v) async {
            setState(() => aria2BanScanInterval = v.round());
            await GStorage.putSetting(SettingsKeys.aria2BanScanInterval, v.round());
            await _controller.applyAria2SettingsChanged();
          },
        ),
        SettingsSliderTile(
          title: const Text('吸血观察时长'),
          description: const Text('持续上传多久后才判定为吸血'),
          valueLabel: '$aria2BanObserveSeconds 秒',
          value: aria2BanObserveSeconds.toDouble(),
          min: 30,
          max: 3600,
          divisions: 118,
          onChanged: (v) async {
            setState(() => aria2BanObserveSeconds = v.round());
            await GStorage.putSetting(SettingsKeys.aria2BanObserveSeconds, v.round());
            await _controller.applyAria2SettingsChanged();
          },
        ),
        SettingsSliderTile(
          title: const Text('吸血判定上传量'),
          description: const Text('持续上传超过该量且对方回传不足 5% 才算吸血'),
          valueLabel: _banSize(aria2BanUploadThresholdKb),
          value: aria2BanUploadThresholdKb.toDouble(),
          min: 256,
          max: 20480,
          divisions: 78,
          onChanged: (v) async {
            setState(() => aria2BanUploadThresholdKb = v.round());
            await GStorage.putSetting(
                SettingsKeys.aria2BanUploadThresholdKb, v.round());
            await _controller.applyAria2SettingsChanged();
          },
        ),
        SettingsSliderTile(
          title: const Text('封禁触发阈值'),
          description: const Text('行为得分 ≥ 该值后封禁（越大越保守）'),
          valueLabel: '$aria2BanThreshold',
          value: aria2BanThreshold.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          onChanged: (v) async {
            setState(() => aria2BanThreshold = v.round());
            await GStorage.putSetting(SettingsKeys.aria2BanThreshold, v.round());
            await _controller.applyAria2SettingsChanged();
          },
        ),
        Observer(builder: (_) {
          return SettingsTile(
            leading: Icons.block_rounded,
            title: const Text('已封禁 IP'),
            description: Text('共 ${_controller.bannedPeers.length} 条 · '
                'Windows 防火墙落地'),
            onPressed: (_) => _showBannedList(),
          );
        }),
      ],
    );
  }

  String _banSize(int kb) {
    if (kb < 1024) return '$kb KiB';
    return '${(kb / 1024).toStringAsFixed(1)} MiB';
  }

  String _formatTime(DateTime t) {
    return '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
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
            '• 内置引擎需要 aria2c.exe：可放到应用目录 data/aria2/ 下，'
            '或通过“选择 aria2c”手动指定\n'
            '• DHT / UPnP 可提升无 tracker 资源的下发成功率\n'
            '• Tracker 会自动更新，也可随时“立即更新”\n'
            '• 节点安全仅作用于内置引擎下载的 BitTorrent 任务\n'
            '• 远程模式仍需本地运行 Aria2 并开启 RPC',
          ),
        ),
      ],
    );
  }

  // ---------------- 交互 ----------------
  // 以下为继承自旧版页面的辅助方法，保持搜索源编辑能力。
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
    final finalController =
        TextEditingController(text: aria2TrackerSources);
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
    setState(() => aria2TrackerSources = result);
    await GStorage.putSetting(SettingsKeys.aria2TrackerSources, result);
    await _controller.applyAria2SettingsChanged();
  }

  Future<void> _pickDownloadDir() async {
    if (mounted) setState(() => isPickingDir = true);
    try {
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择默认下载目录',
      );
      if (dir == null) return;
      setState(() => aria2DownloadDir = dir);
      await GStorage.putSetting(SettingsKeys.aria2DownloadDir, dir);
      await _controller.applyAria2SettingsChanged();
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

  Future<void> _showBannedList() async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (innerContext, setInnerState) {
            final peers = _controller.bannedPeers.toList();
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('已封禁 IP（${peers.length}）',
                              style: const TextStyle(fontSize: 16)),
                        ),
                        if (peers.isNotEmpty)
                          TextButton(
                            onPressed: () async {
                              await _controller.clearPeerBans();
                              setInnerState(() {});
                            },
                            child: const Text('全部解封'),
                          ),
                        TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 8),
                  if (peers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('当前没有封禁记录'),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final peer in peers)
                            ListTile(
                              dense: true,
                              leading: const Icon(
                                  Icons.block_rounded, size: 20),
                              title: Text(peer.ip),
                              subtitle: Text('${peer.reason}\n'
                                  '${_formatTime(peer.bannedAt)} · 得分 ${peer.score}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.undo_rounded, size: 20),
                                tooltip: '解封',
                                onPressed: () async {
                                  await _controller.unbanPeers(peer.ip);
                                  setInnerState(() {});
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}