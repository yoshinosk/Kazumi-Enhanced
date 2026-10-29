import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/magnet/bangumi_match_sheet.dart';
import 'package:kazumi/pages/magnet/magnet_controller.dart';
import 'package:kazumi/services/magnet/libtorrent_engine.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/media/media_scraper.dart';
import 'package:kazumi/services/media/media_title_matcher.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/directory_picker.dart';
import 'package:kazumi/utils/format.dart' show formatBytes, parseSizeToBytes;

/// 会话级下载目录记忆。
///
/// 用户手动选过的目录会作为本次运行中后续任务的默认值，避免批量下载时
/// 反复选择同一目录；不持久化，重启后回到全局默认目录。
class MagnetSessionDownloadDir {
  MagnetSessionDownloadDir._();

  static String? lastPicked;

  static void reset() => lastPicked = null;
}

/// 创建磁力任务的统一入口：按设置决定是否弹窗询问下载目录，然后提交任务。
///
/// [presetDir] 为调用方预设的目录（如订阅自带下载目录），会作为弹窗初始值；
/// 关闭「添加任务时询问下载目录」时直接以该目录提交（为空则用全局默认目录）。
///
/// [scrapeInfo] / [linkedAnime] 是磁力页当前关联的番剧。提交前会按资源标题
/// 校验归属：明显不是这部番时丢弃关联，改由下载完成后的自动搜刮识别，
/// 避免换关键词搜别的番剧后仍然刮到详情页那一部上。
Future<void> confirmAndAddMagnetDownload(
  BuildContext context, {
  required MagnetController controller,
  required MagnetSearchItem item,
  String? presetDir,
  MediaScrapeInfo? scrapeInfo,
  BangumiItem? linkedAnime,
  String? queryHint,
  String dialogTitle = '添加下载任务',
  String? hint,
}) async {
  var dir = presetDir;
  var info = scrapeInfo;
  var scrapeExplicit = false;
  if (GStorage.getSetting(SettingsKeys.magnetAskDirOnAdd)) {
    final plan = await showMagnetAddDownloadDialog(
      context,
      item: item,
      controller: controller,
      presetDir: presetDir,
      dialogTitle: dialogTitle,
      hint: hint,
      scrapeInfo: scrapeInfo,
    );
    // 用户取消或页面已销毁。
    if (plan == null || !context.mounted) return;
    dir = plan.dir;
    info = plan.scrapeInfo;
    scrapeExplicit = plan.scrapeExplicit;
  }
  // 用户在弹窗里手动指定 / 清除了归属：以用户的选择为准，不再用标题
  // 覆盖；页面继承来的关联才需要按资源标题校验。
  final resolved = scrapeExplicit
      ? (info: info, confidence: info == null ? 0.0 : 1.0)
      : MediaTitleMatcher.resolveScrapeInfo(
          title: item.title,
          info: info,
          anime: linkedAnime,
          queryHint: queryHint,
        );
  await controller.addDownload(
    item,
    dir: dir,
    scrapeInfo: resolved.info,
    scrapeConfidence: resolved.confidence,
  );
}

/// 添加下载弹窗的返回值：最终下载目录与归属番剧。
class MagnetAddDownloadPlan {
  const MagnetAddDownloadPlan({
    required this.dir,
    this.scrapeInfo,
    this.scrapeExplicit = false,
  });

  final String dir;

  /// 用户最终确认的归属番剧；为空表示下载完成后按标题自动识别。
  final MediaScrapeInfo? scrapeInfo;

  /// 用户是否在弹窗里手动改过归属（改过则以用户选择为准）。
  final bool scrapeExplicit;
}

/// 弹出「添加下载任务」确认框，可在此为本次任务单独指定下载目录与归属番剧。
///
/// 返回目标目录与归属；用户取消时返回 null。
Future<MagnetAddDownloadPlan?> showMagnetAddDownloadDialog(
  BuildContext context, {
  required MagnetSearchItem item,
  required MagnetController controller,
  String? presetDir,
  MediaScrapeInfo? scrapeInfo,
  String dialogTitle = '添加下载任务',
  String? hint,
}) {
  return KazumiDialog.show<MagnetAddDownloadPlan>(
    context: context,
    builder: (dialogContext) => _MagnetAddDownloadDialog(
      item: item,
      controller: controller,
      presetDir: presetDir,
      dialogTitle: dialogTitle,
      hint: hint,
      initialScrapeInfo: scrapeInfo,
    ),
  );
}

