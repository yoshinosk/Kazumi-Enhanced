import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/magnet/magnet_subscription_service.dart';

MagnetSearchItem _item(String id) => MagnetSearchItem(
      title: id,
      magnetLink: 'magnet:?xt=urn:btih:$id',
      torrentUrl: '',
      size: '',
      publishDate: DateTime(2026, 1, 1),
    );

MagnetSubscription _subscription({
  String? lastGuid,
  String feedUrl = 'https://example.test/feed.xml',
}) => MagnetSubscription(
      id: 'sub-1',
      name: 'Feed',
      feedUrl: feedUrl,
      createdAt: DateTime(2026, 1, 1),
      lastGuid: lastGuid,
    );

void main() {
  test('cursor is retained when new items are not acknowledged', () async {
    final old = _item('old');
    final latest = _item('latest');
    final saved = <List<MagnetSubscription>>[];
    final service = MagnetSubscriptionService(
      fetchFeed: (_) async => [latest, old],
      saveSubscriptions: (value) async => saved.add(value),
    );
    service.onNewItems = (_, __) async => false;

    await service.checkSubscriptionForTest(
      _subscription(lastGuid: old.magnetLink),
    );

    expect(saved.single.single.lastGuid, old.magnetLink);
  });

  test('cursor advances only after all new items are acknowledged', () async {
    final old = _item('old');
    final latest = _item('latest');
    final saved = <List<MagnetSubscription>>[];
    final service = MagnetSubscriptionService(
      fetchFeed: (_) async => [latest, old],
      saveSubscriptions: (value) async => saved.add(value),
    );
    service.onNewItems = (_, items) async {
      expect(items.map((item) => item.title), ['latest']);
      return true;
    };

    await service.checkSubscriptionForTest(
      _subscription(lastGuid: old.magnetLink),
    );

    expect(saved.single.single.lastGuid, latest.magnetLink);
  });

  test('游标未初始化时把整个 feed 当作新条目上报并推进游标', () async {
    final old = _item('old');
    final latest = _item('latest');
    var reported = false;
    final saved = <List<MagnetSubscription>>[];
    final service = MagnetSubscriptionService(
      fetchFeed: (_) async => [latest, old],
      saveSubscriptions: (value) async => saved.add(value),
    );
    service.onNewItems = (_, items) async {
      reported = true;
      expect(items.map((item) => item.title), ['latest', 'old']);
      return true;
    };

    await service.checkSubscriptionForTest(_subscription(lastGuid: null));

    expect(reported, isTrue);
    expect(saved.single.single.lastGuid, latest.magnetLink);
  });

  test('游标未初始化且自动下载失败时不推进游标，下次检查重试', () async {
    final latest = _item('latest');
    final saved = <List<MagnetSubscription>>[];
    final service = MagnetSubscriptionService(
      fetchFeed: (_) async => [latest],
      saveSubscriptions: (value) async => saved.add(value),
    );
    service.onNewItems = (_, __) async => false;

    await service.checkSubscriptionForTest(_subscription(lastGuid: null));

    expect(saved.single.single.lastGuid, isNull);
  });

  test('add 订阅立即上报当前 feed 条目（自动下载）并推进游标', () async {
    final latest = _item('latest');
    final old = _item('old');
    var reported = false;
    final saved = <List<MagnetSubscription>>[];
    final service = MagnetSubscriptionService(
      fetchFeed: (_) async => [latest, old],
      saveSubscriptions: (value) async => saved.add(value),
    );
    service.onNewItems = (_, items) async {
      reported = true;
      expect(items.map((item) => item.title), ['latest', 'old']);
      return true;
    };

    final sub = await service.add(_subscription());

    expect(reported, isTrue);
    expect(sub!.lastGuid, latest.magnetLink);
    expect(saved.single.single.lastGuid, latest.magnetLink);
  });

  test('add 订阅时自动下载失败不推进游标，等待下次检查重试', () async {
    final latest = _item('latest');
    final saved = <List<MagnetSubscription>>[];
    final service = MagnetSubscriptionService(
      fetchFeed: (_) async => [latest],
      saveSubscriptions: (value) async => saved.add(value),
    );
    service.onNewItems = (_, __) async => false;

    final sub = await service.add(_subscription());

    expect(sub!.lastGuid, isNull);
    expect(saved.single.single.lastGuid, isNull);
  });

  test('add 订阅时 feed 为空则游标保持未初始化', () async {
    var onNewItemsCalled = false;
    final saved = <List<MagnetSubscription>>[];
    final service = MagnetSubscriptionService(
      fetchFeed: (_) async => const [],
      saveSubscriptions: (value) async => saved.add(value),
    );
    service.onNewItems = (_, __) async {
      onNewItemsCalled = true;
      return true;
    };

    final sub = await service.add(_subscription());

    expect(onNewItemsCalled, isFalse);
    expect(sub!.lastGuid, isNull);
    expect(saved.single.single.lastGuid, isNull);
  });

  test('removeMany 批量删除指定订阅并合并为一次保存', () async {
    final saved = <List<MagnetSubscription>>[];
    final service = MagnetSubscriptionService(
      fetchFeed: (_) async => const [],
      saveSubscriptions: (value) async => saved.add(value),
    );
    final a = await service.add(_subscription(feedUrl: 'https://a'));
    final b = await service.add(_subscription(feedUrl: 'https://b'));
    final c = await service.add(_subscription(feedUrl: 'https://c'));

    saved.clear();
    await service.removeMany([a!.id, c!.id]);

    expect(service.subscriptions.map((s) => s.id), [b!.id]);
    expect(saved.length, 1);
  });

  test('setAutoDownloadMany 批量切换自动下载且不影响游标', () async {
    final latest = _item('latest');
    final service = MagnetSubscriptionService(
      fetchFeed: (_) async => [latest],
      saveSubscriptions: (_) async {},
    );
    service.onNewItems = (_, _) async => true;
    final a = await service.add(_subscription(feedUrl: 'https://a'));
    final b = await service.add(_subscription(feedUrl: 'https://b'));

    await service.setAutoDownloadMany([a!.id, b!.id], false);

    expect(
      service.subscriptions.every(
        (s) => !s.autoDownload && s.lastGuid == latest.magnetLink,
      ),
      isTrue,
    );
  });

  test('setDownloadPathMany 批量设置下载目录，null 表示清除', () async {
    final service = MagnetSubscriptionService(
      fetchFeed: (_) async => const [],
      saveSubscriptions: (_) async {},
    );
    final a = await service.add(_subscription(feedUrl: 'https://a'));
    final b = await service.add(_subscription(feedUrl: 'https://b'));

    await service.setDownloadPathMany([a!.id], 'D:/Anime');

    expect(
      service.subscriptions.firstWhere((s) => s.id == a.id).downloadPath,
      'D:/Anime',
    );
    expect(
      service.subscriptions.firstWhere((s) => s.id == b!.id).downloadPath,
      isNull,
    );

    await service.setDownloadPathMany([a.id], null);

    expect(
      service.subscriptions.firstWhere((s) => s.id == a.id).downloadPath,
      isNull,
    );
  });

  test('checkAll 指定 onlyIds 时只检查选中的订阅', () async {
    final feeds = <String, List<MagnetSearchItem>>{};
    final reported = <String>[];
    final service = MagnetSubscriptionService(
      fetchFeed: (sub) async => feeds[sub.feedUrl] ?? const [],
      saveSubscriptions: (_) async {},
    );
    service.onNewItems = (sub, _) async {
      reported.add(sub.feedUrl);
      return true;
    };
    final a = await service.add(_subscription(feedUrl: 'https://a'));
    await service.add(_subscription(feedUrl: 'https://b'));

    feeds['https://a'] = [_item('a1')];
    await service.checkAll(onlyIds: [a!.id]);
    expect(reported, ['https://a']);

    // 已检查的 a 游标已推进，全量检查时只剩 b 被上报。
    feeds['https://b'] = [_item('b1')];
    reported.clear();
    await service.checkAll();
    expect(reported, ['https://b']);
  });
}
