/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.8
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_data_provider.dart';
import '../models/password_policy.dart';
import '../utils/app_date.dart';
import './identity_guard.dart';
import './record_dialog.dart';
import './student_picker_dialog.dart';
import './record_list.dart';
import './password_action_guard.dart';
import '../constants/app_theme.dart';
import '../utils/app_clock.dart';

/// 历史记录对话框：左侧日期多选列表，右侧展示所选日期的记录；
/// 支持追加记录（需密码）、按日期导出/合并导出/分别导出/导出表扬批评排名。
class HistoryDialog extends StatefulWidget {
  const HistoryDialog({super.key});

  @override
  State<HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<HistoryDialog> {
  List<String> _selectedDates = [];

  /// 清理已不在历史列表中的"幽灵"日期（如该日期记录全部被删除后），
  /// 避免选中状态残留导致按钮与导出异常。
  ///
  /// 修复（审查 三-5）：只保留 **build 里的 Provider 订阅**这一条路径 ——
  /// 此前还额外手工 addListener，同一次数据变更会触发两条重建路径。
  /// 清理动作改在构建后执行（构建期不能 setState）。
  void _pruneSelectedDates(List<String> dates) {
    if (!_selectedDates.any((d) => !dates.contains(d))) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectedDates.removeWhere((d) => !dates.contains(d)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final dates = provider.getHistoryDates();
    _pruneSelectedDates(dates);
    // 只有当存在"未选中的中间日期"时才显示"选中之间"按钮。
    final hasFillable = _hasFillableDates(dates);

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '历史记录',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 200,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: theme.dividerColor),
                        ),
                      ),
                      child: Column(
                        children: [
                          if (hasFillable)
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: ElevatedButton(
                                onPressed: () => _fillDatesBetween(provider),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 40),
                                ),
                                child: const Text('选中之间'),
                              ),
                            ),
                          Expanded(
                            // 修复（审计 P2-65）：无历史记录时给出空态提示
                            //（此前左侧一片空白，像是加载失败）。
                            child: dates.isEmpty
                                ? Center(
                                    child: Text(
                                      '暂无历史记录',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: dates.length,
                                    itemBuilder: (context, index) =>
                                        _buildDateItem(dates[index]),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: _selectedDates.isEmpty
                              ? const Center(child: Text('请选择日期'))
                              : RecordList(
                                  records: provider.getRecordsForDates(
                                    _selectedDates,
                                  ),
                                  targetDate: _selectedDates.length == 1
                                      ? _selectedDates.first
                                      : null,
                                  selectedDates: _selectedDates,
                                ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              ElevatedButton(
                                onPressed: () =>
                                    _showAppendCalendar(context, provider),
                                child: const Text('追加记录'),
                              ),
                              const SizedBox(width: 8),
                              if (_selectedDates.isNotEmpty) ...[
                                if (_selectedDates.length == 1)
                                  ElevatedButton(
                                    onPressed: () => _exportSingleDate(
                                      context,
                                      provider,
                                      _selectedDates.first,
                                    ),
                                    child: const Text('导出记录'),
                                  ),
                                if (_selectedDates.length > 1) ...[
                                  ElevatedButton(
                                    onPressed: () =>
                                        _exportMerged(context, provider),
                                    child: const Text('合并导出记录'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () =>
                                        _exportSeparated(context, provider),
                                    child: const Text('分别导出记录'),
                                  ),
                                ],

                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateItem(String date) {
    final theme = Theme.of(context);
    final isSelected = _selectedDates.contains(date);

    final selectedColor =
        theme.colorScheme.primary.withValues(alpha: 0.1);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedDates.remove(date);
            } else {
              _selectedDates.add(date);
            }
          });
        },
        child: Container(
          // 用有明确边界的 Container 画选中底色，避免 ListTile 的
          // selectedTileColor 在列表边缘/滚动时出现高亮向上溢出的观感。
          color: isSelected ? selectedColor : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  date,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAppendCalendar(
    BuildContext parentContext,
    AppDataProvider provider,
  ) async {
    if (!await ensureIdentityForAction(parentContext, action: '追加记录')) return;
    if (!parentContext.mounted) return;
    if (!await ensurePasswordForAction(
      parentContext,
      provider,
      PasswordAction.recordAppend,
      message: '追加记录会写入历史数据，请先进入班主任管理。',
    )) {
      return;
    }
    if (!parentContext.mounted) return;
    await _showDatePicker(parentContext, provider);
  }

  Future<void> _showDatePicker(BuildContext context, AppDataProvider provider) async {
    // 可追加的最早日期：默认今年与上一年；
    // 若存在更早的历史记录，则放宽到最早记录所在的年份。
    final now = AppClock.now();
    var earliestYear = now.year - 1;
    for (final dateStr in provider.getHistoryDates()) {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final year = int.tryParse(parts[0]);
        if (year != null && year < earliestYear) {
          earliestYear = year;
        }
      }
    }
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: AppClock.now(),
      firstDate: DateTime(earliestYear, 1, 1),
      // 追加记录只允许选择今天及以前的日期。
      lastDate: AppClock.now(),
    );

    if (selectedDate != null && context.mounted) {
      final dateStr = formatYmd(selectedDate);
      await _showStudentMultiSelect(context, dateStr);
    }
  }

  Future<void> _showStudentMultiSelect(
    BuildContext parentContext,
    String dateStr,
  ) async {
    // 学生名单取自 provider，保证名单维护后此处同步生效。
    final studentList = Provider.of<AppDataProvider>(
      parentContext,
      listen: false,
    ).appData.students;

    final selectedStudents = await StudentPickerDialog.show(
      parentContext,
      title: '选择要追加记录的学生（可多选）',
      students: studentList,
      multiSelect: true,
    );
    if (selectedStudents == null || selectedStudents.isEmpty) return;
    if (!parentContext.mounted) return;
    await showAppendRecordDialog(
      parentContext,
      date: dateStr,
      students: selectedStudents,
    );
  }

  /// 是否存在未选中的"中间"日期（只在此时显示"选中之间"按钮，
  /// 避免点击后无任何变化）。
  bool _hasFillableDates(List<String> dates) {
    if (_selectedDates.length < 2) return false;
    final sorted = _selectedDates.toList()..sort();
    final first = sorted.first;
    final last = sorted.last;
    return dates
        .any((d) => d.compareTo(first) > 0 && d.compareTo(last) < 0);
  }

  void _fillDatesBetween(AppDataProvider provider) {
    if (_selectedDates.length < 2) return;

    final sorted = _selectedDates.toList()..sort();
    final startDate = sorted.first;
    final endDate = sorted.last;

    // 只填充真实存在（有记录）的日期，避免选中列表中不可见的幽灵日期。
    final existing = provider.getHistoryDates().toSet();
    final datesBetween = provider
        .getDatesBetween(startDate, endDate)
        .where(existing.contains)
        .toList();
    setState(() {
      _selectedDates = datesBetween;
    });
  }

  /// 导出文件名后缀：单日期用该日期，多日期用"起止日期"形式，避免文件名过长。
  String _exportFileSuffix(List<String> dates) {
    final sorted = dates.toList()..sort();
    if (sorted.isEmpty) return '记录';
    if (sorted.length == 1) return sorted.first;
    return '${sorted.first}_至_${sorted.last}';
  }

  Future<void> _exportSingleDate(
    BuildContext context,
    AppDataProvider provider,
    String date,
  ) async {
    final records = provider.getRecordsForDate(date);
    if (records.isEmpty) {
      showTopSnackBar(context, '该日期没有记录', isError: true);
      return;
    }
    await RecordList.exportToExcel(context, records, date, attendanceDate: date);
  }

  Future<void> _exportMerged(
    BuildContext context,
    AppDataProvider provider,
  ) async {
    final records = provider.getRecordsForDates(_selectedDates);
    if (records.isEmpty) {
      showTopSnackBar(context, '所选日期没有记录', isError: true);
      return;
    }
    await RecordList.exportToExcel(
      context,
      records,
      '合并记录_${_exportFileSuffix(_selectedDates)}',
    );
  }

  Future<void> _exportSeparated(
    BuildContext context,
    AppDataProvider provider,
  ) async {
    var exportedCount = 0;
    for (final date in _selectedDates) {
      // 导出期间用户可能关闭历史记录对话框，后续循环不能再使用已卸载的 context。
      if (!context.mounted) return;
      final records = provider.getRecordsForDate(date);
      if (records.isEmpty) continue;
      exportedCount++;
      await RecordList.exportToExcel(
        context,
        records,
        date,
        attendanceDate: date,
      );
    }
    if (exportedCount == 0) {
      if (!context.mounted) return;
      showTopSnackBar(context, '所选日期没有记录', isError: true);
    }
  }

}
