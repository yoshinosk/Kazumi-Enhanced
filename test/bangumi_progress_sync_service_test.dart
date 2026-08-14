import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/media/bangumi_progress_sync_service.dart';

void main() {
  test('progress target never moves backwards', () {
    expect(BangumiProgressSyncService.monotonicTarget(12, 8), 12);
    expect(BangumiProgressSyncService.monotonicTarget(8, 12), 12);
    expect(BangumiProgressSyncService.monotonicTarget(12, 12), 12);
  });
}
