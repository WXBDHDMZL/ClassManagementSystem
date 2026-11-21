/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.1
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';

import 'text_prompt_dialog.dart';
import 'confirm_destructive.dart';
import 'student_import_dialog.dart';
import 'package:provider/provider.dart';
import '../constants/attendance_feature.dart';
import '../providers/app_data_provider.dart';
import '../constants/time_periods.dart';
import './record_list.dart';
import '../constants/app_theme.dart';

/// 二次确认对话框：确认返回 true，取消返回 null。
/// 审查 M9：骨架统一走 [confirmDestructive]（红色确认按钮口径一致）。
Future<bool?> _confirmAction(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return confirmDestructive(
    context,
    title: title,
    message: message,
    confirmLabel: '确定',
  );
}

/// 名单管理对话框：增删改、拖动排序学生名单，支持一键清空名单。
/// 改名会同步更新所有历史记录与考勤记录中的学生姓名。
class StudentManageDialog extends StatefulWidget {
  const StudentManageDialog({super.key});

  @override
  State<StudentManageDialog> createState() => _StudentManageDialogState();
}

class _StudentManageDialogState extends State<StudentManageDialog> {
  final TextEditingController _addController = TextEditingController();

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  void _add(AppDataProvider provider) {
    final error = AppDataProvider.validateStudentName(_addController.text);
    if (error != null) {
      showTopSnackBar(context, error, isError: true);
      return;
    }
    if (provider.addStudent(_addController.text)) {
      _addController.clear();
      showTopSnackBar(context, '已添加学生');
    } else {
      showTopSnackBar(context, '姓名已存在', isError: true);
    }
  }

  Future<void> _rename(AppDataProvider provider, String oldName) async {
    final newName = await showTextPrompt(
      context,
      title: '修改姓名',
      label: '姓名',
      initialValue: oldName,
    );
    if (newName == null || !mounted) return;
    final error = AppDataProvider.validateStudentName(newName);
    if (error != null) {
      showTopSnackBar(context, error, isError: true);
      return;
    }
    if (provider.renameStudent(oldName, newName)) {
      showTopSnackBar(
        context,
        AttendanceFeature.enabled
            ? '已修改，历史记录与考勤记录中的姓名同步更新'
            : '已修改，历史记录中的姓名同步更新',
      );
    } else {
      showTopSnackBar(context, '姓名已存在', isError: true);
    }
  }

  Future<void> _remove(AppDataProvider provider, String name) async {
    final confirmed = await _confirmAction(
      context,
      title: '删除学生',
      message: AttendanceFeature.enabled
          ? '确定从名单中删除「$name」吗？该学生已有的历史记录与考勤记录不会被删除。'
          : '确定从名单中删除「$name」吗？该学生已有的历史记录不会被删除。',
    );
    if (confirmed != true || !mounted) return;
    if (provider.removeStudent(name)) {
      showTopSnackBar(context, '已删除');
    } else if (mounted) {
      // P3-4 修复：删除失败不再静默（此前界面毫无反馈，用户以为删掉了）。
      showTopSnackBar(context, '删除失败：该学生可能正在被其他数据引用', isError: true);
    }
  }

