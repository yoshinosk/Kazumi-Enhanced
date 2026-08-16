import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';

/// Animes Garden 开放 API 客户端。
///
/// 文档：https://animes.garden/docs/api
/// 基址：https://api.animes.garden
///
/// GET /resources 支持的查询参数（实测）：
///   page、pageSize、search（标题关键词）、fansub（字幕组名称）、type（类型名称）
/// 其中 [filter] 回显字段：search / fansubs / types。
class AnimesGardenService {
  AnimesGardenService();

  static const String baseUrl = 'https://api.animes.garden';

  Dio get _dio => DioFactory.createForConfig(
        NetworkConfig.fromSettings(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

  static const _kHeaders = {
    'Accept': 'application/json,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
  };

  /// 字幕组信息。
  Future<List<AnimesGardenTeam>> fetchTeams() async {
    try {
      final response = await _dio.get<String>(
        '$baseUrl/teams',
        queryParameters: {'page': 1, 'pageSize': 500},
        options: Options(
          responseType: ResponseType.plain,
          headers: _kHeaders,
        ),
      );
      final body = response.data ?? '';
      if (body.isEmpty) return const [];
      final decoded = jsonDecode(body);
      if (decoded is! Map) return const [];
      final teams = decoded['teams'];
      if (teams is! List) return const [];
      final result = <AnimesGardenTeam>[];
      for (final t in teams) {
        if (t is! Map) continue;
        final name = (t['name'] ?? '').toString();
        if (name.isEmpty) continue;
        result.add(AnimesGardenTeam(
          id: t['id']?.toString() ?? '',
          name: name,
          avatar: (t['avatar'] ?? '').toString(),
        ));
      }
      // 按名称排序，便于下拉选择
      result.sort((a, b) => a.name.compareTo(b.name));
      return result;
    } catch (e) {
      KazumiLogger().w('AnimesGardenService: fetch teams failed', error: e);
      return const [];
    }
  }

  /// 搜索资源，支持分页与筛选。
  ///
  /// - [keyword]：标题关键词（search 参数）
  /// - [fansub]：字幕组名称（fansub 参数，可空）
  /// - [type]：资源类型（type 参数，可空，如 动画 / 合集）
  /// - [page]：页码，从 1 开始
  /// - [pageSize]：每页数量
  Future<AnimesGardenSearchResult> search({
    required String keyword,
    String? fansub,
    String? type,
    int page = 1,
    int pageSize = 20,
  }) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      return const AnimesGardenSearchResult(items: [], page: 1, isLastPage: true);
    }
    try {
      final qp = <String, dynamic>{
        'page': page,
        'pageSize': pageSize,
        'search': trimmed,
      };
      final f = fansub?.trim();
      if (f != null && f.isNotEmpty) qp['fansub'] = f;
      final t = type?.trim();
      if (t != null && t.isNotEmpty) qp['type'] = t;
      final response = await _dio.get<String>(
        '$baseUrl/resources',
        options: Options(
          responseType: ResponseType.plain,
          headers: _kHeaders,
        ),
        queryParameters: qp,
      );
      final body = response.data ?? '';
      if (body.isEmpty) {
        return AnimesGardenSearchResult(items: const [], page: page, isLastPage: true);
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return AnimesGardenSearchResult(items: const [], page: page, isLastPage: true);
      }
      final resources = decoded['resources'];
      final items = <MagnetSearchItem>[];
      if (resources is List) {
        final seen = <String>{};
        for (final item in resources) {
          if (item is! Map) continue;
          final parsed = _parseItem(item);
          if (parsed == null) continue;
          final hash = _hashOf(parsed.magnetLink);
          if (hash != null && !seen.add(hash)) continue;
          items.add(parsed);
        }
      }
      final pagination = decoded['pagination'];
      final complete = pagination is Map && pagination['complete'] == true;
      return AnimesGardenSearchResult(
        items: items,
        page: page,
        isLastPage: complete || items.length < pageSize,
      );
    } on DioException catch (e) {
      KazumiLogger().w('AnimesGardenService: search failed', error: e);
      return AnimesGardenSearchResult(items: const [], page: page, isLastPage: true);
    } catch (e) {
      KazumiLogger().w('AnimesGardenService: parse failed', error: e);
      return AnimesGardenSearchResult(items: const [], page: page, isLastPage: true);
    }
  }

