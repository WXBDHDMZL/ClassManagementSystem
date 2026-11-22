/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-07-25
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../settings_pages.dart';

/// 数据包导出/导入（含 _PackageImportDialog 整包还原确认对话框）。
/// 导出数据包（全部数据）。
Future<void> _exportPackage(
  BuildContext context,
  AppDataProvider provider,
) async {
  // 报告 L1：数据包是**明文** JSON（含全部姓名/记录/考勤）—— 导出与导入同
  // 口径先过门禁，并在成功提示里明示明文属性（此前导出无任何门禁）。
  final verified = await _verifyForAction(
    context,
    provider,
    PasswordAction.dataPackageExport,
    '导出数据包会在磁盘上生成明文文件（含全部记录与姓名），请先进入班主任管理。',
  );
  if (!verified || !context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('导出数据包'),
      content: Text(
        '数据包是明文 JSON，包含全部记录${AttendanceFeature.enabled ? '、考勤' : ''}、名单与姓名。\n'
        '请保存到只有你能访问的位置，不要发送给无关人员。\n\n是否继续？',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('继续导出'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final package = TransferService.buildPackage(
    provider.appData,
    exportedAt: AppClock.now().toString().split('.').first,
  );
  final path = await _saveExportFile(
    provider,
    fileName:
        '班级管理系统_数据包_${StatisticsService.todayString(AppClock.now())}.json',
    bytes: utf8.encode(package),
  );
  if (!context.mounted) return;
  showTopSnackBar(
    context,
    path == null ? '已取消导出' : '数据包导出成功: $path（该文件为明文，请妥善保管）',
  );
}

/// 导入数据包：可选恢复记录 / 名单 / 原因库 / 时间段 / 考勤。
Future<void> _importPackage(
  BuildContext context,
  AppDataProvider provider,
) async {
  final verified = await _verifyForAction(
    context,
    provider,
    PasswordAction.dataPackageImport,
    '导入数据包会向数据里写入内容，请先进入班主任管理。',
  );
  if (!verified || !context.mounted) return;
  final picked = await FilePicker.platform.pickFiles(
    dialogTitle: '选择数据包文件',
    type: FileType.custom,
    allowedExtensions: ['json'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty || !context.mounted) return;
  final bytes = picked.files.first.bytes;
  if (bytes == null) {
    showTopSnackBar(context, '读取文件失败，请重试', isError: true);
    return;
  }
  // 修复（审计 P1-13）：严格 UTF-8 —— 非 UTF-8 包此前被 allowMalformed
  // 静默修复成乱码后照常入库；现在直接拒绝并给出可操作的提示。
  final PackageData? data;
  try {
    data = TransferService.parsePackageBytes(bytes);
  } on FormatException {
    if (!context.mounted) return;
    showTopSnackBar(
      context,
      '文件不是 UTF-8 编码，可能不是本程序导出的数据包或已损坏；'
      '请用本程序重新导出后重试',
      isError: true,
    );
    return;
  }
  if (data == null) {
    showTopSnackBar(context, '不是有效的班级管理系统数据包', isError: true);
    return;
  }
  // 显式转存非空副本：在 try 块中被赋值的局部变量在闭包里不会保留
  // 空安全提升，下方 builder 需要非空的包对象。
  final PackageData package = data;
  if (!context.mounted) return;

  final result = await showDialog<List<String>>(
    context: context,
    builder: (dialogContext) =>
        _PackageImportDialog(fileName: picked.files.first.name, data: package),
  );
  if (result == null || result.isEmpty || !context.mounted) return;

  // 整包还原：直接整体替换，不再逐类合并。
  if (result.contains('replaceAll')) {
    final confirmed = await confirmDestructive(
      context,
      title: '确认整包还原',
      message:
          '将用数据包里的内容**整体替换**本机的记录、名单、原因库、'
          '时段${AttendanceFeature.enabled ? '、考勤记录与考勤状态' : ''}，'
          '本机现有数据会被覆盖且不可撤销。\n\n'
          '${AttendanceFeature.enabled && data.attendance == null ? '数据包未包含考勤记录，本机考勤会保留。\n\n' : ''}'
          '建议先"导出数据包"或"立即备份"。确定继续吗？',
      confirmLabel: '确定还原',
    );
    if (!confirmed || !context.mounted) return;
    // B-10：整包还原前自动备份；备份失败则中止。
    if (!await _autoBackupBeforeDestructive(context, provider)) return;
    if (!context.mounted) return;
    final writtenRecords = await provider.restoreFromPackage(data);
    if (!context.mounted) return;
    if (writtenRecords < 0) {
      showTopSnackBar(
        context,
        '整包还原后保存失败，已回滚到还原前数据。请检查磁盘空间或文件权限',
        isError: true,
      );
      return;
    }
    final saved = await provider.saveNow();
    if (!context.mounted) return;
    if (!saved) {
      showTopSnackBar(context, '整包还原后保存失败，请检查磁盘空间或文件权限', isError: true);
      return;
    }
    final restoredAttendance = provider.getAllAttendance().length;
    final attendanceSummary = !AttendanceFeature.enabled
        ? ''
        : data.attendance == null
        ? '考勤保留本机 $restoredAttendance 条 · '
        : '考勤 $restoredAttendance 条 · ';
    showTopSnackBar(
      context,
      '整包还原完成：记录 $writtenRecords 条 · '
      '$attendanceSummary'
      // X-16 修复：包内名单为空时，整包还原会**保持空名单**（S-8：不回落
      // 出厂/真实名单，避免隐私外溢），此前却提示"出厂名单"，与实际不符。
      '名单 ${data.students.isEmpty ? '空（包内未包含）' : '${data.students.length} 人'}',
    );
    return;
  }

  final messages = <String>[];
  // 修复（1.29，2026-10-03 审查）：每周起始日、考勤开关与同步映射此前被
  // 错挂在"时间段"勾选项里，后改为独立恢复。
  // G-39：但此前是**无条件恢复** —— 用户只勾"学生名单"时这些设置仍会被悄悄改动，
  // 且"没有可导入的内容"提示与实际不符。现纳入独立勾选项 settings，未勾选则不动。
  // 数据包导入是复合流程：入口已验证 dataPackageImport，内部写名单/原因/
  // 记录/考勤/时段时不再要求各自的独立动作密码；否则会出现导入只成功一半。
  final applied = provider.runWithAuthorizedActionVoid(
    PasswordAction.dataPackageImport,
    () {
      if (result.contains('settings')) {
        // 审计 P1-18：旧数据包可能没有这两个字段，缺失时保持本机现值 ——
        // 此前回退值会把"每周起始日=周日"重置为周一、把启用中的考勤悄悄关掉。
        if (package.weekStart != null) {
          provider.setWeekStart(package.weekStart!);
        }
        if (package.attendanceEnabled != null) {
          provider.setAttendanceEnabled(package.attendanceEnabled!);
        }
        if (package.attendanceSyncMap != null) {
          provider.setAttendanceSyncMap(package.attendanceSyncMap!);
        }
        messages.add(AttendanceFeature.enabled ? '统计周期与考勤设置' : '统计周期设置');
      }
      if (result.contains('periods')) {
        final packagePeriods = package.periods;
        if (packagePeriods != null && packagePeriods.isNotEmpty) {
          provider.setPeriods(packagePeriods);
          messages.add('时间段设置（含自定义增删）');
        }
      }
      if (result.contains('students') && package.students.isNotEmpty) {
        final added = provider.mergeStudents(package.students);
        messages.add('名单（补充 $added 人）');
      }
      if (result.contains('reasons')) {
        final packageReasons = package.reasons;
        if (packageReasons != null) {
          final added = provider.mergeReasons(
            TransferService.rowsOfLibrary(packageReasons),
          );
          messages.add('原因库（补充 $added 条）');
        }
      }
      if (result.contains('records') && package.records.isNotEmpty) {
        // 与现有记录完全相同的跳过，避免重复导入。
        // X-15 修复：判重键改用 ImportService.recordIdentityKey（与表格导入同口径），
        // 此前自拼的键漏了"时段"与"备注"，会让仅这两项不同的记录被误判重复而丢行。
        final existing = provider.getRecordsForDates(
          provider.getHistoryDates(),
        );
        final keys = existing.map(ImportService.recordIdentityKey).toSet();
        final toImport = <StudentRecord>[];
        for (final record in package.records) {
          if (!keys.add(ImportService.recordIdentityKey(record))) continue;
          toImport.add(record);
        }
        final imported = provider.importRecords(toImport);
        messages.add('记录（新增 $imported 条）');
      }
      final packageAttendance = package.attendance;
      if (AttendanceFeature.enabled &&
          result.contains('attendance') &&
          packageAttendance != null &&
          packageAttendance.isNotEmpty) {
        // 修复（审计 P2-33）：状态项/未到名单缺失（null）时不改动本机。
        if (package.attendanceStatuses != null) {
          provider.mergeAttendanceStatuses(package.attendanceStatuses!);
        }
        provider.mergeAttendanceStatuses(
          packageAttendance.map((record) => record.status),
        );
        if (package.attendanceAbsentStatuses != null) {
          // "计入未到"的口径一并恢复（内部只保留仍在状态项里的名称）。
          provider.setAttendanceAbsentStatuses(
            package.attendanceAbsentStatuses!,
          );
        }
        final imported = provider.importAttendance(packageAttendance);
        messages.add('考勤（写入 $imported 条）');
      }
    },
  );
  if (!applied) {
    if (!context.mounted) return;
    showTopSnackBar(context, '导入授权已失效，请重新验证后重试', isError: true);
    return;
  }
  if (!context.mounted) return;
  showTopSnackBar(
    context,
    messages.isEmpty ? '没有可导入的内容' : '数据包导入完成：${messages.join('、')}',
  );
}

/// 数据包导入对话框：勾选要恢复的部分。
class _PackageImportDialog extends StatefulWidget {
  const _PackageImportDialog({required this.fileName, required this.data});

  final String fileName;
  final PackageData data;

  @override
  State<_PackageImportDialog> createState() => _PackageImportDialogState();
}

class _PackageImportDialogState extends State<_PackageImportDialog> {
  late final Set<String> _selected = {
    'records',
    'students',
    'reasons',
    'periods',
    'settings',
    if (AttendanceFeature.enabled) 'attendance',
  };

  /// 整包还原：用数据包内容整体替换本机数据（危险操作，需显式勾选）。
  bool _replaceAll = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    var reasonCount = 0;
    final packageReasons = data.reasons;
    if (packageReasons != null) {
      for (final type in const ['表扬', '批评']) {
        final groups = type == '表扬'
            ? packageReasons.praise
            : packageReasons.criticism;
        for (final reasons in groups.values) {
          reasonCount += reasons.length;
        }
      }
    }

    Widget row(String key, String title, String summary) {
      return CheckboxListTile(
        value: _selected.contains(key),
        onChanged: (value) => setState(() {
          if (value == true) {
            _selected.add(key);
          } else {
            _selected.remove(key);
          }
        }),
        title: Text(title),
        subtitle: Text(summary),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
      );
    }

    return AlertDialog(
      title: const Text('导入数据包'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('文件：${widget.fileName}'),
          if (data.exportedAt != null) Text('导出于：${data.exportedAt}'),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _replaceAll,
            onChanged: (value) => setState(() => _replaceAll = value ?? false),
            title: const Text('整包还原（覆盖现有数据）'),
            subtitle: Text(
              '勾选后：本机的记录、名单、原因库、时段'
              '${AttendanceFeature.enabled ? '、考勤记录与考勤状态' : ''}'
              '都会被数据包里的内容整体替换（不可撤销，建议先导出备份）；'
              '不勾选则按下面的分类做"补充"导入。',
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
          const Divider(height: 12),
          const Text('记录、名单、原因库都是"补充"导入，不会删除现有数据：'),
          row('records', '记录', '${data.records.length} 条（重复的自动跳过）'),
          row('students', '学生名单', '${data.students.length} 人（补充缺失的）'),
          row('reasons', '原因库', '$reasonCount 条（补充缺失的）'),
          row(
            'periods',
            '时间段设置',
            '${data.periods?.length ?? 0} 个时段',
          ),
          row(
            'settings',
            AttendanceFeature.enabled ? '统计周期与考勤设置' : '统计周期设置',
            AttendanceFeature.enabled ? '每周起始日、考勤开关、同步映射' : '每周起始日',
          ),
          if (AttendanceFeature.enabled && data.attendance == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('数据包未包含考勤记录，还原时保留本机考勤。'),
            ),
          if (AttendanceFeature.enabled && data.attendance != null)
            row(
              'attendance',
              '考勤记录',
              data.attendance!.isEmpty
                  ? '0 条（将清空本机考勤）'
                  : '${data.attendance!.length} 条（同一天同一学生以数据包为准）',
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(
            context,
            _replaceAll ? <String>['replaceAll'] : _selected.toList(),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _replaceAll
                ? Theme.of(context).colorScheme.error
                : null,
            foregroundColor: _replaceAll
                ? Theme.of(context).colorScheme.onError
                : null,
          ),
          child: Text(_replaceAll ? '确认整包还原' : '确认导入'),
        ),
      ],
    );
  }
}
