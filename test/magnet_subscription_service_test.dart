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
}
