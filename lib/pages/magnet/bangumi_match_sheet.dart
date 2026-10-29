import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/magnet/magnet_controller.dart';

/// 打开「匹配番剧」面板：搜索 Bangumi 番剧并返回用户选中的条目。
///
/// 供下载任务的「待确认」手动匹配与下载前的归属确认共用。
Future<BangumiItem?> showBangumiMatchSheet(
  BuildContext context, {
  required MagnetController controller,
  String initialKeyword = '',
}) {
  return showModalBottomSheet<BangumiItem>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BangumiMatchSheet(
      controller: controller,
      initialKeyword: initialKeyword,
    ),
  );
}

/// 「匹配番剧」底部面板：搜索 Bangumi 番剧并返回选中条目。
class BangumiMatchSheet extends StatefulWidget {
  const BangumiMatchSheet({
    super.key,
    required this.controller,
    required this.initialKeyword,
  });

  final MagnetController controller;
  final String initialKeyword;

  @override
  State<BangumiMatchSheet> createState() => _BangumiMatchSheetState();
}

class _BangumiMatchSheetState extends State<BangumiMatchSheet> {
  late final TextEditingController _keywordCtrl;
  List<BangumiItem> _results = const [];
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _keywordCtrl = TextEditingController(text: widget.initialKeyword);
    _search();
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _keywordCtrl.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    final items = await widget.controller.searchBangumi(keyword);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = items;
      if (items.isEmpty) {
        _error = '没有找到相关番剧，试试更换关键词';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('匹配番剧', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _keywordCtrl,
                      decoration: const InputDecoration(
                        hintText: '搜索番剧关键词',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _searching ? null : _search,
                    icon: const Icon(Icons.search_rounded),
                    tooltip: '搜索',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                  ? Center(
                      child: Text(
                        _error ?? '输入关键词搜索 Bangumi',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _results[index];
                        final cover =
                            item.images['large'] ?? item.images['common'];
                        return ListTile(
                          onTap: () => Navigator.pop(context, item),
                          leading: (cover != null && cover.isNotEmpty)
                              ? SizedBox(
                                  width: 36,
                                  height: 48,
                                  child: NetworkImgLayer(
                                    src: cover,
                                    width: 36,
                                    height: 48,
                                  ),
                                )
                              : null,
                          title: Text(
                            item.nameCn.isNotEmpty ? item.nameCn : item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: item.airDate.isNotEmpty
                              ? Text(item.airDate)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
