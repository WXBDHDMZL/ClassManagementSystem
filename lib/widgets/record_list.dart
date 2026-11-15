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
import 'package:excel/excel.dart' as excel;
import 'package:excel/excel.dart' show TextCellValue;
import 'dart:io';
import '../providers/app_data_provider.dart';
import '../models/app_settings.dart';
import '../models/attendance_record.dart';
import '../models/student_record.dart';
import '../constants/time_periods.dart';
import '../constants/app_theme.dart';
import '../constants/attendance_feature.dart';
import '../utils/app_date.dart';
import '../services/statistics_service.dart';
import './record_dialog.dart';
import './history_dialog.dart';
import './statistics_dialog.dart';
import './attendance_dialog.dart';
import './identity_guard.dart';
import 'app_notification.dart';
import './password_action_guard.dart';
import '../services/excel_export.dart';
import '../utils/app_clock.dart';

// 顶部提示已统一到 app_notification.dart。这里 re-export，保证既有 186 个
// `import 'record_list.dart'` 的调用点无需修改。
export 'app_notification.dart'
    show showTopSnackBar, showUndoTopSnackBar, AppNoticeHandle;

/// 导出失败的提示文案：文件写入类错误给出可操作的建议，其余保留原始信息便于排查。
String exportFailureMessage(Object error) {
  if (error is FileSystemException) {
    return '导出失败：无法写入文件，请检查导出路径是否存在、文件是否被占用，或磁盘是否已满';
  }
  return '导出失败：$error';
}

/// 记录列表面板：展示今日/指定日期的记录，支持编辑、删除（需密码）、
/// 查看历史与导出 Excel。同时提供全局顶部提示框 [showTopSnackBar]。
class RecordList extends StatelessWidget {
  final List<StudentRecord> records;
  final String? targetDate;
  final List<String>? selectedDates;