  /// 拉取订阅的最新资源：固定取第一页（按 createdAt 降序），叠加客户端筛选。
  ///
  /// [subscription.feedUrl] 用作搜索关键词；[fansub] 由 API 过滤；
  /// [keywords]/[since]/[minSizeMb]/[maxSizeMb] 在客户端过滤。
  Future<List<MagnetSearchItem>> fetchSubscriptionFeed(
    MagnetSubscription subscription, {
    int pageSize = 30,
  }) async {
    if (subscription.kind != SubscriptionKind.animesGarden) return const [];
    final result = await search(
      keyword: subscription.feedUrl,
      fansub: subscription.fansub,
      page: 1,
      pageSize: pageSize,
    );
    final keywords = subscription.keywords;
    final kwList = keywords == null
        ? const <String>[]
        : keywords
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
    final since = subscription.since;
    final minMb = subscription.minSizeMb;
    final maxMb = subscription.maxSizeMb;
    return result.items.where((item) {
      if (kwList.isNotEmpty &&
          !kwList.every((k) => item.title.toLowerCase().contains(k.toLowerCase()))) {
        return false;
      }
      if (since != null && item.publishDate.isBefore(since)) return false;
      final mb = _sizeToMb(item.size);
      if (mb == null) {
        // 解析不出体积：体积范围限定存在时丢弃，否则保留
        if (minMb != null || maxMb != null) return false;
      } else {
        if (minMb != null && mb < minMb) return false;
        if (maxMb != null && mb > maxMb) return false;
      }
      return true;
    }).toList();
  }

  static final _magnetRegex =
      RegExp("magnet:\\?xt=urn:btih:([a-zA-Z0-9]+)[^\\s\"<>']*");

  String? _hashOf(String magnet) {
    final m = _magnetRegex.firstMatch(magnet);
    return m?.group(1)?.toLowerCase();
  }

  MagnetSearchItem? _parseItem(Map item) {
    final magnet = (item['magnet'] ?? '').toString();
    if (magnet.isEmpty) return null;
    final title = (item['title'] ?? '').toString();
    final fansub = item['fansub'];
    final publisher =
        (fansub is Map ? fansub['name'] : null)?.toString();
    final type = (item['type'] ?? '').toString();
    final createdAt = (item['createdAt'] ?? '').toString();
    final date = DateTime.tryParse(createdAt) ?? DateTime.now();
    return MagnetSearchItem(
      title: title.isNotEmpty ? title : (magnet),
      magnetLink: magnet,
      torrentUrl: '',
      size: _formatKbSize(item['size']),
      publishDate: date,
      publisher: publisher,
      subtitle: type,
    );
  }

  /// Animes Garden 的 size 字段单位为 KB。
  String _formatKbSize(dynamic kb) {
    final kilobytes = num.tryParse(kb?.toString() ?? '');
    if (kilobytes == null || kilobytes <= 0) return '';
    var size = kilobytes.toDouble() * 1024;
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[unit]}';
  }

  /// 把形如 "1.30 GB" / "342.6 MB" / "11.8GB" 的体积字符串换算为 MB。
  static double? _sizeToMb(String size) {
    if (size.isEmpty) return null;
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*(GB|MB|KB|TB|GiB|MiB|KiB|TiB)',
            caseSensitive: false)
        .firstMatch(size);
    if (m == null) return null;
    final value = double.tryParse(m.group(1)!) ?? 0;
    final unit = m.group(2)!.toUpperCase();
    switch (unit) {
      case 'TB':
      case 'TIB':
        return value * 1024 * 1024;
      case 'GB':
      case 'GIB':
        return value * 1024;
      case 'MB':
      case 'MIB':
        return value;
      case 'KB':
      case 'KIB':
        return value / 1024;
      default:
        return null;
    }
  }
}

/// 字幕组信息。
class AnimesGardenTeam {
  final String id;
  final String name;
  final String avatar;
  const AnimesGardenTeam({
    required this.id,
    required this.name,
    required this.avatar,
  });
}

/// 一次搜索的结果（含分页信息）。
class AnimesGardenSearchResult {
  final List<MagnetSearchItem> items;
  final int page;
  final bool isLastPage;
  const AnimesGardenSearchResult({
    required this.items,
    required this.page,
    required this.isLastPage,
  });
}