class _MagnetAddDownloadDialog extends StatefulWidget {
  const _MagnetAddDownloadDialog({
    required this.item,
    required this.controller,
    required this.dialogTitle,
    this.presetDir,
    this.hint,
    this.initialScrapeInfo,
  });

  final MagnetSearchItem item;
  final MagnetController controller;
  final String dialogTitle;

  /// 预设目录（订阅自带下载目录等）；为空时用全局默认目录。
  final String? presetDir;

  /// 附加说明（如剪贴板检测到的原始链接）。
  final String? hint;

  /// 磁力页当前的关联番剧（下载前可在此更换 / 清除）。
  final MediaScrapeInfo? initialScrapeInfo;

  @override
  State<_MagnetAddDownloadDialog> createState() =>
      _MagnetAddDownloadDialogState();
}

class _MagnetAddDownloadDialogState extends State<_MagnetAddDownloadDialog> {
  /// 全局默认目录（异步解析，解析完成前为 null）。
  String? _defaultDir;

  /// 当前选中的目录，为空表示仍在解析默认值。
  String _selectedDir = '';
  bool _picking = false;

  /// 本次任务最终归属的番剧，可在弹窗内更换或清除。
  MediaScrapeInfo? _scrapeInfo;

  /// 用户是否手动改过归属：改过则以用户选择为准，不再按标题覆盖。
  bool _scrapeExplicit = false;

  @override
  void initState() {
    super.initState();
    _scrapeInfo = widget.initialScrapeInfo;
    final preset = widget.presetDir?.trim() ?? '';
    _selectedDir = preset.isNotEmpty
        ? preset
        : MagnetSessionDownloadDir.lastPicked?.trim() ?? '';
    _resolveDefaultDir();
  }

