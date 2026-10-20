import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/pages/settings/sync/sync_settings_widgets.dart';
import 'package:kazumi/services/lan/lan_sync_models.dart';
import 'package:kazumi/services/lan/lan_sync_service.dart';

class LanSyncPage extends StatefulWidget {
  const LanSyncPage({super.key});

  @override
  State<LanSyncPage> createState() => _LanSyncPageState();
}

class _LanSyncPageState extends State<LanSyncPage> {
  bool _busy = false;
  String _message = '';
  bool _failed = false;

  LanSyncService get _service => inject<LanSyncService>();

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
      _message = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = '操作失败：$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPairDialog(LanDiscoveredServer server) async {
    final controller = TextEditingController();
    final code = await KazumiDialog.show<String>(
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.pin_rounded),
        title: Text('连接 ${server.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('在桌面端「局域网共享」设置中查看 6 位配对码。'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: const InputDecoration(
                hintText: '000000',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                KazumiDialog.dismiss(popWith: controller.text.trim()),
            child: const Text('连接'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || code == null || code.isEmpty) return;
    await _run(() async {
      final result = await _service.pairWithCode(server, code);
      if (mounted) {
        setState(() {
          _failed = !result.success;
          _message = result.message;
        });
      }
    });
  }

  Future<void> _connectServer(LanDiscoveredServer server) async {
    if (_service.hasTokenFor(server.serverId)) {
      await _run(() async {
        final result = await _service.connectServer(server);
        if (mounted) {
          setState(() {
            _failed = !result.success;
            _message = result.message;
          });
        }
      });
    } else {
      await _showPairDialog(server);
    }
  }

