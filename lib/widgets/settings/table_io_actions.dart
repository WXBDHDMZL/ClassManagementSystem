/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.11.0
 * 创建日期 (Created): 2026-07-25
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../settings_pages.dart';

/// 表格类导入导出动作（全部记录、学生名单导入、运行日志导出）。
/// 共享助手（保存文件/选文件/密码校验/通用确认）见 `shared_actions.dart`。

/// 导出全部记录（按日期合并为一张表）。
Future<void> _exportAllRecords(
  BuildContext context,
  AppDataProvider provider,
) async {
  final records = provider.getRecordsForDates(provider.getHistoryDates());
  if (records.isEmpty) {
    showTopSnackBar(context, '还没有任何记录', isError: true);
    return;
  }
  await RecordList.exportToExcel(
    context,
    records,
    '全部记录_${StatisticsService.todayString(AppClock.now())}',
  );
}

/// 导入名单：合并（补充缺失）或替换。
Future<void> _importStudents(
  BuildContext context,
  AppDataProvider provider,
) async {
  final verified = await _verifyForAction(
    context,
    provider,
    PasswordAction.rosterImport,
    '导入学生名单会改动现有名单，请先进入班主任管理。',
  );
  if (!verified || !context.mounted) return;
  final picked = await _pickTableFile(context, dialogTitle: '选择名单表格');
  if (picked == null || !context.mounted) return;
  List<List<String>> rows;
  final List<String> names;
  try {
    // 读取与解析同在一个兜底里：两者都可能因文件损坏而抛异常。
    rows = await TransferService.readRowsAsync(
      picked.bytes,
      isCsv: picked.isCsv,
      headerKeywords: const {'姓名', '学生姓名'},
    );
    names = TransferService.parseStudentsRows(rows);
  } on FormatException catch (e) {
    // 修复（审计 P1-17）：CSV 非 UTF-8 时透出专用引导（另存为 CSV UTF-8），
    // 不再泛化成"文件损坏"。
    if (!context.mounted) return;
    showTopSnackBar(context, e.message, isError: true);
    return;
  } catch (e) {
    if (!context.mounted) return;
    showTopSnackBar(context, '表格读取失败：文件可能已损坏或不是表格文件', isError: true);
    return;
  }
  // 性能批 H4：await（解码）之后界面可能已被销毁，后续 context 使用前补挂载检查。
  if (!context.mounted) return;
  if (names.isEmpty) {
    showTopSnackBar(context, '表格里没有解析到姓名（需要"姓名"列或第一列）', isError: true);
    return;
  }
  final existing = provider.appData.students;
  final newCount = names.where((name) => !existing.contains(name)).length;

  var replace = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('导入名单'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件：${picked.name}'),
            Text('解析到 ${names.length} 名学生，其中 $newCount 名是现有名单里没有的'),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: replace,
              onChanged: (value) => setState(() => replace = value ?? false),
              title: const Text('替换现有名单'),
              subtitle: const Text('不勾选时只补充缺失的学生；替换不会删除历史记录'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认导入'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;

  if (replace) {
    final ok = provider.replaceStudents(names);
    showTopSnackBar(
      context,
      ok ? '名单已替换为 ${names.length} 名学生' : '名单为空（或全部无效），未做替换',
      isError: !ok,
    );
  } else {
    final added = provider.mergeStudents(names);
    showTopSnackBar(context, '名单已补充 $added 名学生');
  }
}

// ---------- 运行日志 ----------

/// 导出操作日志（全量：按月日志文件按时间顺序拼接）。
Future<void> _exportOperationLog(
  BuildContext context,
  AppDataProvider provider,
) async {
  final verified = await ensurePasswordForAction(
    context,
    provider,
    PasswordAction.logExport,
    message: '导出操作日志会生成含学生姓名的明文文件，请先进入班主任管理。',
  );
  if (!verified || !context.mounted) return;
  // 日志已合并为单一文件；导出前解密为明文日志。
  final text = await OperationLogService.exportText();
  if (text.isEmpty) {
    if (!context.mounted) return;
    showTopSnackBar(context, '还没有操作日志', isError: true);
    return;
  }
  final bytes = utf8.encode(text);
  final path = await _saveExportFile(
    provider,
    fileName: '操作日志_导出_${StatisticsService.todayString(AppClock.now())}.txt',
    bytes: bytes,
  );
  if (!context.mounted) return;
  showTopSnackBar(context, path == null ? '已取消导出' : '操作日志导出成功: $path（明文，含姓名）');
}

/// 导出错误日志（全量：按月日志文件按时间顺序拼接；没有日志时提示）。
Future<void> _exportErrorLog(BuildContext context) async {
  final provider = Provider.of<AppDataProvider>(context, listen: false);
  final verified = await ensurePasswordForAction(
    context,
    provider,
    PasswordAction.logExport,
    message: '导出错误日志会生成明文文件，请先进入班主任管理。',
  );
  if (!verified || !context.mounted) return;
  // provider 在异步读之前取好（避免跨 await 再用 context 触发 use_build_context_synchronously）。
  final text = await exportErrorLogText();
  if (!context.mounted) return;
  if (text.isEmpty) {
    showTopSnackBar(context, '还没有错误日志（没有记录过错误）', isError: true);
    return;
  }
  final bytes = utf8.encode(text);
  final path = await _saveExportFile(
    provider,
    fileName: '错误日志_导出_${StatisticsService.todayString(AppClock.now())}.txt',
    bytes: bytes,
  );
  if (!context.mounted) return;
  showTopSnackBar(context, path == null ? '已取消导出' : '错误日志导出成功: $path（明文）');
}
