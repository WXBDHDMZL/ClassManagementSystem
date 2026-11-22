/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.0
 * 创建日期 (Created): 2026-11-21
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../services/library_import_service.dart';
import 'record_list.dart';

/// 时段导入对话框：粘贴或选择表格，预览后把时段列表回填到设置页。
class PeriodImportDialog extends StatefulWidget {
  const PeriodImportDialog({super.key});

  static Future<List<Map<String, String>>?> show(BuildContext context) {
    return showDialog<List<Map<String, String>>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PeriodImportDialog(),
    );
  }

  @override
  State<PeriodImportDialog> createState() => _PeriodImportDialogState();
}

class _PeriodImportDialogState extends State<PeriodImportDialog> {
  final TextEditingController _pasteController = TextEditingController();

  String _mode = 'paste';
  PeriodImportPreview? _preview;
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
          : LibraryImportService.parsePeriodsText(value);
    });
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择时段表文件',
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
      final preview = await LibraryImportService.parsePeriodsFile(
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      backgroundColor: theme.colorScheme.surface,
      child: Container(
        width: clampDialogWidth(MediaQuery.sizeOf(context), 520),
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
                    '导入时段',
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
                '每行一个时段：可以写“时段 key + 标签”，也可以只写标签；'
                '导入后先填入列表，点击“保存”才会生效。',
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
                    hintText: '粘贴时段，每行一个，例如：\n08:00-12:30 上课\n14:00-16:40 上课',
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
                  if (preview != null && preview.hasPeriods)
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, preview.periods),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.card,
                        ),
                      ),
                      child: const Text('应用到列表'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme, PeriodImportPreview? preview) {
    if (_readingFile) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (preview == null) return const SizedBox.shrink();
    if (!preview.hasPeriods) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: AppRadius.card,
        ),
        child: Text(
          preview.skipped > 0
              ? '没有识别到可导入的时段，${preview.skipped} 行无法识别'
              : '没有识别到可导入的时段',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      );
    }
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
            '识别到 ${preview.periods.length} 个时段'
            '${preview.skipped > 0 ? '，${preview.skipped} 行无法识别' : ''}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < preview.periods.length && i < 10; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${i + 1}. ${preview.periods[i]['label']}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: mutedTextColor(theme, 0.8),
                ),
              ),
            ),
          if (preview.periods.length > 10)
            Text(
              '… 还有 ${preview.periods.length - 10} 个',
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedTextColor(theme, 0.7),
              ),
            ),
        ],
      ),
    );
  }
}
