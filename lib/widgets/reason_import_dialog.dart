/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.2
 * 创建日期 (Created): 2026-11-21
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_theme.dart';
import '../constants/time_periods.dart';
import '../providers/app_data_provider.dart';
import '../services/library_import_service.dart';
import '../services/transfer_service.dart';
import 'confirm_destructive.dart';
import 'record_list.dart';

/// 原因库导入对话框：粘贴文本或选择表格文件，预览后补充或整体替换。
class ReasonImportDialog extends StatefulWidget {
  const ReasonImportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ReasonImportDialog(),
    );
  }

  @override
  State<ReasonImportDialog> createState() => _ReasonImportDialogState();
}

class _ReasonImportDialogState extends State<ReasonImportDialog> {
  final TextEditingController _pasteController = TextEditingController();

  String _mode = 'paste';
  ReasonImportPreview? _preview;
  String? _fileName;
  bool _readingFile = false;

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  void _onPasteChanged(String value) {
    setState(() {
      _fileName = null;
      _preview = value.trim().isEmpty
          ? null
          : LibraryImportService.parseReasonsText(value);
    });
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择原因库文件',
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv', 'txt'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      showTopSnackBar(context, '读取文件失败，请重试', isError: true);
      return;
    }
    setState(() {
      _readingFile = true;
      _fileName = file.name;
      _preview = null;
    });
    try {
      final preview = await LibraryImportService.parseReasonsFile(
        bytes: bytes,
        fileName: file.name,
      );
      if (!mounted) return;
      setState(() {
        _readingFile = false;
        _preview = preview;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _readingFile = false);
      showTopSnackBar(context, '读取失败：$error', isError: true);
    }
  }

  Future<void> _merge(AppDataProvider provider, ReasonImportPreview preview) async {
    final added = provider.mergeReasons(preview.rows);
    if (!mounted) return;
    if (added == 0) {
      showTopSnackBar(context, '没有可补充的原因（可能全部已存在）', isError: true);
      return;
    }
    Navigator.pop(context);
    showTopSnackBar(context, '已补充 $added 条原因');
  }

  Future<void> _replace(
    AppDataProvider provider,
    ReasonImportPreview preview,
  ) async {
    final confirmed = await confirmDestructive(
      context,
      title: '替换原因库',
      message: '将用识别到的 ${preview.rows.length} 条原因替换当前原因库。'
          '历史记录里已保存的原因不会被删除。',
      confirmLabel: '替换',
    );
    if (confirmed != true || !mounted) return;
    final replaced = provider.setReasons(
      TransferService.libraryFromRows(preview.rows),
    );
    if (!replaced) {
      if (mounted) {
        showTopSnackBar(context, '替换失败：请先进入班主任管理', isError: true);
      }
      return;
    }
    Navigator.pop(context);
    showTopSnackBar(context, '已替换为 ${preview.rows.length} 条原因');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final preview = _preview;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      backgroundColor: theme.colorScheme.surface,
      child: Container(
        width: clampDialogWidth(MediaQuery.sizeOf(context), 560),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '导入原因',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: theme.colorScheme.onSurface),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Text(
                '表格列为“类型 / 时段 / 原因”；只有“类型 / 原因”两列时归入全时段通用。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: mutedTextColor(theme, 0.7),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'paste',
                    icon: Icon(Icons.content_paste, size: 16),
                    label: Text('粘贴文本'),
                  ),
                  ButtonSegment(
                    value: 'file',
                    icon: Icon(Icons.folder_open, size: 16),
                    label: Text('选择文件'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) {
                  setState(() {
                    _mode = selection.first;
                    _preview = null;
                    _fileName = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              if (_mode == 'paste')
                TextField(
                  controller: _pasteController,
                  minLines: 5,
                  maxLines: 8,
                  onChanged: _onPasteChanged,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(AppRadius.cardValue),
                      ),
                    ),
                    hintText: '粘贴原因，每行一条，例如：\n表扬\t上课\t认真听课\n批评\t课间\t追逐打闹',
                    alignLabelWithHint: true,
                  ),
                )
              else
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _readingFile ? null : _pickFile,
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: Text(_readingFile ? '正在读取…' : '选择文件'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _fileName ?? '支持 .xlsx、.csv、.txt',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: mutedTextColor(theme, 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              _buildPreview(theme, preview),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const Spacer(),
                  if (preview != null && preview.hasRows) ...[
                    TextButton(
                      onPressed: () => _merge(provider, preview),
                      child: const Text('补充到原因库'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _replace(provider, preview),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.card,
                        ),
                      ),
                      child: const Text('替换原因库'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme, ReasonImportPreview? preview) {
    if (_readingFile) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (preview == null) return const SizedBox.shrink();
    if (!preview.hasRows) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: AppRadius.card,
        ),
        child: Text(
          preview.skipped > 0
              ? '没有识别到可导入的原因，${preview.skipped} 行无法识别'
              : '没有识别到可导入的原因',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      );
    }
    final sample = preview.rows.take(8).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '识别到 ${preview.rows.length} 条原因'
            '（表扬 ${preview.praiseCount} / 批评 ${preview.criticismCount}）'
            '${preview.skipped > 0 ? '，${preview.skipped} 行无法识别' : ''}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (final row in sample)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${row.operationType} · '
                '${row.periodKey == '_common' ? '全时段通用' : getTimePeriodName(row.periodKey)}'
                ' · ${row.reason}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: mutedTextColor(theme, 0.8),
                ),
              ),
            ),
          if (preview.rows.length > sample.length)
            Text(
              '… 还有 ${preview.rows.length - sample.length} 条',
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedTextColor(theme, 0.7),
              ),
            ),
        ],
      ),
    );
  }
}