  Future<void> _clear(AppDataProvider provider) async {
    final confirmed = await _confirmAction(
      context,
      title: '清空名单',
      message: AttendanceFeature.enabled
          ? '将清空当前名单（历史记录与考勤记录不受影响）。确定继续吗？'
          : '将清空当前名单（历史记录不受影响）。确定继续吗？',
    );
    if (confirmed != true || !mounted) return;
    provider.clearStudents();
    showTopSnackBar(context, '名单已清空');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final students = provider.appData.students;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      backgroundColor: theme.colorScheme.surface,
      child: Container(
        width: clampDialogWidth(MediaQuery.sizeOf(context), 460),
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
                    '名单管理',
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
                '共 ${students.length} 人（可拖动排序）',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: mutedTextColor(theme, 0.7),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 340,
                child: students.isEmpty
                    ? Center(
                        child: Text(
                          '名单为空，请在下方添加学生',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        itemCount: students.length,
                        onReorderItem: provider.reorderStudents,
                        itemBuilder: (context, index) =>
                            _buildStudentItem(theme, provider, index, students[index]),
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addController,
                      // N-3：让长度上限在输入时可见（超出会被拦下并提示），
                      // 而不是提交后莫名其妙失败。
                      maxLength: AppDataProvider.maxNameLength,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(AppRadius.cardValue)),
                        ),
                        hintText: '输入学生姓名',
                        counterText: '',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => _add(provider),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _add(provider),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.card,
                      ),
                    ),
                    child: const Text('新增'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed:
                        students.isEmpty ? null : () => _clear(provider),
                    icon: const Icon(Icons.playlist_remove, size: 16),
                    label: const Text('清空名单'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => StudentImportDialog.show(context),
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: const Text('导入名单'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.card,
                      ),
                    ),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 名单行（审查 L8：此前与下方原因行同名 `_buildItem`，改名区分）。
  Widget _buildStudentItem(
    ThemeData theme,
    AppDataProvider provider,
    int index,
    String name,
  ) {
    return Container(
      key: ValueKey('student_${index}_$name'),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.field,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              tooltip: '修改姓名',
              onPressed: () => _rename(provider, name),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 18),
              tooltip: '删除',
              onPressed: () => _remove(provider, name),
            ),
            // X-22 修复：拖动排序手柄此前命中区仅 ≈26×18，触屏上很难拖住。
            // 用 44×44 的最小触控区包住图标（视觉不变，可点/可拖范围变大）。
            ReorderableDragStartListener(
              index: index,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Center(child: Icon(Icons.drag_handle, size: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 原因管理对话框：按 表扬/批评 + 时段 维护原因库，
/// 支持新增、改名、删除、拖动排序与一键恢复默认原因。
class ReasonManageDialog extends StatefulWidget {
  const ReasonManageDialog({super.key});

  @override
  State<ReasonManageDialog> createState() => _ReasonManageDialogState();
}

class _ReasonManageDialogState extends State<ReasonManageDialog> {
  static const String _commonKey = '_common';

  String _operationType = '表扬';
  String _periodKey = _commonKey;
  final TextEditingController _addController = TextEditingController();

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  List<String> _currentReasons(AppDataProvider provider) {
    return provider.appData.reasons.groupReasons(_operationType, _periodKey);
  }

  void _add(AppDataProvider provider) {
    if (provider.addReason(_operationType, _periodKey, _addController.text)) {
      _addController.clear();
      showTopSnackBar(context, '已添加原因');
    } else {
      showTopSnackBar(context, '原因不能为空或已存在', isError: true);
    }
  }

  Future<void> _rename(AppDataProvider provider, String oldReason) async {
    final newReason = await showTextPrompt(
      context,
      title: '修改原因',
      label: '原因',
      initialValue: oldReason,
    );
    if (newReason == null || !mounted) return;
    if (provider.renameReason(
      _operationType,
      _periodKey,
      oldReason,
      newReason,
    )) {
      showTopSnackBar(context, '已修改原因');
    } else {
      showTopSnackBar(context, '原因不能为空或已存在', isError: true);
    }
  }

  Future<void> _remove(AppDataProvider provider, String reason) async {
    final confirmed = await _confirmAction(
      context,
      title: '删除原因',
      message: '确定删除原因「$reason」吗？该操作不可撤销。',
    );
    if (confirmed != true || !mounted) return;
    if (provider.removeReason(_operationType, _periodKey, reason)) {
      showTopSnackBar(context, '已删除原因');
    } else if (mounted) {
      showTopSnackBar(context, '删除失败：该原因可能正在被其他数据引用', isError: true);
    }
  }

  Future<void> _reset(AppDataProvider provider) async {
    final confirmed = await _confirmAction(
      context,
      title: '恢复默认原因',
      message: '将恢复为出厂默认的表扬/批评原因库，当前原因库会被替换。确定继续吗？',
    );
    if (confirmed != true || !mounted) return;
    provider.resetReasons();
    showTopSnackBar(context, '已恢复默认原因');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final reasons = _currentReasons(provider);

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
                    '原因管理',
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
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: '表扬', label: Text('表扬')),
                  ButtonSegment(value: '批评', label: Text('批评')),
                ],
                selected: {_operationType},
                onSelectionChanged: (selection) =>
                    setState(() => _operationType = selection.first),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildReasonPeriodChip(theme, _commonKey, '全时段通用'),
                  ...effectivePeriods().map((item) => item['key']!).map(
                    (key) => _buildReasonPeriodChip(
                      theme,
                      key,
                      getTimePeriodShortName(key),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '「${_periodLabel()}」原因（可拖动排序）',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: mutedTextColor(theme, 0.7),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 240,
                child: reasons.isEmpty
                    ? Center(
                        child: Text(
                          '该分组暂无可选原因，请在下方添加',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        itemCount: reasons.length,
                        onReorderItem: (oldIndex, newIndex) =>
                            provider.reorderReasons(
                              _operationType,
                              _periodKey,
                              oldIndex,
                              newIndex,
                            ),
                        itemBuilder: (context, index) =>
                            _buildReasonItem(theme, provider, index, reasons[index]),
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(AppRadius.cardValue)),
                        ),
                        hintText: '输入新原因',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => _add(provider),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _add(provider),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.card,
                      ),
                    ),
                    child: const Text('新增'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _reset(provider),
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('恢复默认原因'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.card,
                      ),
                    ),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _periodLabel() =>
      _periodKey == _commonKey ? '全时段通用' : getTimePeriodShortName(_periodKey);

  Widget _buildReasonPeriodChip(ThemeData theme, String key, String label) {
    final isSelected = _periodKey == key;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _periodKey = key),
      backgroundColor: theme.cardColor,
      selectedColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      checkmarkColor: theme.colorScheme.primary,
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.primary
            : theme.textTheme.bodyMedium?.color,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      side: BorderSide(color: theme.dividerColor),
    );
  }

  /// 原因行（审查 L8：此前与上方名单行同名 `_buildItem`，改名区分）。
  Widget _buildReasonItem(
    ThemeData theme,
    AppDataProvider provider,
    int index,
    String reason,
  ) {
    return Container(
      key: ValueKey('reason_${_operationType}_${_periodKey}_${index}_$reason'),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.field,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                reason,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              tooltip: '修改原因',
              onPressed: () => _rename(provider, reason),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 18),
              tooltip: '删除',
              onPressed: () => _remove(provider, reason),
            ),
            // X-22 修复：同名单页，拖动排序手柄命中区放大到 44×44。
            ReorderableDragStartListener(
              index: index,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Center(child: Icon(Icons.drag_handle, size: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
