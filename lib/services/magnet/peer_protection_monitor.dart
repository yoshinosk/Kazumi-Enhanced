import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/magnet/aria2_client.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 一条封禁记录。
class BannedPeer {
  final String ip;
  final String reason;
  final DateTime bannedAt;
  final int score;

  const BannedPeer({
    required this.ip,
    required this.reason,
    required this.bannedAt,
    required this.score,
  });

  factory BannedPeer.fromJson(Map<String, dynamic> json) {
    return BannedPeer(
      ip: json['ip'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      bannedAt: DateTime.tryParse(json['bannedAt'] as String? ?? '') ??
          DateTime.now(),
      score: (json['score'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'reason': reason,
        'bannedAt': bannedAt.toIso8601String(),
        'score': score,
      };
}

/// 对等节点行为监控与封禁。
///
/// 通过 `aria2.getPeers` 周期性采集每个任务的节点信息，识别两类行为：
///  - 吸血：我方持续大量上传而对端几乎不回传数据；
///  - 行为异常：同一 IP 的 peerId 频繁变化、跨任务扩散、瞬连瞬断。
/// 达到阈值后写入黑名单并交由 [PeerBanEnforcer]（Windows 防火墙）落地。
class PeerProtectionMonitor {
  PeerProtectionMonitor({Aria2Client? client})
      : _aria2 = client ?? Aria2Client();

  final Aria2Client _aria2;

  Timer? _timer;
  bool _scanning = false;
  DateTime _lastScanAt = DateTime.now();

  final Map<String, _PeerAccum> _peers = {};
  final List<BannedPeer> _banned = [];
  bool _bannedLoaded = false;

  /// 新封禁事件回调（用于 UI 提示 / 引擎联动）。
  void Function(BannedPeer peer)? onBanned;

  List<BannedPeer> get banned => List.unmodifiable(_banned);

  /// 最近一次扫描是否发现异常事件（供设置页展示）。
  int lastScanStrikes = 0;

  /// 从设置恢复黑名单。
  void _ensureBannedLoaded() {
    if (_bannedLoaded) return;
    _bannedLoaded = true;
    final raw = GStorage.getSetting(SettingsKeys.aria2BannedIps);
    if (raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      _banned
        ..clear()
        ..addAll(list.map((e) => BannedPeer.fromJson(
            Map<String, dynamic>.from(e as Map))));
    } catch (_) {
      // 忽略损坏数据。
    }
  }

  Future<void> _persistBanned() async {
    await GStorage.putSetting(
      SettingsKeys.aria2BannedIps,
      jsonEncode(_banned.map((e) => e.toJson()).toList()),
    );
  }

  /// 当前设置是否启用监控。
  bool get _enabledBySettings =>
      GStorage.getSetting(SettingsKeys.aria2BanLeecher) ||
      GStorage.getSetting(SettingsKeys.aria2BanAbnormalIp);

  /// 启动定时扫描。
  Future<void> start() async {
    _ensureBannedLoaded();
    await stop();
    if (!_enabledBySettings) return;
    final interval =
        GStorage.getSetting(SettingsKeys.aria2BanScanInterval).clamp(10, 3600);
    _timer = Timer.periodic(Duration(seconds: interval), (_) => scan());
    // 首次尽快扫描一次。
    scan();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  /// 手动触发一次扫描（如设置变更后）。
  Future<void> scan() async {
    if (_scanning || !_enabledBySettings) return;
    _scanning = true;
    lastScanStrikes = 0;
    _scanIpCount.clear();
    try {
      final active = await _aria2.tellActive();
      for (final task in active) {
        if (task.status != 'active' && task.status != 'waiting') continue;
        await _inspect(task.gid);
      }
      _scanTorrentCountCheck();
      _decay();
    } catch (e) {
      KazumiLogger().w('PeerProtectionMonitor: scan failed', error: e);
    } finally {
      _scanning = false;
    }
  }

  /// 本轮扫描中同一 IP 出现的（任务 × 节点）次数。
  final Map<String, int> _scanIpCount = {};

  Future<void> _inspect(String gid) async {
    final peers = await _aria2.getPeers(gid);
    final intervalSec = _scanIntervalSec();

    for (final peer in peers) {
      if (peer.ip.isEmpty) continue;
      final ip = _normalizeIp(peer.ip);
      if (ip.isEmpty || _banned.any((b) => b.ip == ip)) continue;

      _scanIpCount[ip] = (_scanIpCount[ip] ?? 0) + 1;

      final acc = _peers.putIfAbsent(ip, _PeerAccum.new);
      acc.givenBytes += peer.uploadSpeed * intervalSec;
      acc.gotBytes += peer.downloadSpeed * intervalSec;
      acc.sampleCount++;
      acc.lastSeen = DateTime.now();
      acc.firstSeen ??= DateTime.now();

      // 同 IP 的 peerId 变化 → 伪装/异常。
      if (peer.peerId.isNotEmpty &&
          acc.lastPeerId != null &&
          acc.lastPeerId != peer.peerId) {
        acc.churn++;
      }
      if (peer.peerId.isNotEmpty) acc.lastPeerId = peer.peerId;

      _maybeBanLeecher(ip, acc, peer.uploadSpeed);
      _maybeBanAbnormal(ip, acc);
    }
  }

  int _scanIntervalSec() {
    final interval = DateTime.now().difference(_lastScanAt).inSeconds;
    _lastScanAt = DateTime.now();
    return interval.clamp(5, 3600);
  }

  void _maybeBanLeecher(String ip, _PeerAccum acc, int currentUpload) {
    if (!GStorage.getSetting(SettingsKeys.aria2BanLeecher)) return;
    final observeSec =
        GStorage.getSetting(SettingsKeys.aria2BanObserveSeconds);
    final thresholdKb =
        GStorage.getSetting(SettingsKeys.aria2BanUploadThresholdKb);
    final sinceFirst = acc.firstSeen == null
        ? 0
        : DateTime.now().difference(acc.firstSeen!).inSeconds;
    if (sinceFirst < observeSec) return;

    final given = acc.givenBytes;
    final got = acc.gotBytes;
    // 吸血判定：我方上传超过阈值且对端回传不足 5%，且当前仍在持续上传。
    final isLeecher = currentUpload > 0 &&
        given > thresholdKb * 1024 &&
        got < given * 0.05;
    if (!isLeecher) return;

    acc.strikes++;
    acc.leechStrikes++;
    lastScanStrikes++;
    _maybeBan(
      ip,
      '吸血节点（上传 ${(given / 1024).toStringAsFixed(0)} KiB，'
      '回传 ${(got / 1024).toStringAsFixed(0)} KiB）',
      acc,
    );
  }

  void _maybeBanAbnormal(String ip, _PeerAccum acc) {
    if (!GStorage.getSetting(SettingsKeys.aria2BanAbnormalIp)) return;

    // 1. peerId 频繁变化（>=2 次）且贡献极少 → 伪装节点。
    if (acc.churn >= 2 && acc.gotBytes < 1024 * 64) {
      acc.strikes++;
      acc.abnormalStrikes++;
      lastScanStrikes++;
      _maybeBan(ip, '行为异常（peerId 频繁变化）', acc);
    }
  }

  /// 全部任务扫描完成后，处理“同一 IP 跨多个任务”的扩散型节点。
  void _scanTorrentCountCheck() {
    if (!GStorage.getSetting(SettingsKeys.aria2BanAbnormalIp)) return;
    for (final entry in _scanIpCount.entries) {
      if (entry.value < 4) continue;
      final acc = _peers[entry.key];
      if (acc == null) continue;
      acc.strikes++;
      acc.abnormalStrikes++;
      lastScanStrikes++;
      _maybeBan(entry.key, '行为异常（同时连接 ${entry.value} 个任务）', acc);
    }
  }

  void _maybeBan(String ip, String reason, _PeerAccum acc) {
    final threshold = GStorage.getSetting(SettingsKeys.aria2BanThreshold);
    if (acc.strikes < threshold) return;
    if (_banned.any((b) => b.ip == ip)) return;

    final peer = BannedPeer(
      ip: ip,
      reason: reason,
      bannedAt: DateTime.now(),
      score: acc.strikes,
    );
    _banned.add(peer);
    _persistBanned();
    // 移除观察对象，避免重复判定。
    _peers.remove(ip);
    PeerBanEnforcer.apply(ip);
    onBanned?.call(peer);
    KazumiLogger().i('PeerProtectionMonitor: banned $ip ($reason)');
  }

  /// 解码：节点已不在 swarm 中后逐渐衰减权重，防止误伤积累。
  void _decay() {
    final now = DateTime.now();
    _peers.removeWhere((ip, acc) {
      if (_banned.any((b) => b.ip == ip)) return true;
      final lastSeen = acc.lastSeen ?? now;
      return now.difference(lastSeen) > const Duration(minutes: 20);
    });
  }

  /// 解封：移除黑名单并清理防火墙规则。
  Future<void> unban(String ip) async {
    _banned.removeWhere((b) => b.ip == ip);
    await _persistBanned();
    await PeerBanEnforcer.remove(ip);
  }

  Future<void> clearAll() async {
    final ips = _banned.map((b) => b.ip).toList();
    _banned.clear();
    await _persistBanned();
    for (final ip in ips) {
      await PeerBanEnforcer.remove(ip);
    }
  }

  static String _normalizeIp(String ip) {
    var t = ip.trim();
    if (t.startsWith('[') && t.endsWith(']')) {
      t = t.substring(1, t.length - 1);
    }
    if (t.isEmpty || t == '0.0.0.0' || t == '::' || t == '::1' || t == '127.0.0.1') {
      return '';
    }
    return t;
  }
}

class _PeerAccum {
  int sampleCount = 0;
  int givenBytes = 0;
  int gotBytes = 0;
  int strikes = 0;
  int leechStrikes = 0;
  int abnormalStrikes = 0;
  int churn = 0;
  String? lastPeerId;
  DateTime? firstSeen;
  DateTime? lastSeen;
}

/// 封禁落地：通过 Windows 防火墙（netsh advfirewall）阻断与指定 IP 的
/// 双向连接。需要管理员权限；失败时仅在日志中记录，不影响应用运行。
class PeerBanEnforcer {
  PeerBanEnforcer._();

  static const String _namePrefix = 'Kazumi BT Ban';

  static Future<void> apply(String ip) async {
    if (!Platform.isWindows) return;
    if (!_validIp(ip)) return;
    final name = _ruleName(ip);
    for (final dir in ['in', 'out']) {
      await _run([
        'advfirewall',
        'firewall',
        'add',
        'rule',
        'name=$name',
        'dir=$dir',
        'action=block',
        'remoteip=$ip',
        'protocol=any',
        'enable=yes',
      ]);
    }
  }

  static Future<void> remove(String ip) async {
    if (!Platform.isWindows) return;
    final name = _ruleName(ip);
    await _run(['advfirewall', 'firewall', 'delete', 'rule', 'name=$name']);
  }

  static String _ruleName(String ip) => '$_namePrefix $ip';

  static bool _validIp(String ip) {
    final v4 = RegExp(
        r'^(\d{1,3}\.){3}\d{1,3}$');
    final v6 = RegExp(
        r'^[0-9a-fA-F:]+$');
    return v4.hasMatch(ip) || (v6.hasMatch(ip) && ip.contains(':'));
  }

  static Future<void> _run(List<String> args) async {
    try {
      final result = await Process.run(
        'netsh',
        args,
        runInShell: false,
      ).timeout(const Duration(seconds: 20));
      if (result.exitCode != 0) {
        KazumiLogger().w(
          'PeerBanEnforcer: netsh ${args.join(' ')} exited ${result.exitCode}: ${result.stderr}',
        );
      }
    } catch (e) {
      KazumiLogger().w('PeerBanEnforcer: netsh failed', error: e);
    }
  }
}