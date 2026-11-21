/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/attendance_feature.dart';
import '../models/attendance_record.dart';
import '../models/password_policy.dart';
import '../models/student_record.dart';
import '../providers/app_data_provider.dart';
import '../services/import_service.dart';
import './record_list.dart';
import '../constants/app_theme.dart';

/// 导入记录确认对话框：先展示解析结果（可导入 / 跳过 / 重复 / 缺失学生），
/// 由用户选择重复处理方式后执行导入。
class ImportRecordsDialog extends StatefulWidget {
  const ImportRecordsDialog({
    super.key,
    required this.fileName,
    required this.preview,
  });

  final String fileName;
  final ImportPreview preview;

  /// 弹出确认对话框（取消或导入完成后自动关闭）。
  static Future<void> show(
    BuildContext context, {
    required String fileName,
    required ImportPreview preview,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => ImportRecordsDialog(
        fileName: fileName,
        preview: preview,
      ),
    );
  }

  @override
  State<ImportRecordsDialog> createState() => _ImportRecordsDialogState();
}

class _ImportRecordsDialogState extends State<ImportRecordsDialog> {
  /// 重复记录的处理方式：默认跳过，勾选后改为覆盖（先删旧记录再导入）。
  bool _overwriteDuplicates = false;

  /// 名单里没有的学生是否一并加入名单，默认加入。
  bool _addMissingStudents = true;

  /// 是否按当前映射同时补登考勤（B-04），默认勾选。
  bool _syncAttendance = true;

  /// 表格缺日期列时，必须显式确认“按今天导入”。
  bool _acknowledgeMissingDate = false;

  /// 估算会补登多少条考勤（同一日期+学生+时段只算一条）。
  int _attendanceCandidateCount(AppDataProvider provider) {
    if (!AttendanceFeature.enabled) return 0;
    final syncReasons = provider.appData.settings.attendanceSyncMap.values
        .where((reason) => reason.isNotEmpty)
        .toSet();
    if (syncReasons.isEmpty) return 0;
    final preview = widget.preview;
    final records = <StudentRecord>[
      ...preview.records,
      if (_overwriteDuplicates) ...preview.duplicateImports,
    ];
    final slots = <String>{};
    for (final record in records) {
      if (record.operationType != '批评') continue;
      final date = record.date;
      if (date == null || date.isEmpty) continue;
      if (!record.reasons.split('、').any(syncReasons.contains)) continue;
      // 与 importRecords 的实际补登口径一致：空时段按“全天”处理。
      final periodKey = record.periodKey.isEmpty
          ? AttendanceRecord.allDayKey
          : record.periodKey;
      slots.add('$date|${record.studentName}|$periodKey');
    }
    return slots.length;
  }