  /// 更换本次任务的归属番剧。
  Future<void> _pickAnime() async {
    final keyword = MediaScraper().cleanName(widget.item.title);
    final picked = await showBangumiMatchSheet(
      context,
      controller: widget.controller,
      initialKeyword: keyword,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _scrapeInfo = MediaScrapeInfo.fromBangumiItem(picked);
      _scrapeExplicit = true;
    });
  }

  Future<void> _resolveDefaultDir() async {
    final dir = await LibtorrentEngine.resolveDownloadDir();
    if (!mounted) return;
    setState(() {
      _defaultDir = dir;
      if (_selectedDir.isEmpty) {
        _selectedDir = dir;
      }
    });
  }

  bool get _usingCustomDir =>
      _defaultDir != null && _selectedDir != _defaultDir;

  Future<void> _pickDir() async {
    setState(() => _picking = true);
    try {
      final picked = await pickWritableDirectory(
        dialogTitle: '选择下载目录',
        initialDirectory: _selectedDir.isEmpty ? null : _selectedDir,
      );
      if (!mounted) return;
      if (picked == null) return;
      setState(() => _selectedDir = picked);
      MagnetSessionDownloadDir.lastPicked = picked;
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  void _resetToDefault() {
    final defaultDir = _defaultDir;
    if (defaultDir == null) return;
    setState(() => _selectedDir = defaultDir);
    MagnetSessionDownloadDir.reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final hint = widget.hint;
    return AlertDialog(
      title: Text(widget.dialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title.isEmpty ? '未命名任务' : item.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            if (hint != null && hint.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                hint,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (item.size.isNotEmpty || item.publisher != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: [
                  if (item.size.isNotEmpty)
                    _MetaText(icon: Icons.sd_storage_rounded, label: item.size),
                  if (item.publisher != null)
                    _MetaText(
                        icon: Icons.person_outline, label: item.publisher!),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _ScrapeTargetSection(
              info: _scrapeInfo,
              onPick: _pickAnime,
              onClear: () => setState(() {
                _scrapeInfo = null;
                _scrapeExplicit = true;
              }),
            ),
            const SizedBox(height: 16),
            _DownloadDirSection(
              dir: _selectedDir,
              picking: _picking,
              onPick: _pickDir,
              onReset: _usingCustomDir ? _resetToDefault : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _selectedDir.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    MagnetAddDownloadPlan(
                      dir: _selectedDir,
                      scrapeInfo: _scrapeInfo,
                      scrapeExplicit: _scrapeExplicit,
                    ),
                  ),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('添加下载'),
        ),
      ],
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 弹出「批量添加下载任务」确认框：为一批资源统一指定下载目录与归属番剧。
///
/// 批量下载常常一次十几集，若逐条弹目录确认，用户得点十几次才能下完，
/// 因此这里只问一次并统一应用。归属番剧留空时由调用方按每个资源的标题
/// 分别识别，不会把整批资源硬刮到同一部番剧上。
Future<MagnetAddDownloadPlan?> showMagnetBatchAddDownloadDialog(
  BuildContext context, {
  required List<MagnetSearchItem> items,
  required MagnetController controller,
  String? presetDir,
  MediaScrapeInfo? scrapeInfo,
}) {
  return KazumiDialog.show<MagnetAddDownloadPlan>(
    context: context,
    builder: (dialogContext) => _MagnetBatchAddDownloadDialog(
      items: items,
      controller: controller,
      presetDir: presetDir,
      initialScrapeInfo: scrapeInfo,
    ),
  );
}

class _MagnetBatchAddDownloadDialog extends StatefulWidget {
  const _MagnetBatchAddDownloadDialog({
    required this.items,
    required this.controller,
    this.presetDir,
    this.initialScrapeInfo,
  });

  /// 本次要提交的资源（调用方已剔除下载队列中已存在的条目）。
  final List<MagnetSearchItem> items;
  final MagnetController controller;

  /// 预设目录（订阅自带下载目录等）；为空时用全局默认目录。
  final String? presetDir;

  /// 磁力页当前的关联番剧，作为整批资源的默认归属。
  final MediaScrapeInfo? initialScrapeInfo;

  @override
  State<_MagnetBatchAddDownloadDialog> createState() =>
      _MagnetBatchAddDownloadDialogState();
}

class _MagnetBatchAddDownloadDialogState
    extends State<_MagnetBatchAddDownloadDialog> {
  /// 预览列表最多展示的条目数，其余用「等共 N 项」概括。
  static const int _previewLimit = 5;

  /// 全局默认目录（异步解析，解析完成前为 null）。
  String? _defaultDir;

  /// 当前选中的目录，为空表示仍在解析默认值。
  String _selectedDir = '';
  bool _picking = false;

  MediaScrapeInfo? _scrapeInfo;

  /// 用户是否手动改过归属：改过则以用户选择为准，不再按标题覆盖。
  bool _scrapeExplicit = false;

  @override
  void initState() {
    super.initState();
    _scrapeInfo = widget.initialScrapeInfo;
    final preset = widget.presetDir?.trim() ?? '';
    _selectedDir = preset.isNotEmpty
        ? preset
        : MagnetSessionDownloadDir.lastPicked?.trim() ?? '';
    _resolveDefaultDir();
  }

  bool get _usingCustomDir =>
      _defaultDir != null && _selectedDir != _defaultDir;

  Future<void> _resolveDefaultDir() async {
    final dir = await LibtorrentEngine.resolveDownloadDir();
    if (!mounted) return;
    setState(() {
      _defaultDir = dir;
      if (_selectedDir.isEmpty) _selectedDir = dir;
    });
  }

  /// 整批资源共用的归属番剧：用当前搜索词作为初始关键词更准，
  /// 拿第一条资源的完整标题去搜反而容易被字幕组 / 集数干扰。
  Future<void> _pickAnime() async {
    final query = widget.controller.query.trim();
    final keyword = query.isNotEmpty
        ? query
        : MediaScraper().cleanName(widget.items.first.title);
    final picked = await showBangumiMatchSheet(
      context,
      controller: widget.controller,
      initialKeyword: keyword,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _scrapeInfo = MediaScrapeInfo.fromBangumiItem(picked);
      _scrapeExplicit = true;
    });
  }

  Future<void> _pickDir() async {
    setState(() => _picking = true);
    try {
      final picked = await pickWritableDirectory(
        dialogTitle: '选择下载目录',
        initialDirectory: _selectedDir.isEmpty ? null : _selectedDir,
      );
      if (!mounted || picked == null) return;
      setState(() => _selectedDir = picked);
      MagnetSessionDownloadDir.lastPicked = picked;
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _resetToDefault() {
    final defaultDir = _defaultDir;
    if (defaultDir == null) return;
    setState(() => _selectedDir = defaultDir);
    MagnetSessionDownloadDir.reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.items;
    var totalBytes = 0;
    for (final item in items) {
      totalBytes += parseSizeToBytes(item.size) ?? 0;
    }
    final sizeLabel = totalBytes > 0 ? ' · 共约 ${formatBytes(totalBytes)}' : '';
    final preview = items.take(_previewLimit).toList();
    return AlertDialog(
      title: const Text('批量添加下载任务'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '已选 ${items.length} 个资源$sizeLabel',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in preview)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.downloading_rounded,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.title.isEmpty ? '未命名资源' : item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (items.length > preview.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '等共 ${items.length} 项',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ScrapeTargetSection(
              info: _scrapeInfo,
              onPick: _pickAnime,
              onClear: () => setState(() {
                _scrapeInfo = null;
                _scrapeExplicit = true;
              }),
              emptyHint: '自动识别（每个任务下载完成后按标题匹配）',
            ),
            const SizedBox(height: 16),
            _DownloadDirSection(
              dir: _selectedDir,
              picking: _picking,
              onPick: _pickDir,
              onReset: _usingCustomDir ? _resetToDefault : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _selectedDir.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    MagnetAddDownloadPlan(
                      dir: _selectedDir,
                      scrapeInfo: _scrapeInfo,
                      scrapeExplicit: _scrapeExplicit,
                    ),
                  ),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: Text('添加 ${items.length} 个'),
        ),
      ],
    );
  }
}

/// 「归属番剧」选择块：展示当前归属，可更换或清除（两类下载弹窗共用）。
class _ScrapeTargetSection extends StatelessWidget {
  const _ScrapeTargetSection({
    required this.info,
    required this.onPick,
    required this.onClear,
    this.emptyHint = '自动识别（下载完成后按资源标题匹配）',
  });

  final MediaScrapeInfo? info;
  final VoidCallback onPick;
  final VoidCallback onClear;

  /// 未指定归属时的说明文案（单条与批量的识别口径不同）。
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('归属番剧', style: theme.textTheme.labelLarge),
            const Spacer(),
            if (info != null)
              IconButton(
                tooltip: '不关联（下载完成后自动识别）',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
            TextButton(
              onPressed: onPick,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(info == null ? '指定番剧' : '更换'),
            ),
          ],
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            info == null
                ? emptyHint
                : '《${info!.displayName.isEmpty ? '未命名番剧' : info!.displayName}》',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// 「下载目录」选择块：展示目标目录，可更改或恢复默认（两类下载弹窗共用）。
class _DownloadDirSection extends StatelessWidget {
  const _DownloadDirSection({
    required this.dir,
    required this.picking,
    required this.onPick,
    this.onReset,
  });

  final String dir;
  final bool picking;
  final VoidCallback onPick;

  /// 恢复默认目录；为 null 时说明当前已是默认目录，不显示该入口。
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('下载目录', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            dir.isEmpty ? '正在解析默认目录…' : dir,
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            TextButton.icon(
              onPressed: picking ? null : onPick,
              icon: picking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('更改目录'),
            ),
            if (onReset != null)
              TextButton(
                onPressed: onReset,
                child: const Text('使用默认目录'),
              ),
          ],
        ),
      ],
    );
  }
}
