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
import 'package:provider/provider.dart';

import '../constants/app_theme.dart';
import '../providers/app_data_provider.dart';
import '../services/student_import_service.dart';
import 'confirm_destructive.dart';
import 'record_list.dart';

/// 名单导入对话框：粘贴文本或选择文件，预览后补充到名单或替换现有名单。
class StudentImportDialog extends StatefulWidget {
  const StudentImportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const StudentImportDialog(),
    );
  }

  @override
  State<StudentImportDialog> createState() => _StudentImportDialogState();
}

class _StudentImportDialogState extends State<StudentImportDialog> {
  final TextEditingController _pasteController = TextEditingController();

  StudentImportSource _mode = StudentImportSource.paste;
  StudentImportPreview? _preview;
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
          : StudentImportService.parseText(value);
    });
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择名单文件',
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv', 'txt', 'docx'],
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
    final preview = await StudentImportService.parseFile(
      bytes: bytes,
      fileName: file.name,
    );
    if (!mounted) return;
    setState(() {
      _readingFile = false;
      _preview = preview;
    });
  }

  Future<void> _merge(AppDataProvider provider, List<String> names) async {
    final before = provider.appData.students.length;
    final added = provider.mergeStudents(names);
    final after = provider.appData.students.length;
    if (!mounted) return;
    if (added == 0 && after == before) {
      showTopSnackBar(context, '没有可补充的姓名（可能全部已在名单中）', isError: true);
      return;
    }
    Navigator.pop(context);
    showTopSnackBar(context, '已补充 $added 人');
  }

  Future<void> _replace(AppDataProvider provider, List<String> names) async {
    final confirmed = await confirmDestructive(
      context,
      title: '替换现有名单',
      message:
          '将用识别到的 ${names.length} 人替换当前 ${provider.appData.students.length} 人名单。历史记录不会被删除。',
      confirmLabel: '替换',
    );
    if (confirmed != true || !mounted) return;
    final ok = provider.replaceStudents(names);
    if (!mounted) return;
    if (!ok) {
      showTopSnackBar(context, '替换失败：没有可用的姓名', isError: true);
      return;
    }
    Navigator.pop(context);
    showTopSnackBar(context, '已替换为 ${names.length} 人');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final preview = _preview;
    final existing = provider.appData.students.toSet();

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
                    '导入名单',
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
                '可以从 Excel、CSV、文本或 Word 中读取姓名，也可以直接粘贴。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: mutedTextColor(theme, 0.7),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<StudentImportSource>(
                segments: const [
                  ButtonSegment(
                    value: StudentImportSource.paste,
                    icon: Icon(Icons.content_paste, size: 16),
                    label: Text('粘贴文本'),
                  ),
                  ButtonSegment(
                    value: StudentImportSource.tableFile,
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
              if (_mode == StudentImportSource.paste)
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
                    hintText: '粘贴姓名，每行一个，也可以用逗号、顿号或表格粘贴',
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
                        _fileName ?? '支持 .xlsx、.csv、.txt、.docx',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: mutedTextColor(theme, 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              _buildPreview(theme, preview, existing),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const Spacer(),
                  if (preview != null && preview.hasNames) ...[
                    TextButton(
                      onPressed: () => _merge(provider, preview.names),
                      child: const Text('补充到名单'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _replace(provider, preview.names),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.card,
                        ),
                      ),
                      child: const Text('替换现有名单'),
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

  Widget _buildPreview(
    ThemeData theme,
    StudentImportPreview? preview,
    Set<String> existing,
  ) {
    if (_readingFile) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (preview == null) {
      return const SizedBox.shrink();
    }
    if (preview.hasError) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: AppRadius.card,
        ),
        child: Text(
          preview.error!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      );
    }

    final alreadyInRoster = preview.names.where(existing.contains).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '识别到 ${preview.names.length} 人',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (alreadyInRoster > 0)
            Text(
              '其中 $alreadyInRoster 人已在当前名单中',
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedTextColor(theme, 0.7),
              ),
            ),
          if (preview.duplicateCount > 0)
            Text(
              '已合并 ${preview.duplicateCount} 个重复姓名',
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedTextColor(theme, 0.7),
              ),
            ),
          if (preview.invalid.isNotEmpty)
            Text(
              '跳过 ${preview.invalid.length} 个不合法姓名：${preview.invalid.take(5).join('、')}'
              '${preview.invalid.length > 5 ? '…' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in preview.names)
                    Chip(
                      label: Text(name),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
