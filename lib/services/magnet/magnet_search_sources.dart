import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/magnet/animes_garden_service.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 搜索源返回内容的解析方式。
enum MagnetSourceKind {
  /// HTML 搜索结果页，从页面中抓取磁力链。
  html,

  /// JSON API，解析接口返回的 JSON。
  json,
}

/// 一个内置的磁力搜索源。
///
/// 每个源知道如何根据关键词构造搜索地址，[kind] 决定引擎使用 HTML 抓取器
/// 还是 JSON 解析器来处理返回内容。
class MagnetSearchSource {
  const MagnetSearchSource({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.buildSearchFeedUrl,
    required this.kind,
    this.description = '',
  });

  /// 唯一标识，用于持久化用户选择。
  final String id;

  /// 显示名称。
  final String name;

  /// 站点基础地址（用于展示与搜索地址构造）。
  final String baseUrl;

  /// 根据关键词构造搜索地址。
  final String Function(String keyword, String baseUrl) buildSearchFeedUrl;

  /// 该源返回内容的解析方式。
  final MagnetSourceKind kind;

  final String description;
}

/// 内置搜索源集合。这些站点通常需要代理才能访问，默认提供多个可切换的源。
class MagnetSearchSources {
  MagnetSearchSources._();

  /// Mikan Project（mikanime.tv），HTML 搜索页，默认源。
  static const mikan = MagnetSearchSource(
    id: 'mikan',
    name: 'Mikan Project',
    baseUrl: 'https://mikanime.tv',
    description: '蜜柑计划，默认源',
    kind: MagnetSourceKind.html,
    buildSearchFeedUrl: _mikanSearchUrl,
  );

  /// Animes Garden 开放 API，JSON 接口，支持按标题 / 字幕组 / 类型搜索。
  static const animesGarden = MagnetSearchSource(
    id: 'animes_garden',
    name: 'Animes Garden',
    baseUrl: 'https://api.animes.garden',
    description: 'Animes Garden 资源聚合 API',
    kind: MagnetSourceKind.json,
    buildSearchFeedUrl: _animesGardenSearchUrl,
  );

  /// 全部内置源，按推荐顺序排列。
  static const List<MagnetSearchSource> all = [
    mikan,
    animesGarden,
  ];

  /// 根据 id 查找源，找不到时回退到 [mikan]。
  static MagnetSearchSource byId(String id) {
    for (final source in all) {
      if (source.id == id) return source;
    }
    return mikan;
  }

  static String _mikanSearchUrl(String keyword, String baseUrl) {
    final encoded = Uri.encodeQueryComponent(keyword.trim());
    return '$baseUrl/Home/Search?searchstr=$encoded';
  }

  /// Animes Garden：search 取自搜索关键词，fansub / type 取自用户设置（可空）。
  static String _animesGardenSearchUrl(String keyword, String baseUrl) {
    final encoded = Uri.encodeQueryComponent(keyword.trim());
    var url = '$baseUrl/resources?page=1&pageSize=10&search=$encoded';
    final fansub =
        GStorage.getSetting(SettingsKeys.animesGardenFansub).trim();
    final type =
        GStorage.getSetting(SettingsKeys.animesGardenType).trim();
    if (fansub.isNotEmpty) {
      url += '&fansub=${Uri.encodeQueryComponent(fansub)}';
    }
    if (type.isNotEmpty) {
      url += '&type=${Uri.encodeQueryComponent(type)}';
    }
    return url;
  }
}

/// 多源磁力搜索引擎：并发请求多个源，合并去重后返回结果。
///
/// Animes Garden 源通过 [AnimesGardenService] 走 JSON API，支持分页与筛选；
/// Mikan 源走 HTML 抓取。搜索结果可分页加载（[searchPage]）。
class MagnetSearchEngine {
  MagnetSearchEngine();

  final AnimesGardenService _animesGarden = AnimesGardenService();

