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

import 'package:excel/excel.dart' show TextCellValue;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_theme.dart';
import '../constants/time_periods.dart';
import '../utils/app_date.dart';
import '../models/attendance_record.dart';
import '../models/password_policy.dart';
import '../providers/app_data_provider.dart';
import '../services/statistics_service.dart';
import './identity_guard.dart';
import './identity_picker_dialog.dart';
import './password_action_guard.dart';
import './record_list.dart';
import './student_picker_dialog.dart';
import './confirm_destructive.dart';
import '../services/excel_export.dart';
import '../utils/app_clock.dart';

/// 考勤对话框：默认全员到齐，只登记请假、缺勤等异常。
/// 登记流程与"记录"一致：选学生（可多选）→ 选时间段（含"全天"）→ 选状态；
/// 异常记录按时间段分组列出，可逐条撤销，另有导出考勤表与清空全部时段。
class AttendanceDialog extends StatefulWidget {
  const AttendanceDialog({super.key});

  /// 打开考勤登记：身份在登记动作前校验；密码按动作级规则在登记/撤销时验证。
  static Future<void> show(BuildContext context) async {
    // 身份功能开启时先要求身份（避免输完密码才发现没选身份）。
    if (!await ensureIdentityForAction(context, action: '登记考勤')) return;
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (context) => const AttendanceDialog(),
    );
  }

  @override
  State<AttendanceDialog> createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends State<AttendanceDialog> {
  late String _date;

  @override
  void initState() {
    super.initState();
    // X-12：默认日期按"当前时段的归属日"取 —— 凌晨（跨零点时段的凌晨部分）
    // 打开考勤时默认落在前一天（入睡那天），与记录侧口径一致。
    final now = AppClock.now();
    _date = StatisticsService.dateString(
      attributionDay(now, matchPeriodByMinutes(now.hour * 60 + now.minute)),
    );
  }

  Future<void> _pickDate() async {
    final now = AppClock.now();
    final current = StatisticsService.parseDate(_date) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(now) ? now : current,
      firstDate: DateTime(2000, 1, 1),
      // 考勤为当天登记或事后补录，不允许登记未来日期。
      lastDate: now,
      helpText: '选择考勤日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null || !mounted) return;
    setState(() => _date = StatisticsService.dateString(picked));
  }

  /// 登记/修改考勤前确认记录人：与记录对话框同一口径 —— 功能开启时必须
  /// 有当前身份；窗口打开后身份闲置过期时，这里会再次要求选择。
  Future<bool> _ensureIdentity(AppDataProvider provider) async {
    if (!provider.identityFeatureEnabled || provider.activeIdentity != null) {
      return true;
    }
    if (!mounted) return false;
    showTopSnackBar(context, '登记考勤前请先选择本次记录人', isError: true);
    await showIdentityPicker(context);
    return mounted && provider.activeIdentity != null;
  }

  /// 登记考勤：选学生（多选）→ 选时间段 → 选状态，与"记录"的操作顺序一致。
  Future<void> _register(AppDataProvider provider) async {
    if (!await ensurePasswordForAction(
      context,
      provider,
      PasswordAction.attendanceRegister,
      message: '登记考勤会改动学生考勤数据，请先进入班主任管理。',
    )) {
      return;
    }
    if (!await _ensureIdentity(provider) || !mounted) return;
    final students = provider.appData.students;
    if (students.isEmpty) {
      showTopSnackBar(context, '名单为空，请先在设置中维护学生名单', isError: true);
      return;
    }
    // 当前时间段提示：已登记的学生在副标题里显示已有状态。
    final statusOf = <String, String>{};
    for (final record in provider.getAttendanceForDate(_date)) {
      statusOf.update(
        record.studentName,
        (old) => '$old、${record.status}',
        ifAbsent: () => record.status,
      );
    }
    final picked = await StudentPickerDialog.show(
      context,
      title: '选择学生（可多选）',
      students: students,
      multiSelect: true,
      subtitleBuilder: (name) =>
          statusOf[name] ?? AttendanceRecord.presentStatus,
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    final periodKey = await _pickPeriod();
    if (periodKey == null || !mounted) return;

    final status = await _pickStatus(provider, picked.length, periodKey);
    if (status == null || !mounted) return;
    // 选学生/时段/状态期间身份也可能过期，写盘前再确认一次。
    if (!await _ensureIdentity(provider) || !mounted) return;
    if (!provider.canActiveIdentityRegisterAttendance) {
      showTopSnackBar(context, '当前身份没有普通模式考勤登记权限', isError: true);
      return;
    }

    final changed = provider.setAttendanceForStudents(
      picked,
      status,
      date: _date,
      periodKey: periodKey,
    );
    if (!mounted) return;
    if (changed == 0) {
      showTopSnackBar(context, '所选学生在该时间段的状态没有变化');
      return;
    }
    final periodName = getTimePeriodName(periodKey);
    showTopSnackBar(
      context,
      status.isEmpty
          ? '已将 $changed 名学生该时段恢复为${AttendanceRecord.presentStatus}'
          : '已登记 $changed 名学生：$periodName · $status',
    );
  }

  /// 选择时间段：全天与"当前时段"直接列出（默认选中当前时段），
  /// 其余时段折叠在"其他时间段"里，避免一屏按钮。
  Future<String?> _pickPeriod() {
    final options = attendancePeriodOptions();
    final now = AppClock.now();
    final currentKey = matchPeriodByMinutes(now.hour * 60 + now.minute);
    final primary = <Map<String, String>>[
      options.first, // 全天
      if (currentKey != null && currentKey != AttendanceRecord.allDayKey)
        ...options.where((option) => option['key'] == currentKey),
    ];
    final others = options
        .where((option) => !primary.any((item) => item['key'] == option['key']))
        .toList();
    var selected = currentKey ?? AttendanceRecord.allDayKey;
    var expanded = false;

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final theme = Theme.of(dialogContext);
          final muted = mutedTextColor(theme, 0.65);
          Widget chip(Map<String, String> option) {
            final isCurrent = option['key'] == currentKey;
            return ChoiceChip(
              label: Text(
                '${option['label']}${isCurrent ? '（当前）' : ''}',
              ),
              selected: selected == option['key'],
              onSelected: (_) => setState(() => selected = option['key']!),
            );
          }

          return AlertDialog(
            title: const Text('选择时间段'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '已按当前时间预选时段，确认即可；需要补录其它时段时可展开。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final option in primary) chip(option)],
                  ),
                  if (others.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                        ),
                        label: Text(
                          expanded
                              ? '收起其他时间段'
                              : '其他时间段（${others.length}）',
                        ),
                        onPressed: () =>
                            setState(() => expanded = !expanded),
                      ),
                    ),
                    if (expanded)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [for (final option in others) chip(option)],
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, selected),
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 选择登记状态：状态项 + "出勤"（即撤销该时段的异常登记）。
  Future<String?> _pickStatus(
    AppDataProvider provider,
    int studentCount,
    String periodKey,
  ) {
    final statuses = provider.appData.settings.attendanceStatuses;
    final periodName = getTimePeriodName(periodKey);
    // 修复（审计 P2-66）：默认不预选状态 —— 触屏上"选学生→选时段→确认"
    // 两步就可能误登记；未选中时"确认登记"按钮置灰（G-42 已有该逻辑），
    // 强制老师明确选择（要撤销登记可选"出勤"）。
    String? selected;
    final syncMap = provider.appData.settings.attendanceSyncMap;
    final criticismEnabled = provider.appData.settings.criticismEnabled;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final theme = Theme.of(dialogContext);
          final muted = mutedTextColor(theme, 0.7);
          return AlertDialog(
            title: Text('为 $studentCount 名学生登记（$periodName）'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择考勤状态；选择"${AttendanceRecord.presentStatus}"表示该时段正常，'
                  '会撤销已有登记。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final status in statuses)
                      ChoiceChip(
                        label: Text(status),
                        selected: selected == status,
                        onSelected: (_) => setState(() => selected = status),
                      ),
                    ChoiceChip(
                      label: const Text(AttendanceRecord.presentStatus),
                      selected: selected == '',
                      onSelected: (_) => setState(() => selected = ''),
                    ),
                  ],
                ),
                if (selected != null && selected!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    !criticismEnabled
                        ? '当前“批评”记录类型已停用，本次只登记考勤，不会生成批评记录。'
                        : syncMap[selected] == null
                            ? '该状态只登记考勤，不会生成批评记录。'
                            : '登记后会在"批评"里同步一条原因「${syncMap[selected]}」的记录；'
                                  '在记录里选该原因也会自动登记考勤。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              // G-42：状态项为空时 selected 初始为 null，此前点"确认登记"会
              // pop(null) 被调用方当成"取消"——用户以为登记成功，实则静默失效。
              // 未选中任何状态时按钮置灰（此时"出勤"chip 可选，选了即可确认）。
              ElevatedButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.pop(dialogContext, selected),
                child: const Text('确认登记'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 撤销单条考勤登记（恢复为出勤）：仅考勤同步生成的批评记录一并删除，
  /// 老师手动录入的关联记录保留（修复 审计 P0-1）。
  Future<void> _undoRecord(
    AppDataProvider provider,
    AttendanceRecord record,
  ) async {
    final hasLinked = record.syncedRecordId.isNotEmpty;
    final confirmed = await confirmDestructive(
      context,
      title: '撤销考勤登记',
      message: '将 ${record.studentName} 的「${record.periodLabel} · '
          '${record.status}」撤销，恢复为${AttendanceRecord.presentStatus}。'
          '${hasLinked ? (record.syncedFromRecord ? '\n关联的批评记录由你手动录入，将保留。' : '\n同步生成的批评记录会一并删除。') : ''}',
      confirmLabel: '确定撤销',
    );
    if (!confirmed || !mounted) return;
    if (!await ensurePasswordForAction(
      context,
      provider,
      PasswordAction.attendanceUndo,
      message: '撤销考勤会改动考勤数据，请先进入班主任管理。',
    )) {
      return;
    }
    provider.setAttendance(
      record.studentName,
      '',
      date: _date,
      periodKey: record.periodKey,
      action: PasswordAction.attendanceUndo,
    );
    if (!mounted) return;
    showTopSnackBar(
      context,
      '已将 ${record.studentName} 该时段恢复为${AttendanceRecord.presentStatus}',
    );
  }

  Future<void> _clearDate(AppDataProvider provider, int count) async {
    if (count == 0) return;
    final confirmed = await confirmDestructive(
      context,
      title: '清空全部时间段',
      message: '将删除 ${formatChineseDate(_date)} 全部时间段的 $count 条异常考勤记录，'
          '同步生成的批评记录也会一并删除，所有学生恢复为'
          '${AttendanceRecord.presentStatus}。此操作不可撤销，确定继续吗？',
      confirmLabel: '确定清空',
    );
    if (!confirmed || !mounted) return;
    if (!await ensurePasswordForAction(
      context,
      provider,
      PasswordAction.attendanceUndo,
      message: '清空考勤会删除当日考勤记录，请先进入班主任管理。',
    )) {
      return;
    }
    final cleared = provider.clearAttendance(_date);
    if (!mounted) return;
    showTopSnackBar(context, '已清空 $cleared 条考勤记录');
  }

  /// 导出考勤表：应到/实到 + 各状态人次 + 异常名单（含时间段），
  /// 正常出勤不逐人展开，表尾写“其余正常出勤 N 人”。
  Future<void> _exportAttendance(AppDataProvider provider) async {
    final students = provider.appData.students;
    final records = provider.getAttendanceForDate(_date);
    final stats = provider.attendanceStats(_date);
    final byPeriod = provider.attendanceByPeriod(_date);
    // 与记录导出同一口径：启用身份或已有记录人时增加“记录人”列。
    final includeRecorder =
        provider.identityFeatureEnabled ||
        records.any((record) => record.recordedBy.isNotEmpty);
    // 按名单顺序导出；已从名单移除但留有考勤的学生补在末尾，避免漏数据。
    final ordered = <String>[
      ...students,
      // P3-1 修复：名单外学生按首次出现去重（此前有 N 条考勤就会重复输出 N 行）。
      ...<String>{
        for (final record in records)
          if (!students.contains(record.studentName)) record.studentName,
      },
    ];
    if (ordered.isEmpty) {
      showTopSnackBar(context, '名单为空，无法导出考勤表', isError: true);
      return;
    }

    try {
      final excelFile = ExcelExport.newWorkbook();
      final sheet = excelFile['Sheet1'];
      // 表头分段写：一行一个信息，避免首行过长在表格里显示不全。
      sheet.appendRow([TextCellValue('考勤日期：${formatChineseDate(_date)}')]);
      sheet.appendRow([
        TextCellValue(
          '应到 ${stats.total} 人 · 实到 ${stats.presentCount} 人',
        ),
      ]);
      final summaryText = stats.byStatus.entries
          .where((entry) => entry.value > 0)
          .map((entry) => '${entry.key} ${entry.value} 人次')
          .join(' · ');
      sheet.appendRow([
        TextCellValue(summaryText.isEmpty ? '异常情况：无' : '异常情况：$summaryText'),
      ]);
      // 名单外学生（已从名单移除但留有考勤）单列一行说明，避免明细里"多出人"看不出原因。
      if (stats.offRosterCount > 0) {
        sheet.appendRow([
          TextCellValue(
            '另有 ${stats.offRosterCount} 条记录来自已不在名单的学生（不计入应到人数）',
          ),
        ]);
      }
      // 修改1：只列异常名单（迟到/早退/请假/缺勤/自定义状态），
      // 正常出勤不再逐人展开，表尾统一写“其余正常出勤 N 人”。
      // 明细列与"设置 → 数据管理 → 导出与导入"中的考勤记录一致（日期/学生/时间段/状态/时间，
      // 启用身份时增加记录人），异常行仍可直接再导入回来。
      sheet.appendRow([
        TextCellValue('日期'),
        TextCellValue('学生姓名'),
        TextCellValue('时间段'),
        TextCellValue('考勤状态'),
        TextCellValue('登记时间'),
        if (includeRecorder) TextCellValue('记录人'),
      ]);
      for (final name in ordered) {
        final own = <AttendanceRecord>[
          for (final entry in byPeriod.entries)
            for (final record in entry.value)
              if (record.studentName == name) record,
        ];
        for (final record in own) {
          sheet.appendRow([
            TextCellValue(record.date),
            TextCellValue(name),
            TextCellValue(record.periodLabel),
            TextCellValue(record.status),
            TextCellValue(record.timestamp),
            if (includeRecorder)
              TextCellValue(
                record.recordedBy.isEmpty ? '未记录' : record.recordedBy,
              ),
          ]);
        }
      }
      // 名单内没有任何异常记录的学生 = 正常出勤；名单外学生不计入应到。
      final normalCount =
          (stats.total - stats.abnormalStudents).clamp(0, stats.total);
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([TextCellValue('其余正常出勤 $normalCount 人')]);
      ExcelExport.autoFitColumns(sheet);

      // 修复（审计 P1-19）：与记录/统计导出统一走 ExcelExport.saveWorkbook ——
      // 目录先建好、文件名消毒、原子写；此前目录不存在时会出现"记录导出成功、
      // 考勤导出失败"的入口间行为分歧。
      final exportPath = provider.appData.settings.exportPath;
      final fileName = provider.withExportPrefix('考勤表_$_date');
      final savedPath = await ExcelExport.saveWorkbook(
        excelFile,
        baseName: fileName,
        exportPath: exportPath,
        dialogTitle: '保存考勤表',
      );
      if (!mounted) return;
      showTopSnackBar(
        context,
        savedPath == null ? '已取消导出' : '导出成功: $savedPath',
      );
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, exportFailureMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final stats = provider.attendanceStats(_date);
    final byPeriod = provider.attendanceByPeriod(_date);

    final screen = MediaQuery.of(context).size;
    final width = dialogWidthFor(screen);

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      child: SizedBox(
        width: width,
        height: screen.height * 0.85,
        child: Column(
          children: [
            _buildAttendanceHeader(theme),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (provider.identityFeatureEnabled) ...[
                      IdentityBanner(
                        identity: provider.activeIdentity,
                        isEditing: false,
                        originalRecordedBy: '',
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildAttendanceSummaryCards(theme, stats),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _register(provider),
                          icon: const Icon(Icons.how_to_reg_outlined, size: 16),
                          label: const Text('登记考勤'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _exportAttendance(provider),
                          icon: const Icon(
                            Icons.file_download_outlined,
                            size: 16,
                          ),
                          label: const Text('导出考勤表'),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: stats.recordCount == 0
                              ? null
                              : () => _clearDate(provider, stats.recordCount),
                          icon: const Icon(
                            Icons.delete_sweep_outlined,
                            size: 16,
                          ),
                          label: const Text('清空全部时段'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '异常记录（按时间段）',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '没有登记的学生一律视为${AttendanceRecord.presentStatus}；'
                      '点学生后面的 × 可撤销该条登记，同步生成的批评记录会一并删除。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.65,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (byPeriod.isEmpty)
                      _buildAllPresentCard(theme)
                    else
                      for (final entry in byPeriod.entries)
                        _buildPeriodGroup(theme, provider, entry.key, entry.value),
                  ],
                ),
              ),
            ),
            _buildAttendanceFooter(theme, stats),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.semantic.subtleBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '考勤',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_outlined, size: 16),
            label: Text(formatChineseDate(_date)),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceSummaryCards(ThemeData theme, AttendanceStats stats) {
    final cards = <Widget>[
      _buildAttendanceSummaryCard(
        theme,
        '应到',
        '${stats.total}',
        theme.colorScheme.primary,
        Icons.groups_outlined,
      ),
      _buildAttendanceSummaryCard(
        theme,
        '实到',
        '${stats.presentCount}',
        theme.semantic.praise,
        Icons.how_to_reg_outlined,
      ),
    ];
    for (final entry in stats.byStatus.entries) {
      cards.add(
        _buildAttendanceSummaryCard(
          theme,
          entry.key,
          '${entry.value}',
          entry.value > 0
              ? theme.semantic.warning
              : mutedTextColor(theme, 0.5),
          Icons.event_busy_outlined,
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }

  Widget _buildAttendanceSummaryCard(
    ThemeData theme,
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    // X-24 同类修复：固定高度 82 在特大字号下会溢出（文字撑破卡片）——
    // 随字号等比放大，保证"界面字号=特大"时统计卡片不抛溢出。
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6);
    return Container(
      height: 82 * scale,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.semantic.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedTextColor(theme, 0.8),
                  ),
                ),
              ),
            ],
          ),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllPresentCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.semantic.subtleBorder),
      ),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 28,
            color: theme.semantic.praise,
          ),
          const SizedBox(height: 8),
          Text(
            '各时间段均无异常记录，全员到齐',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: mutedTextColor(theme, 0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodGroup(
    ThemeData theme,
    AppDataProvider provider,
    String periodKey,
    List<AttendanceRecord> records,
  ) {
    final statuses = provider.appData.settings.attendanceStatuses;
    // 同一时间段内按状态分组展示，方便一眼看出谁请假、谁迟到。
    final byStatus = <String, List<AttendanceRecord>>{};
    for (final record in records) {
      byStatus.putIfAbsent(record.status, () => <AttendanceRecord>[]).add(
            record,
          );
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.semantic.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            records.first.periodLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          for (final entry in byStatus.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    // X-24 修复：固定 96 宽在特大字号下会折行错位；
                    // 按实际字号等比例放大（各行列宽仍一致，行间对齐不破坏）。
                    width: 96 *
                        MediaQuery.textScalerOf(context)
                            .scale(1.0)
                            .clamp(1.0, 1.6),
                    child: Text(
                      '${entry.key}（${entry.value.length}）'
                      '${statuses.contains(entry.key) ? '' : ' · 已停用'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: statuses.contains(entry.key)
                            ? theme.semantic.warning
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final record in entry.value)
                          InputChip(
                            label: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(record.studentName),
                                if (record.recordedBy.isNotEmpty)
                                  Text(
                                    '记录人：${record.recordedBy}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: mutedTextColor(theme, 0.6),
                                    ),
                                  ),
                              ],
                            ),
                            // X-23 修复：触屏点按区域 —— 此前 compact 密度把
                            // × 的命中区压到不足 44；去掉 compact 并放大图标。
                            deleteIcon: const Icon(Icons.close, size: 20),
                            onDeleted: () => _undoRecord(provider, record),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAttendanceFooter(ThemeData theme, AttendanceStats stats) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.semantic.subtleBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              stats.recordCount == 0
                  ? '当前无异常记录'
                  : '共 ${stats.recordCount} 条异常记录'
                        '${stats.offRosterCount == 0 ? '' : '（含名单外 ${stats.offRosterCount} 条）'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedTextColor(theme, 0.7),
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