  const RecordList({
    super.key,
    required this.records,
    this.targetDate,
    this.selectedDates,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMultiDate = selectedDates != null && selectedDates!.length > 1;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.sheet,
        border: Border.all(color: theme.semantic.subtleBorder, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isMultiDate ? '历史记录' : (targetDate != null ? '记录列表' : '今日记录'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: records.isEmpty
                  ? Center(
                      child: Text(
                        '暂无记录',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    )
                  : isMultiDate
                  ? _buildMultiDateList(context)
                  : ListView.builder(
                      itemCount: records.length,
                      itemBuilder: (context, index) {
                        // 审查 M4 补漏（收口）：与历史列表同口径补稳定 key
                        // （行含可选备注行、行高不固定，故不加 itemExtent）。
                        final record = records[index];
                        return KeyedSubtree(
                          key: ObjectKey(record),
                          child: _buildRecordItem(context, record),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            if (!isMultiDate && targetDate == null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 用 Wrap 而非 Row：开启考勤后有三个按钮，面板较窄时自动换行，
                  // 避免右侧按钮被挤出面板（窗口最小尺寸下会溢出）。
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showHistory(context),
                        icon: const Icon(Icons.history, size: 16),
                        label: const Text('历史记录'),
                        style: OutlinedButton.styleFrom(
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.sheet,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _showStatistics(context),
                        icon: const Icon(Icons.bar_chart, size: 16),
                        label: const Text('数据统计'),
                        style: OutlinedButton.styleFrom(
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.sheet,
                          ),
                        ),
                      ),
                      // G-50：改用 context.select 窄订阅 —— 只在"考勤开关"变化时
                      // 重建这个按钮。此前 listen:false 不订阅，开关变化后按钮的
                      // 可用态要靠父级恰好重建才刷新。
                      if (AttendanceFeature.enabled &&
                          context.select<AppDataProvider, bool>(
                            (p) => p.appData.settings.attendanceEnabled,
                          ))
                        OutlinedButton.icon(
                          onPressed: () => _showAttendance(context),
                          icon: const Icon(Icons.how_to_reg_outlined, size: 16),
                          label: const Text('考勤'),
                          style: OutlinedButton.styleFrom(
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppRadius.sheet,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      // 当天只有考勤异常（没有表扬/批评记录）时同样可以导出。
                      onPressed:
                          records.isEmpty && !_hasTodayAttendance(context)
                          ? null
                          : () => _exportRecords(context),
                      icon: const Icon(Icons.file_download_outlined, size: 16),
                      label: const Text('导出今日记录'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiDateList(BuildContext context) {
    final groupedRecords = _groupRecordsByDate();
    final sortedDates = groupedRecords.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    // 扁平化为「日期头 + 记录」序列，交给 ListView.builder 按需构建。
    // 此前用 ListView(children:) 一次性构建上千条记录的整棵子树，
    // "选中之间"跨整学期时打开历史会明显卡顿、内存峰值高。
    final flat = <Object>[];
    for (final date in sortedDates) {
      flat.add(date); // String = 日期分组标题
      flat.addAll(groupedRecords[date]!);
    }

    return ListView.builder(
      itemCount: flat.length,
      itemBuilder: (context, index) {
        final item = flat[index];
        // 审查 M4：为列表元素补稳定 key（此前全部无 key，增删时元素状态可能
        // 错位）。用 ObjectKey(记录/日期串本身)而非 record.id —— 列表中混合
        // 日期头与记录、且旧数据可能存在空 id，id 作 key 有撞键风险。
        // 不用 itemExtent：记录行含可选备注行、文字可换行，行高不固定，
        // 固定高度会裁掉内容（触屏特大字号下更明显）。
        if (item is String) {
          return KeyedSubtree(
            key: ValueKey<String>('header_$item'),
            child: _buildDateHeader(context, item),
          );
        }
        final record = item as StudentRecord;
        return KeyedSubtree(
          key: ObjectKey(record),
          child: _buildRecordItem(context, record),
        );
      },
    );
  }

  /// 历史列表里的日期分组标题。
  Widget _buildDateHeader(BuildContext context, String date) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        formatChineseDate(date),
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: mutedTextColor(theme, 0.8),
        ),
      ),
    );
  }

  Map<String, List<StudentRecord>> _groupRecordsByDate() {
    final Map<String, List<StudentRecord>> groups = {};
    for (final record in records) {
      final date = record.date ?? '';
      if (!groups.containsKey(date)) {
        groups[date] = [];
      }
      groups[date]!.add(record);
    }
    return groups;
  }

  Widget _buildRecordItem(BuildContext context, StudentRecord record) {
    final theme = Theme.of(context);
    final isPraise = record.operationType == '表扬';
    // 时段显示：优先当前生效的名称；时段无法识别（如导入的外部数据）时
    // 退回记录里保存的名称，避免出现"原因 · "这种悬空分隔符、还丢信息。
    final periodLabel = periodNameForRecord(record.periodKey, record.periodName);
    final periodShortName = periodLabel.isEmpty
        ? ''
        : periodLabel.split(' ').last;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          record.studentName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (isPraise
                                      ? theme.semantic.praise
                                      : theme.semantic.criticize)
                                  .withValues(alpha: 0.2),
                          borderRadius: AppRadius.field,
                        ),
                        child: Text(
                          record.operationType,
                          style: TextStyle(
                            color: isPraise
                                ? theme.semantic.praise
                                : theme.semantic.criticize,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (record.isImported)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: AppRadius.field,
                          ),
                          child: Text(
                            '导入',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      if (record.isBatch || record.isAppended)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.semantic.warning.withValues(
                              alpha: 0.2,
                            ),
                            borderRadius: AppRadius.field,
                          ),
                          child: Text(
                            record.isBatch ? '批量' : '追加',
                            style: TextStyle(
                              color: theme.semantic.warning,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${record.reasons}'
                          '${periodShortName.isEmpty ? '' : ' · $periodShortName'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        record.timestamp,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (record.remark.isNotEmpty)
                    Text(
                      '备注: ${record.remark}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  if (record.recordedBy.isNotEmpty)
                    Text(
                      '记录人: ${record.recordedBy}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                // 触屏场景：图标按钮保留 44×44 的最小点按区域。
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: '修改',
                  padding: const EdgeInsets.all(10),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: () => _editRecord(context, record),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  tooltip: '删除',
                  padding: const EdgeInsets.all(10),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: () => _deleteRecord(context, record),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editRecord(BuildContext context, StudentRecord record) async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    // 班主任管理下不强制先选记录人：管理员可以改他人的记录，
    // 记录里的“记录人”仍保留原快照。
    if (!provider.isManagementMode &&
        !await ensureIdentityForAction(context, action: '修改记录')) {
      return;
    }
    if (!context.mounted) return;
    // 本人窗口内直接改；其他人/超时需进入班主任管理。
    if (!provider.canMutateRecord(record) &&
        !await ensureManagementMode(
          context,
          provider,
          message: '修改他人记录或超出本人编辑窗口，需要进入班主任管理。',
        )) {
      return;
    }
    if (!context.mounted) return;
    _doEdit(context, record);
  }

  void _doEdit(BuildContext context, StudentRecord record) {
    showDialog(
      context: context,
      builder: (context) => RecordDialog(
        studentName: record.studentName,
        editRecord: record,
        // 按记录自身日期定位，保证多日期视图下也能正确编辑。
        targetDate: record.date ?? targetDate,
      ),
    );
  }

  Future<void> _deleteRecord(
    BuildContext context,
    StudentRecord record,
  ) async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    if (!provider.isManagementMode &&
        !await ensureIdentityForAction(context, action: '删除记录')) {
      return;
    }
    if (!context.mounted) return;
    if (!provider.canMutateRecord(record) &&
        !await ensureManagementMode(
          context,
          provider,
          message: '删除他人记录或超出本人编辑窗口，需要进入班主任管理。',
        )) {
      return;
    }
    final deleted = provider.deleteRecord(record.id, date: record.date);
    if (!context.mounted) return;
    if (deleted) {
      showUndoTopSnackBar(
        context,
        '已删除：${record.studentName} · ${record.operationType}',
        onUndo: provider.undoLastRecordChange,
      );
    } else {
      showTopSnackBar(context, '未找到该记录，可能已被删除', isError: true);
    }
  }

  /// 当天是否有考勤异常（决定"导出今日记录"是否可用）。
  /// 修改5：未开启考勤功能时，记录导出不再附带考勤异常名单，此入口也不再影响可用态。
  bool _hasTodayAttendance(BuildContext context) {
    if (!AttendanceFeature.enabled) return false;
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    if (!provider.appData.settings.attendanceEnabled) return false;
    return provider
        .getAttendanceForDate(StatisticsService.todayString(AppClock.now()))
        .isNotEmpty;
  }

  void _exportRecords(BuildContext context) async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    final records = provider.getTodayRecords();
    // 文件名带日期，避免次日导出覆盖前一天的文件。
    final now = AppClock.now();
    final dateStr = StatisticsService.dateString(now);
    await exportToExcel(
      context,
      records,
      '今日记录_$dateStr',
      // 修改5：未开启考勤功能时，记录导出不附考勤异常名单。
      attendanceDate: AttendanceFeature.enabled &&
              provider.appData.settings.attendanceEnabled
          ? dateStr
          : null,
    );
  }

  void _showHistory(BuildContext context) {
    showDialog(context: context, builder: (context) => const HistoryDialog());
  }

  /// 打开数据统计对话框（纯展示，无需密码）。
  void _showStatistics(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const StatisticsDialog(),
    );
  }

  /// 打开考勤登记对话框（改动考勤数据，按"记录"密码策略校验）。
  void _showAttendance(BuildContext context) {
    AttendanceDialog.show(context);
  }

  // 说明（审查 二-1）：列宽自适应与"保存到哪"已统一到 services/excel_export.dart，
  // 不再定义在 Widget 里（此前统计导出反向依赖本 Widget）。

  /// 在单日记录表末尾追加当天的考勤异常名单（无异常时不追加）。
  static void _appendAttendanceRows(
    excel.Sheet sheet,
    AppDataProvider provider,
    String date,
  ) {
    if (!AttendanceFeature.enabled) return;
    final groups = provider.attendanceByPeriod(date);
    if (groups.isEmpty) return;
    final includeRecorder =
        provider.identityFeatureEnabled ||
        groups.values.any(
          (records) => records.any((record) => record.recordedBy.isNotEmpty),
        );
    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow([
      TextCellValue('考勤异常（按时间段；未列出即${AttendanceRecord.presentStatus}）'),
    ]);
    if (includeRecorder) {
      sheet.appendRow([
        TextCellValue('学生姓名'),
        TextCellValue('时间段'),
        TextCellValue('考勤状态'),
        TextCellValue('记录人'),
      ]);
    }
    for (final entry in groups.entries) {
      for (final record in entry.value) {
        sheet.appendRow([
          TextCellValue(record.studentName),
          TextCellValue(record.periodLabel),
          TextCellValue(record.status),
          if (includeRecorder)
            TextCellValue(
              record.recordedBy.isEmpty ? '未记录' : record.recordedBy,
            ),
        ]);
      }
    }
  }

  static Future<void> exportToExcel(
    BuildContext context,
    List<StudentRecord> records,
    String fileName, {
    String? attendanceDate,
  }) async {
    try {
      final provider = Provider.of<AppDataProvider>(context, listen: false);
      final exportPath = provider.appData.settings.exportPath;
      // 文件名统一带上"导出选项"里配置的前缀。
      fileName = provider.withExportPrefix(fileName);

      final excelFile = ExcelExport.newWorkbook();

      // 导出列可在"设置 → 数据管理 → 导出与导入 → 导出选项"里勾选（顺序固定）。
      final settings = provider.appData.settings;
      final columns = List<String>.from(settings.recordExportColumns);
      // 启用操作身份后，记录人列自动加入导出（旧设置里没有这一列时补上）。
      if (!columns.contains('recordedBy') &&
          (settings.identityFeatureEnabled ||
              records.any((record) => record.recordedBy.isNotEmpty))) {
        columns.add('recordedBy');
      }
      TextCellValue cellOf(StudentRecord record, String key) {
        return TextCellValue(switch (key) {
          'date' => record.date ?? '',
          'name' => record.studentName,
          'type' => record.operationType,
          'reason' => record.reasons,
          'period' => periodNameForRecord(record.periodKey, record.periodName),
          'time' => record.timestamp,
          'recordedBy' =>
            record.recordedBy.isEmpty ? '未记录' : record.recordedBy,
          'remark' => record.remark,
          // 未知列 key（设置残留/手工写入）不能把备注重复到别的列里。
          _ => '',
        });
      }

      // 统一按"日期 + 时间"升序导出，与记录导出的 buildRecordsXlsx 口径一致，
      // 避免同一份内容因入口不同（今日/单日/合并/全部）而顺序相反。
      final ordered = StatisticsService.sortByDateAndTime(records);
      final sheet = excelFile['Sheet1'];
      sheet.appendRow([
        for (final key in columns)
          TextCellValue(AppSettings.recordExportColumnTitles[key] ?? key),
      ]);
      for (final record in ordered) {
        sheet.appendRow([for (final key in columns) cellOf(record, key)]);
      }
      // 单日导出时附上当天考勤异常（网页版同样把请假名单附在记录后面）。
      // 修改5：考勤功能未开启时不附考勤异常名单。
      if (AttendanceFeature.enabled &&
          attendanceDate != null &&
          settings.attendanceEnabled) {
        _appendAttendanceRows(sheet, provider, attendanceDate);
      }
      ExcelExport.autoFitColumns(sheet);

      // 保存逻辑统一走服务层（审查 二-1：此前与统计导出各写一份且行为已分歧）。
      final savedPath = await ExcelExport.saveWorkbook(
        excelFile,
        baseName: fileName,
        exportPath: exportPath,
        dialogTitle: '保存记录',
      );
      if (!context.mounted) return;
      showTopSnackBar(
        context,
        savedPath == null ? '已取消导出' : '导出成功: $savedPath',
      );
    } catch (e) {
      if (context.mounted) {
        showTopSnackBar(context, exportFailureMessage(e), isError: true);
      }
    }
  }
}