  /// 单源分页搜索结果。
  ///
  /// [fansub] 显式指定字幕组（仅 AG 源生效），优先于设置默认值；
  /// 传 null 表示不限定（若设置里有默认字幕组则用设置值）。
  Future<MagnetPageResult> searchPage(
    String keyword,
    MagnetSearchSource source, {
    int page = 1,
    int pageSize = 20,
    String? fansub,
  }) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      return const MagnetPageResult(items: [], page: 1, hasMore: false);
    }
    try {
      if (source.kind == MagnetSourceKind.json) {
        // 显式传入的 fansub 优先于设置默认值
        final effectiveFansub = fansub ?? _animesGardenFansub;
        final r = await _animesGarden.search(
          keyword: trimmed,
          fansub: effectiveFansub,
          type: _animesGardenType,
          page: page,
          pageSize: pageSize,
        );
        return MagnetPageResult(
          items: r.items,
          page: page,
          hasMore: !r.isLastPage && r.items.length >= pageSize,
        );
      }
      // HTML 源无服务端分页，仅首页返回
      if (page > 1) {
        return MagnetPageResult(items: const [], page: page, hasMore: false);
      }
      final url = source.buildSearchFeedUrl(trimmed, source.baseUrl);
      final items = await _fetchHtml(url);
      return MagnetPageResult(items: items, page: 1, hasMore: false);
    } catch (e) {
      KazumiLogger().w('MagnetSearchEngine: searchPage failed', error: e);
      return MagnetPageResult(items: const [], page: page, hasMore: false);
    }
  }

  /// 对选中的源列表进行搜索（首页），合并结果并按发布时间降序排列。
  ///
  /// 每个源失败不影响其它源，只要至少一个源有结果即视为成功。
  Future<List<MagnetSearchItem>> search(
    String keyword,
    List<MagnetSearchSource> sources,
  ) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty || sources.isEmpty) return const [];

    final futures = sources.map((source) => searchPage(trimmed, source));
    final results = await Future.wait(futures);

    // 合并并去重（以磁力链 / 种子地址为键）
    final seen = <String>{};
    final merged = <MagnetSearchItem>[];
    for (final page in results) {
      for (final item in page.items) {
        final key = item.magnetLink.isNotEmpty
            ? item.magnetLink
            : item.torrentUrl;
        if (key.isEmpty) {
          merged.add(item);
          continue;
        }
        if (seen.add(key)) {
          merged.add(item);
        }
      }
    }

    merged.sort((a, b) => b.publishDate.compareTo(a.publishDate));
    return merged;
  }

  String? get _animesGardenFansub {
    final v = GStorage.getSetting(SettingsKeys.animesGardenFansub).trim();
    return v.isEmpty ? null : v;
  }

  String? get _animesGardenType {
    final v = GStorage.getSetting(SettingsKeys.animesGardenType).trim();
    return v.isEmpty ? null : v;
  }

  Dio get _dio => DioFactory.createForConfig(
        NetworkConfig.fromSettings(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

  static const _kHeaders = {
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,application/json;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
  };

  static final _magnetRegex =
      RegExp("magnet:\\?xt=urn:btih:([a-zA-Z0-9]+)[^\\s\"<>']*");
  static final _sizeRegex = RegExp(
    r'(\d+(?:\.\d+)?\s*(?:KiB|MiB|GiB|TiB|KB|MB|GB|TB))',
    caseSensitive: false,
  );
  static final _dateRegex =
      RegExp(r'(\d{4}[-/]\d{1,2}[-/]\d{1,2}(?:[ T]\d{1,2}:\d{2}(?::\d{2})?)?)');

  /// 抓取 HTML 搜索结果页并提取磁力条目。
  ///
  /// 优先按 mikanime 结构解析：标题在 `a.magnet-link-wrap`，磁力链在同行
  /// `a.js-magnet` 的 `data-clipboard-text` 属性；再用正则兜底补充。
  Future<List<MagnetSearchItem>> _fetchHtml(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: _kHeaders,
        ),
      );
      final body = response.data ?? '';
      if (body.isEmpty) return const [];
      return _parseHtml(body);
    } on DioException catch (e) {
      KazumiLogger().w('MagnetSearchEngine: fetch html failed: $url', error: e);
      return const [];
    } catch (e) {
      KazumiLogger().w('MagnetSearchEngine: parse html failed: $url', error: e);
      return const [];
    }
  }

  List<MagnetSearchItem> _parseHtml(String htmlString) {
    final document = html_parser.parse(htmlString);
    final result = <MagnetSearchItem>[];
    final seen = <String>{};

    // mikanime: <a class="magnet-link-wrap">标题</a> + 同行磁力链
    final wraps = document
        .querySelectorAll('a')
        .where((a) => a.classes.contains('magnet-link-wrap'))
        .toList();
    for (final wrap in wraps) {
      final title = wrap.text.trim();
      final magnet = _findMagnetNear(wrap);
      if (magnet.isEmpty) continue;
      final hashMatch = _magnetRegex.firstMatch(magnet);
      final hash = hashMatch?.group(1)?.toLowerCase();
      if (hash == null || !seen.add(hash)) continue;

      final rowText = _rowText(wrap);
      final size = _sizeRegex.firstMatch(rowText)?.group(1) ?? '';
      final date = _tryParseDate(rowText) ?? DateTime.now();

      result.add(MagnetSearchItem(
        title: title.isNotEmpty ? title : hash,
        magnetLink: magnet,
        torrentUrl: '',
        size: size,
        publishDate: date,
        publisher: null,
        subtitle: '',
      ));
    }

    // 兜底：解析 a[href] 中的磁力链（其它站点结构）
    for (final a in document.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      if (!href.contains('magnet:')) continue;
      final hashMatch = _magnetRegex.firstMatch(href);
      final hash = hashMatch?.group(1)?.toLowerCase();
      if (hash == null || !seen.add(hash)) continue;
      String title = a.text.trim();
      if (title.isEmpty) title = (a.attributes['title'] ?? '').trim();
      final rowText = _rowText(a);
      result.add(MagnetSearchItem(
        title: title.isNotEmpty ? title : hash,
        magnetLink: hashMatch!.group(0)!,
        torrentUrl: '',
        size: _sizeRegex.firstMatch(rowText)?.group(1) ?? '',
        publishDate: _tryParseDate(rowText) ?? DateTime.now(),
        publisher: null,
        subtitle: '',
      ));
    }

    // 兜底：正则扫描整段 HTML，补充未被 <a> 包裹的磁力链
    for (final raw in _magnetRegex.allMatches(htmlString)) {
      final hash = raw.group(1)?.toLowerCase();
      if (hash == null || !seen.add(hash)) continue;
      result.add(MagnetSearchItem(
        title: hash,
        magnetLink: raw.group(0)!,
        torrentUrl: '',
        size: '',
        publishDate: DateTime.now(),
        publisher: null,
        subtitle: '',
      ));
    }

    return result;
  }

  /// 从 [wrap] 向上查找所在行容器，返回同行磁力链字符串。
  ///
  /// mikanime 的磁力链位于 `a.js-magnet` 的 `data-clipboard-text` 属性
  /// （已由 html 解码，`&amp;` → `&`），部分站点也可能放在 `href`。
  String _findMagnetNear(dom.Element wrap) {
    var node = wrap.parent;
    while (node != null) {
      for (final a in node.querySelectorAll('a')) {
        if (identical(a, wrap)) continue;
        final clip = a.attributes['data-clipboard-text'];
        if (clip != null && clip.contains('magnet:')) return clip;
        final href = a.attributes['href'];
        if (href != null && href.contains('magnet:')) return href;
      }
      final tag = node.localName;
      if (tag == 'tr' || tag == 'li' || tag == 'article' || tag == 'dd') break;
      node = node.parent;
    }
    return '';
  }

  /// 取 [el] 所在行容器（tr/li/article/dd）的文本，用于提取大小 / 时间。
  String _rowText(dom.Element el) {
    var node = el.parent;
    while (node != null) {
      final tag = node.localName;
      if (tag == 'tr' || tag == 'li' || tag == 'article' || tag == 'dd') {
        return node.text;
      }
      node = node.parent;
    }
    return '';
  }

  DateTime? _tryParseDate(String text) {
    final match = _dateRegex.firstMatch(text);
    if (match == null) return null;
    // 形如 2026/06/04 02:44 → 2026-06-04T02:44:00
    var normalized = match.group(1)!.replaceAll('/', '-').replaceAll(' ', 'T');
    if (RegExp(r'^\d{4}-\d{1,2}-\d{1,2}T\d{1,2}:\d{2}$').hasMatch(normalized)) {
      normalized = '$normalized:00';
    }
    try {
      return DateTime.parse(normalized);
    } catch (_) {
      return null;
    }
  }
}

/// 单源单页搜索结果。
class MagnetPageResult {
  final List<MagnetSearchItem> items;
  final int page;
  final bool hasMore;
  const MagnetPageResult({
    required this.items,
    required this.page,
    required this.hasMore,
  });
}
