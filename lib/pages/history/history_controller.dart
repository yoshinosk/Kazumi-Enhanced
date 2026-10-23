import 'dart:async';

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:mobx/mobx.dart';

part 'history_controller.g.dart';

class HistoryController = _HistoryController with _$HistoryController;

abstract class _HistoryController with Store {
  _HistoryController(this._historyRepository);

  final IHistoryRepository _historyRepository;

  StreamSubscription<void>? _changesSubscription;
  Timer? _reloadTimer;
  String _loadedSignature = '';

  @observable
  ObservableList<History> histories = ObservableList<History>();

  /// 从存储重新读取历史列表。
  ///
  /// 除了本页面的写入，局域网同步 / WebDAV 同步等外部链路也会直接写
  /// Hive 盒子，因此这里顺带订阅盒子变更：否则「已连接但历史没变化」
  /// 的观感会一直持续到页面重建为止。
  void init() {
    _changesSubscription ??= _historyRepository.changes.listen((_) {
      // 播放时每秒都会写一次历史，合并多次变更后再重建列表。
      _reloadTimer?.cancel();
      _reloadTimer = Timer(const Duration(milliseconds: 400), _reload);
    });
    _reload();
  }

  void _reload() {
    final temp = _historyRepository.getAllHistories();
    final signature = _signatureOf(temp);
    if (signature == _loadedSignature) return;
    _loadedSignature = signature;
    histories.clear();
    histories.addAll(temp);
  }

  /// 列表内容指纹：内容未变化时不重建 ObservableList，避免无谓的重绘。
  static String _signatureOf(List<History> items) => items
      .map(
        (history) =>
            '${history.key}#${history.lastWatchTime.millisecondsSinceEpoch}'
            '#${history.lastWatchEpisode}#${history.progresses.length}',
      )
      .join('|');

  Future<void> updateHistory(
    PlaybackHistoryIdentity identity,
    Duration progress, {
    Duration duration = Duration.zero,
  }) async {
    await _historyRepository.updateHistory(
      identity: identity,
      progress: progress,
      duration: duration,
    );
    init();
  }

  Progress? lastWatching(
    BangumiItem bangumiItem,
    String adapterName, {
    String entryKind = HistoryEntryKind.online,
  }) {
    return _historyRepository.getLastWatchingProgress(
      bangumiItem,
      adapterName,
      entryKind: entryKind,
    );
  }

  Progress? findProgress(
    BangumiItem bangumiItem,
    String adapterName,
    int episode, {
    String entryKind = HistoryEntryKind.online,
  }) {
    return _historyRepository.findProgress(
      bangumiItem,
      adapterName,
      episode,
      entryKind: entryKind,
    );
  }

  Future<void> deleteHistory(History history) async {
    await _historyRepository.deleteHistory(history);
    init();
  }

  Future<void> clearAll() async {
    await _historyRepository.clearAllHistories();
    histories.clear();
    _loadedSignature = '';
  }
}