  void _submit() {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    final preview = widget.preview;
    final syncAttendance =
        _syncAttendance && _attendanceCandidateCount(provider) > 0;

    var overwritten = 0;
    var imported = 0;
    var attendanceGenerated = 0;
    void onAttendanceSynced(int count) => attendanceGenerated = count;
    var addedStudents = 0;
    var rejectedStudents = 0;
    // 导入是复合流程：入口已验证 recordImport，内部删除重复/补名单属于
    // 同一流程的子写入，不能要求用户再验证“删除/名单导入”。
    final applied = provider.runWithAuthorizedActionVoid(
      PasswordAction.recordImport,
      () {
        if (_overwriteDuplicates && preview.duplicates.isNotEmpty) {
          // 覆盖 = 先删旧记录，再把表格里的这一行写回去（否则会只删不写、丢数据）。
          overwritten = provider.deleteRecords(
            preview.duplicates,
            keepAttendance: true,
          );
          imported = provider.importRecords([
            ...preview.records,
            ...preview.duplicateImports,
          ], syncAttendance: syncAttendance, onAttendanceSynced: onAttendanceSynced);
        } else {
          imported = provider.importRecords(
            preview.records,
            syncAttendance: syncAttendance,
            onAttendanceSynced: onAttendanceSynced,
          );
        }
        if (_addMissingStudents && preview.unknownStudents.isNotEmpty) {
          final rosterResult =
              provider.addStudentsFromImport(preview.unknownStudents);
          addedStudents = rosterResult.added;
          rejectedStudents = rosterResult.rejected;
        }
      },
    );
    if (!applied) {
      showTopSnackBar(context, '导入授权已失效，请重新验证后重试', isError: true);
      return;
    }

    final message = StringBuffer('导入完成：新增 $imported 条');
    if (preview.skippedRows > 0) {
      message.write('，跳过 ${preview.skippedRows} 行');
    }
    if (preview.duplicates.isNotEmpty) {
      message.write(
        _overwriteDuplicates
            ? '，覆盖 $overwritten 条重复'
            : '，跳过 ${preview.duplicates.length} 条重复',
      );
    }
    // 修复（审计 P2-68）：文件内重复行如实提示（此前静默跳过、对不上行数）。
    if (preview.fileDuplicates > 0) {
      message.write('，跳过 ${preview.fileDuplicates} 行文件内重复');
    }
    if (addedStudents > 0) {
      message.write('，补充 $addedStudents 名学生到名单');
    }
    // 修复（审计 P2-69）：被拒的超长/空姓名提示出来（此前静默拒绝）。
    if (rejectedStudents > 0) {
      message.write('；另有 $rejectedStudents 个姓名不合法（空或超长）未加入名单');
    }
    if (AttendanceFeature.enabled && attendanceGenerated > 0) {
      message.write('，补登考勤 $attendanceGenerated 条');
    }
    // 复查 3.1：importRecords 会跳过"日期非法"的记录（写进操作日志），
    // 这里把差值也提示出来 —— 否则用户看到预览"可导入 3 条"、结果是
    // "新增 0 条"却完全不知道原因。
    final expectedCount = _overwriteDuplicates
        ? preview.records.length + preview.duplicateImports.length
        : preview.records.length;
    final silentlySkipped = expectedCount - imported;
    if (silentlySkipped > 0) {
      message.write('，跳过 $silentlySkipped 条日期非法（详情见操作日志）');
    }
    showTopSnackBar(context, message.toString());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = mutedTextColor(theme, 0.65);
    final preview = widget.preview;
    final canImport = preview.hasData;
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    final attendanceCandidates = _attendanceCandidateCount(provider);
    final needsDateAcknowledge =
        preview.missingDateColumn && !_acknowledgeMissingDate;

    return AlertDialog(
      title: const Text('导入记录'),
      // G-49：名单差异大时"名单缺失：张三、李四、…"会很长，此前非滚动对话框会竖向
      // 溢出（黄黑条）。开启滚动，内容超高时对话框内部可滚。
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoLine(theme, '文件', widget.fileName),
          _infoLine(
            theme,
            '可导入',
            '${preview.records.length} 条'
                '${preview.dateRange == null ? '' : '（${preview.dateRange}）'}',
          ),
          if (preview.skippedRows > 0)
            _infoLine(
              theme,
              '跳过',
              '${preview.skippedRows} 行（缺姓名/日期，或操作项目不是表扬/批评）',
            ),
          if (preview.duplicates.isNotEmpty)
            _infoLine(theme, '重复', '${preview.duplicates.length} 条与现有记录完全相同'),
          // 修复（审计 P2-68）：文件内重复单列一行（此前静默跳过）。
          if (preview.fileDuplicates > 0)
            _infoLine(
              theme,
              '文件内重复',
              '${preview.fileDuplicates} 行（同一文件里完全相同的行只导入第一条）',
            ),
          // B-07：缺日期列必须明示，不能静默按今天导入。
          if (preview.missingDateColumn)
            _infoLine(
              theme,
              '⚠ 日期',
              '表格没有“日期”列：所有记录将按今天导入，请确认后再继续',
            ),
          if (AttendanceFeature.enabled && attendanceCandidates > 0)
            _infoLine(
              theme,
              '补登考勤',
              '按当前映射可补登约 $attendanceCandidates 条（已有考勤不覆盖）',
            ),
          if (preview.unknownStudents.isNotEmpty)
            _infoLine(theme, '名单缺失', preview.unknownStudents.join('、')),
          const SizedBox(height: 8),
          if (preview.duplicates.isNotEmpty)
            CheckboxListTile(
              value: _overwriteDuplicates,
              onChanged: (value) =>
                  setState(() => _overwriteDuplicates = value ?? false),
              title: Text('用表格里的内容覆盖重复记录', style: theme.textTheme.bodyMedium),
              subtitle: Text(
                '不勾选时保留现有记录，只导入新记录',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          if (preview.unknownStudents.isNotEmpty)
            CheckboxListTile(
              value: _addMissingStudents,
              onChanged: (value) =>
                  setState(() => _addMissingStudents = value ?? false),
              title: Text('把缺失的学生加入名单', style: theme.textTheme.bodyMedium),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          if (AttendanceFeature.enabled && attendanceCandidates > 0)
            CheckboxListTile(
              value: _syncAttendance,
              onChanged: (value) =>
                  setState(() => _syncAttendance = value ?? false),
              title: Text(
                '同时按当前考勤映射补登考勤',
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text(
                '只补充“批评 → 迟到/早退/缺勤”等已配置映射；已有考勤不会被覆盖',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          if (preview.missingDateColumn)
            CheckboxListTile(
              value: _acknowledgeMissingDate,
              onChanged: (value) =>
                  setState(() => _acknowledgeMissingDate = value ?? false),
              title: Text(
                '我已知晓：没有日期列，导入到今天的日期',
                style: theme.textTheme.bodyMedium,
              ),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          const SizedBox(height: 4),
          Text(
            '导入的记录会标记为"导入"，可在历史记录中查看与修改。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: canImport && !needsDateAcknowledge ? _submit : null,
          child: Text(
            !canImport
                ? '没有可导入的记录'
                : needsDateAcknowledge
                ? '请先确认按今天导入'
                : '确认导入',
          ),
        ),
      ],
    );
  }

  Widget _infoLine(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedTextColor(theme, 0.65),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
