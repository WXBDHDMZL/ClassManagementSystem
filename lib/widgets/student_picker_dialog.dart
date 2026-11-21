/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.13.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

/// 学生选择对话框：全程序统一样式（搜索框 + 学生列表 + 取消/确认）。
/// 追加记录用多选、统计明细用单选，操作方式与视觉保持一致。
class StudentPickerDialog extends StatefulWidget {
  const StudentPickerDialog({
    super.key,
    required this.title,
    required this.students,
    this.multiSelect = false,
    this.initialSelection = const [],
    this.subtitleBuilder,
  });

  final String title;
  final List<String> students;
  final bool multiSelect;
  final List<String> initialSelection;

  /// 每行右侧的补充说明（例如"表扬 3 · 批评 1"）。
  final String Function(String name)? subtitleBuilder;

  /// 打开选择框：确认返回选中的学生（至少一名），取消返回 null。
  static Future<List<String>?> show(
    BuildContext context, {
    required String title,
    required List<String> students,
    bool multiSelect = false,
    List<String> initialSelection = const [],
    String Function(String name)? subtitleBuilder,
  }) {
    return showDialog<List<String>>(
      context: context,
      builder: (context) => StudentPickerDialog(
        title: title,
        students: students,
        multiSelect: multiSelect,
        initialSelection: initialSelection,
        subtitleBuilder: subtitleBuilder,
      ),
    );
  }

  @override
  State<StudentPickerDialog> createState() => _StudentPickerDialogState();
}

class _StudentPickerDialogState extends State<StudentPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  late final Set<String> _selected = widget.initialSelection.toSet();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(String name, bool? value) {
    setState(() {
      if (widget.multiSelect) {
        if (value == true) {
          _selected.add(name);
        } else {
          _selected.remove(name);
        }
      } else {
        _selected
          ..clear()
          ..add(name);
      }
    });
  }

  /// 列表项：多选用复选框、单选用单选按钮，视觉与行为一致。
  Widget _buildTile(
    ThemeData theme,
    Color muted,
    String name, {
    required bool isCheckbox,
  }) {
    final subtitle = widget.subtitleBuilder?.call(name);
    final subtitleWidget = subtitle == null
        ? null
        : Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          );
    if (!isCheckbox) {
      return RadioListTile<String>(
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(name),
        subtitle: subtitleWidget,
        value: name,
      );
    }
    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(name),
      subtitle: subtitleWidget,
      value: _selected.contains(name),
      onChanged: (value) => _toggle(name, value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = mutedTextColor(theme, 0.65);
    final filtered = _query.isEmpty
        ? widget.students
        : widget.students.where((name) => name.contains(_query)).toList();

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      child: Container(
        width: clampDialogWidth(MediaQuery.sizeOf(context), 400),
        height: clampDialogHeight(MediaQuery.sizeOf(context), 520),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              widget.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: const InputDecoration(
                hintText: '搜索学生',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            // 修复（审计 P2-64）：多选时给出"已选 N 人 / 全选 / 清除" ——
            // 名单大时逐个勾选效率低、也难核对选了多少人。
            if (widget.multiSelect) ...[
              Row(
                children: [
                  Text(
                    '已选 ${_selected.length} 人',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(
                      () => _selected
                        ..clear()
                        ..addAll(widget.students),
                    ),
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selected.clear()),
                    child: const Text('清除'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的学生',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    )
                  : widget.multiSelect
                  ? ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) => KeyedSubtree(
                        // 审查 M4：补稳定 key（名单内姓名唯一，直接用作 key；
                        // 行含可选副标题可换行，行高不固定，故不用 itemExtent）。
                        key: ValueKey<String>(filtered[index]),
                        child: _buildTile(
                          theme,
                          muted,
                          filtered[index],
                          isCheckbox: true,
                        ),
                      ),
                    )
                  // 单选场景用单选按钮：复选框会让人误以为能多选。
                  : RadioGroup<String>(
                      groupValue: _selected.isEmpty ? null : _selected.first,
                      onChanged: (value) {
                        if (value != null) _toggle(value, true);
                      },
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => KeyedSubtree(
                          key: ValueKey<String>(filtered[index]),
                          child: _buildTile(
                            theme,
                            muted,
                            filtered[index],
                            isCheckbox: false,
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selected.toList()),
                  child: Text(
                    widget.multiSelect && _selected.isNotEmpty
                        ? '确认（${_selected.length} 人）'
                        : '确认',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
