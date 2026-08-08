import 'package:dio/dio.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

/// Tracker 列表自动更新服务。
///
/// 从一组源（默认 ngosang / XIU2 / newtrackon 的公开 tracker 列表）抓取
/// announce URL，解析去重后缓存到设置中；内置引擎启动时把它们写进
/// `--bt-tracker`，运行中还可通过 `aria2.changeGlobalOption` 下发。
class TrackerUpdater {
  TrackerUpdater._();

  static final TrackerUpdater instance = TrackerUpdater._();

static const int _maxTrackers = 400;
  Dio? _dio;

  Dio get _client {
    return _dio ??= _createClient();
  }

  Dio _createClient() {
    final cfg = NetworkConfig.fromSettings(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 25),
    );
    final dio = Dio();
    dio.options.connectTimeout = cfg.connectTimeout;
    dio.options.receiveTimeout = cfg.receiveTimeout;
    dio.httpClientAdapter = cfg.createAdapter();
    return dio;
  }

  /// 当前缓存的 tracker 列表（去重后）。
  List<String> cachedTrackers() {
    final raw = GStorage.getSetting(SettingsKeys.aria2TrackersCache);
    if (raw.isEmpty) return const [];
    return raw
        .split(RegExp(r'[\r\n]+'))
        .map((s) => s.trim())
        .where(isValidTracker)
        .toSet()
        .toList();
  }

  /// 最近一次成功更新时间（epoch 毫秒），未更新过返回 null。
  DateTime? lastUpdated() {
    final millis = GStorage.getSetting(SettingsKeys.aria2TrackerLastUpdated);
    if (millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// 配置的 tracker 源 URL 列表。
  List<String> get sources => GStorage
      .getSetting(SettingsKeys.aria2TrackerSources)
      .split(RegExp(r'[\r\n,]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> saveSources(List<String> sources) async {
    await GStorage.putSetting(
      SettingsKeys.aria2TrackerSources,
      sources.join('\n'),
    );
  }

  static bool isValidTracker(String url) {
    final t = url.trim();
    if (t.isEmpty || t.startsWith('#')) return false;
    final uri = Uri.tryParse(t);
    if (uri == null || uri.host.isEmpty) return false;
    return t.startsWith('http://') ||
        t.startsWith('https://') ||
        t.startsWith('udp://') ||
        t.startsWith('wss://');
  }

  /// 抓取并合并所有源。返回更新数量；全部失败返回 -1。
  Future<int> update() async {
    final src = sources;
    if (src.isEmpty) return -1;

    final collected = <String>{};
    var failed = false;
    for (final source in src) {
      try {
        final response = await _client.get<String>(
          source,
          options: Options(
            responseType: ResponseType.plain,
            headers: {'user-agent': 'kazumi-tracker-updater/1.0'},
          ),
        );
        final lines = (response.data ?? '').split(RegExp(r'\r?\n'));
        for (final line in lines) {
          final trimmed = line.trim();
          if (isValidTracker(trimmed)) collected.add(trimmed);
          if (collected.length >= _maxTrackers) break;
        }
        if (collected.length >= _maxTrackers) break;
      } catch (e) {
        failed = true;
        KazumiLogger().w('TrackerUpdater: source failed $source', error: e);
      }
    }

    if (collected.isEmpty) {
      if (failed) {
        KazumiLogger().w('TrackerUpdater: all sources failed, keep cached.');
      }
      return -1;
    }

    final trackers = collected.take(_maxTrackers).toList();
    await GStorage.putSetting(
      SettingsKeys.aria2TrackersCache,
      trackers.join('\n'),
    );
    await GStorage.putSetting(
      SettingsKeys.aria2TrackerLastUpdated,
      DateTime.now().millisecondsSinceEpoch,
    );
    KazumiLogger().i('TrackerUpdater: updated ${trackers.length} trackers');
    return trackers.length;
  }
}