import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/magnet/magnet_controller.dart';
import 'package:kazumi/services/magnet/libtorrent_engine.dart';
import 'package:kazumi/services/magnet/magnet_models.dart';
import 'package:kazumi/services/media/local_media_models.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/directory_picker.dart';

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
Future<void> confirmAndAddMagnetDownload(
  BuildContext context, {
  required MagnetController controller,
  required MagnetSearchItem item,
  String? presetDir,
  MediaScrapeInfo? scrapeInfo,
  String dialogTitle = '添加下载任务',
  String? hint,
}) async {
  var dir = presetDir;
  if (GStorage.getSetting(SettingsKeys.magnetAskDirOnAdd)) {
    final picked = await showMagnetAddDownloadDialog(
      context,
      item: item,
      presetDir: presetDir,
      dialogTitle: dialogTitle,
      hint: hint,
    );
    // 用户取消或页面已销毁。
    if (picked == null || !context.mounted) return;
    dir = picked;
  }
  await controller.addDownload(item, dir: dir, scrapeInfo: scrapeInfo);
}

/// 弹出「添加下载任务」确认框，可在此为本次任务单独指定下载目录。
///
/// 返回目标目录；用户取消时返回 null。
Future<String?> showMagnetAddDownloadDialog(
  BuildContext context, {
  required MagnetSearchItem item,
  String? presetDir,
  String dialogTitle = '添加下载任务',
  String? hint,
}) {
  return KazumiDialog.show<String>(
    context: context,
    builder: (dialogContext) => _MagnetAddDownloadDialog(
      item: item,
      presetDir: presetDir,
      dialogTitle: dialogTitle,
      hint: hint,
    ),
  );
}

class _MagnetAddDownloadDialog extends StatefulWidget {
  const _MagnetAddDownloadDialog({
    required this.item,
    required this.dialogTitle,
    this.presetDir,
    this.hint,
  });

  final MagnetSearchItem item;
  final String dialogTitle;

  /// 预设目录（订阅自带下载目录等）；为空时用全局默认目录。
  final String? presetDir;

  /// 附加说明（如剪贴板检测到的原始链接）。
  final String? hint;

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

  @override
  void initState() {
    super.initState();
    final preset = widget.presetDir?.trim() ?? '';
    _selectedDir = preset.isNotEmpty
        ? preset
        : MagnetSessionDownloadDir.lastPicked?.trim() ?? '';
    _resolveDefaultDir();
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
                _selectedDir.isEmpty ? '正在解析默认目录…' : _selectedDir,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _picking ? null : _pickDir,
                  icon: _picking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('更改目录'),
                ),
                if (_usingCustomDir)
                  TextButton(
                    onPressed: _resetToDefault,
                    child: const Text('使用默认目录'),
                  ),
              ],
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
              : () => Navigator.pop(context, _selectedDir),
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
