import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:xml/xml.dart' as xml;

/// Mikan Project 搜索 / RSS 订阅服务。
///
/// Mikan 同时提供搜索 RSS 和番剧订阅 RSS，结构统一，因此搜索与订阅共用同一个
/// 解析逻辑。站点地址可在设置中替换为镜像。
class MikanSearchService {
  MikanSearchService();

  Dio get _dio => DioFactory.createForConfig(
        NetworkConfig.fromSettings(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

  String get _baseUrl {
    final url = GStorage.getSetting(SettingsKeys.mikanBaseUrl).trim();
    return url.isEmpty ? 'https://mikanani.me' : url;
  }

  /// 构造搜索 RSS 地址。
  String buildSearchFeedUrl(String keyword) {
    final encoded = Uri.encodeQueryComponent(keyword.trim());
    return '$_baseUrl/RSS/Search?searchstr=$encoded';
  }

  /// 构造番剧订阅 RSS 地址。
  String buildBangumiFeedUrl(int bangumiId) {
    return '$_baseUrl/RSS/Bangumi?bangumiId=$bangumiId';
  }

  /// 搜索关键词，返回磁力结果列表。
  Future<List<MagnetSearchItem>> search(String keyword) async {
    if (keyword.trim().isEmpty) return const [];
    return fetchFeed(buildSearchFeedUrl(keyword));
  }

  /// 拉取任意 RSS 源并解析为磁力条目列表。
  Future<List<MagnetSearchItem>> fetchFeed(String feedUrl) async {
    try {
      final response = await _dio.get<String>(
        feedUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final body = response.data ?? '';
      if (body.isEmpty) return const [];
      return _parseRss(body);
    } on DioException catch (e) {
      KazumiLogger().w('MikanSearchService: fetch feed failed: $feedUrl',
          error: e);
      return const [];
    } catch (e) {
      KazumiLogger()
          .w('MikanSearchService: parse feed failed: $feedUrl', error: e);
      return const [];
    }
  }

  List<MagnetSearchItem> _parseRss(String xmlString) {
    final document = xml.XmlDocument.parse(xmlString);
    final items = document.findAllElements('item');
    final result = <MagnetSearchItem>[];
    for (final node in items) {
      final title = _innerText(node, 'title');
      final link = _innerText(node, 'link');
      final pubDate = _innerText(node, 'pubDate');
      final description = _innerText(node, 'description');
      final author = _innerText(node, 'author') +
          _innerText(node, 'dc:creator', defaultTo: '');

      // enclosure 可能是 .torrent 直链，也可能是磁力链（dmhy 等）
      String torrentUrl = '';
      String enclosureMagnet = '';
      String size = '';
      final enclosure = node.findElements('enclosure');
      if (enclosure.isNotEmpty) {
        final attr = enclosure.first;
        final url = attr.getAttribute('url') ?? '';
        if (url.startsWith('magnet:')) {
          enclosureMagnet = url;
        } else {
          torrentUrl = url;
        }
        size = _formatSize(attr.getAttribute('length'));
      }

      // 磁力链可能出现在 enclosure、link、guid 或 description 中
      String magnet = enclosureMagnet.isNotEmpty
          ? enclosureMagnet
          : (_extractMagnet(link) ??
              _extractMagnet(_innerText(node, 'guid')) ??
              _extractMagnet(description) ??
              '');

      // 当 enclosure 提供了 torrent 直链时，若仍缺少磁力链，
      // 后续可由磁力引擎直接下载该种子。
      result.add(MagnetSearchItem(
        title: title,
        magnetLink: magnet,
        torrentUrl: torrentUrl,
        size: size,
        publishDate: _parseDate(pubDate),
        publisher: author.trim().isEmpty ? null : author.trim(),
        subtitle: _extractSubtitle(description),
      ));
    }
    return result;
  }

  String _innerText(xml.XmlElement parent, String name,
      {String defaultTo = ''}) {
    try {
      final found = parent.findElements(name).firstOrNull;
      if (found != null) return found.innerText.trim();
      // 处理带命名空间前缀的元素，如 dc:creator
      final nsFound = parent.children
          .whereType<xml.XmlElement>()
          .where((e) => e.name.local == name.split(':').last)
          .firstOrNull;
      return nsFound?.innerText.trim() ?? defaultTo;
    } catch (_) {
      return defaultTo;
    }
  }

  String? _extractMagnet(String source) {
    if (source.isEmpty) return null;
    final match = RegExp(r'magnet:\?xt=urn:btih:[a-zA-Z0-9]+[^\s"<]*').firstMatch(source);
    return match?.group(0);
  }

  String _extractSubtitle(String description) {
    // Mikan description 通常为空；若包含磁力信息则丢弃，仅保留可能有的大小文本
    if (description.isEmpty) return '';
    final withoutMagnet = description
        .replaceAll(RegExp(r'magnet:\?xt=urn:btih:[^\s"<]*'), '')
        .trim();
    return withoutMagnet;
  }

  DateTime _parseDate(String raw) {
    if (raw.isEmpty) return DateTime.now();
    // RFC822 日期，例如 "Mon, 12 Aug 2024 12:00:00 +0800"
    try {
      return HttpDateParser.parse(raw) ?? DateTime.parse(raw);
    } catch (_) {
      try {
        return DateTime.parse(raw);
      } catch (_) {
        return DateTime.now();
      }
    }
  }

  String _formatSize(String? length) {
    final bytes = int.tryParse(length ?? '');
    if (bytes == null || bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[unit]}';
  }
}

/// 解析 RFC822 风格的 RSS 日期。Dart 内置没有现成实现，这里做轻量解析。
class HttpDateParser {
  HttpDateParser._();

  static DateTime? parse(String input) {
    if (input.isEmpty) return null;
    final cleaned = input.trim();
    try {
      // 移除星期前缀和时区偏移
      final withoutDay = cleaned.contains(',')
          ? cleaned.substring(cleaned.indexOf(',') + 1).trim()
          : cleaned;
      // 替换月份为数字
      final parts = withoutDay.split(RegExp(r'\s+'));
      if (parts.length < 5) return null;
      final day = int.parse(parts[0]);
      final month = _monthIndex(parts[1]);
      final year = int.parse(parts[2]);
      final timeParts = parts[3].split(':');
      if (timeParts.length < 3) return null;
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final second = int.parse(timeParts[2]);
      var tzOffset = const Duration();
      if (parts.length >= 5) {
        tzOffset = _parseTz(parts[4]);
      }
      return DateTime.utc(year, month, day, hour, minute, second)
          .subtract(tzOffset)
          .toLocal();
    } catch (_) {
      return null;
    }
  }

  static int _monthIndex(String name) {
    const map = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
    };
    final value = map[name];
    if (value == null) {
      throw FormatException('Unknown month: $name');
    }
    return value;
  }

  static Duration _parseTz(String tz) {
    if (tz == 'UT' || tz == 'GMT') return Duration.zero;
    final match = RegExp(r'^([+-])(\d{2})(\d{2})$').firstMatch(tz);
    if (match == null) return Duration.zero;
    final sign = match.group(1) == '-' ? -1 : 1;
    final hours = int.parse(match.group(2)!);
    final minutes = int.parse(match.group(3)!);
    return Duration(hours: sign * hours, minutes: sign * minutes);
  }
}
