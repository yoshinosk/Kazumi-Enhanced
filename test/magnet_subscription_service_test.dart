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

MagnetSubscription _subscription({String? lastGuid}) => MagnetSubscription(
      id: 'sub-1',
      name: 'Feed',
      feedUrl: 'https://example.test/feed.xml',
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
}