  Future<void> _showManualDialog() async {
    final addressController = TextEditingController(text: '192.168.1.2:45870');
    final codeController = TextEditingController();
    final result = await KazumiDialog.show<(String, String)>(
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lan_rounded),
        title: const Text('手动连接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('自动发现失败时可直接填写桌面端地址。'),
            const SizedBox(height: 16),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(
                labelText: '桌面端地址',
                hintText: '192.168.1.2:45870',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: '配对码（已配对可留空）',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => KazumiDialog.dismiss(
              popWith: (
                addressController.text.trim(),
                codeController.text.trim(),
              ),
            ),
            child: const Text('连接'),
          ),
        ],
      ),
    );
    addressController.dispose();
    codeController.dispose();
    if (!mounted || result == null) return;
    await _run(() async {
      final paired = await _service.connectManual(
        result.$1,
        code: result.$2.isEmpty ? null : result.$2,
      );
      if (mounted) {
        setState(() {
          _failed = !paired.success;
          _message = paired.message;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => SettingsDetailScaffold(
        title: Text(service.isServerSupported ? '局域网共享' : '局域网同步'),
        body: SyncPageBody(
          children: [
            SyncPageIntro(
              icon: Icons.router_rounded,
              title: service.isServerSupported ? '把媒体库共享到手机' : '连上桌面端接着看',
              description: service.isServerSupported
                  ? '同一 Wi-Fi 下，手机端会自动发现这台电脑。'
                        '媒体库、收藏状态与本地播放进度双向同步，视频以局域网串流播放。'
                  : '打开应用后自动发现同一 Wi-Fi 下的桌面端，'
                        '同步媒体库、收藏状态与播放进度，并直接串流播放桌面端视频。',
            ),
            if (service.isServerSupported) ..._serverSection(service),
            if (service.isClientSupported) ..._clientSection(service),
            if (!service.isServerSupported && !service.isClientSupported)
              const SyncFeedback(message: '当前平台暂不支持局域网同步。'),
            if (_message.isNotEmpty)
              SyncFeedback(message: _message, error: _failed, busy: _busy),
          ],
        ),
      ),
    );
  }

  List<Widget> _serverSection(LanSyncService service) {
    final colors = Theme.of(context).colorScheme;
    final addresses = service.serverAddresses;
    final addressText = addresses.isEmpty
        ? '尚未监听'
        : addresses
              .map((address) => '$address:${service.serverPort}')
              .join('\n');
    return [
      SettingsSection(
        title: const Text('桌面端'),
        tiles: [
          SettingsTile.switchTile(
            leading: Icons.router_rounded,
            title: const Text('开启局域网共享'),
            description: Text(
              service.serverEnabled
                  ? '手机端可在同一 Wi-Fi 下发现并同步这台电脑'
                  : '开启后允许已配对的手机访问媒体库',
            ),
            initialValue: service.serverEnabled,
            enabled: !_busy,
            onToggle: (value) => _run(
              () => service.setServerEnabled(value ?? !service.serverEnabled),
            ),
          ),
          SettingsTile(
            leading: Icons.circle,
            title: const Text('服务状态'),
            description: Text(_serverStatusText(service)),
            trailing: service.serverState == LanServerState.running
                ? Icon(Icons.check_circle_rounded, color: colors.primary)
                : Icon(Icons.info_outline_rounded, color: colors.outline),
          ),
          _collectTile(service),
          SettingsTile(
            leading: Icons.lan_rounded,
            title: const Text('访问地址'),
            description: Text(
              addressText,
              style: TextStyle(height: 1.5, color: colors.onSurfaceVariant),
            ),
            trailing: addresses.isEmpty
                ? null
                : IconButton(
                    tooltip: '复制地址',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: '${addresses.first}:${service.serverPort}',
                        ),
                      );
                      if (mounted) {
                        KazumiDialog.showToast(message: '地址已复制');
                      }
                    },
                  ),
          ),
        ],
      ),
      SettingsSection(
        title: const Text('配对'),
        tiles: [
          SettingsTile(
            leading: Icons.pin_rounded,
            title: const Text('配对码'),
            description: const Text('手机端首次连接时输入；可随时刷新'),
            value: Text(
              service.pairingCode,
              style: const TextStyle(
                fontSize: 22,
                letterSpacing: 6,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: IconButton(
              tooltip: '刷新配对码',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _busy ? null : () => _run(service.refreshPairingCode),
            ),
          ),
        ],
        bottomInfo: const Text(
          '首次开启时 Windows 可能弹出防火墙提示，请允许 Kazumi 访问专用网络。'
          '配对码与访问密钥只保存在本机，不会上传到互联网。',
        ),
      ),
    ];
  }

  Widget _collectTile(LanSyncService service) => SettingsTile.switchTile(
    leading: Icons.bookmarks_rounded,
    title: const Text('同步收藏状态'),
    description: const Text('按最后修改时间合并；同一时间按 在看 > 看过 > 想看 > 搁置 > 抛弃 决胜'),
    initialValue: service.collectEnabled,
    enabled: !_busy,
    onToggle: (value) =>
        _run(() => service.setCollectEnabled(value ?? !service.collectEnabled)),
  );

  List<Widget> _clientSection(LanSyncService service) {
    final enabled = service.clientEnabled;
    final servers = service.discoveredServers;
    final paired = service.hasClientToken;
    return [
      SettingsSection(
        title: const Text('手机端'),
        tiles: [
          SettingsTile.switchTile(
            leading: Icons.sync_rounded,
            title: const Text('启用局域网同步'),
            description: Text(
              enabled ? '打开应用时自动发现桌面端并同步' : '开启后自动连接同一 Wi-Fi 下的桌面端',
            ),
            initialValue: enabled,
            enabled: !_busy,
            onToggle: (value) =>
                _run(() => service.setClientEnabled(value ?? !enabled)),
          ),
          if (enabled) ...[
            SettingsTile(
              leading: Icons.devices_rounded,
              title: const Text('连接状态'),
              description: Text(_clientStatusText(service)),
              value: Text(
                service.isClientConnected ? '已连接' : '未连接',
                style: TextStyle(
                  color: service.isClientConnected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            SettingsTile.switchTile(
              leading: Icons.schedule_rounded,
              title: const Text('自动同步'),
              description: const Text('启动、回到前台和每 3 分钟同步一次播放进度'),
              initialValue: service.autoSync,
              enabled: !_busy,
              onToggle: (value) =>
                  _run(() => service.setAutoSync(value ?? !service.autoSync)),
            ),
            _collectTile(service),
          ],
        ],
        bottomInfo: const Text(
          '部分 Android 版本会询问「本地网络 / 附近设备」权限，请允许，'
          '否则无法发现同一 Wi-Fi 下的桌面端。',
        ),
      ),
      if (enabled) ...[
        SettingsSection(
          title: const Text('发现的桌面端'),
          tiles: [
            if (servers.isEmpty)
              SettingsTile(
                leading: Icons.search_off_rounded,
                title: const Text('暂未发现桌面端'),
                description: const Text(
                  '请确认电脑已开启局域网共享、与手机在同一 Wi-Fi，并允许 Windows 防火墙',
                ),
                trailing: TextButton(
                  onPressed: _busy ? null : () => _run(service.discoverServers),
                  child: const Text('重新发现'),
                ),
              )
            else
              for (final server in servers)
                SettingsTile(
                  leading: Icons.computer_rounded,
                  title: Text(server.name.isEmpty ? 'Kazumi 桌面端' : server.name),
                  description: Text(
                    '${server.displayAddress} · '
                    '${service.hasTokenFor(server.serverId) ? '已配对' : '需要配对码'}',
                  ),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _connectServer(server),
                    child: Text(
                      service.hasTokenFor(server.serverId) ? '连接' : '配对',
                    ),
                  ),
                ),
            SettingsTile(
              leading: Icons.edit_location_alt_rounded,
              title: const Text('手动连接'),
              description: const Text('广播被路由器隔离时，直接填写电脑 IP 与端口'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onPressed: _busy ? null : (_) => _showManualDialog(),
            ),
          ],
        ),
        StateActionButton(
          onPressed: _busy ? null : () => _run(() => service.syncNow()),
          text: _busy ? '请稍候…' : '立即同步',
          icon: Icons.sync_rounded,
        ),
        if (service.lastSyncAt != null)
          SyncFeedback(
            message:
                '上次同步：${_formatTime(service.lastSyncAt!)} · '
                '${service.lastFolderCount} 个目录 / ${service.lastFileCount} 个视频',
          ),
        if (paired || service.connectedServer != null)
          StateActionButton.tonal(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await service.forgetPairing();
                    if (mounted) setState(() => _message = '已取消配对');
                  }),
            text: '取消配对并清除桌面端媒体库',
            icon: Icons.link_off_rounded,
          ),
      ],
    ];
  }

  String _serverStatusText(LanSyncService service) {
    if (!service.serverEnabled) return '未开启';
    return switch (service.serverState) {
      LanServerState.disabled => '未开启',
      LanServerState.starting => '正在启动…',
      LanServerState.running => '运行中 · ${service.serverAddresses.length} 个网络地址',
      LanServerState.error => '启动失败：${service.serverError}',
    };
  }

  String _clientStatusText(LanSyncService service) {
    if (!service.clientEnabled) return '未开启';
    return switch (service.clientState) {
      LanClientState.disabled => '未开启',
      LanClientState.discovering => '正在发现局域网桌面端…',
      LanClientState.unpaired => '已发现桌面端，输入配对码即可连接',
      LanClientState.connecting => '正在同步…',
      LanClientState.connected =>
        '已连接 ${service.clientServerName} · ${service.clientServerAddress}',
      LanClientState.offline =>
        service.clientError.isNotEmpty
            ? service.clientError
            : '桌面端未连接，正在显示上次同步的媒体库',
      LanClientState.error =>
        service.clientError.isNotEmpty ? service.clientError : '同步异常，请检查网络后重试',
    };
  }

  String _formatTime(DateTime time) =>
      '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')} '
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}
