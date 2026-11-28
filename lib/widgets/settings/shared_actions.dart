/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.2
 * 创建日期 (Created): 2026-10-05 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

part of '../settings_pages.dart';

/// 设置页共享动作助手（跨多个 part 文件使用）。
///
/// 审查报告 M13：这四个助手此前定义在 `table_io_actions.dart`（"表格导入导出
/// 动作"）里 —— 一个**名为表格 IO 的文件实际是密码校验与文件选择的定义地**，
/// 想重构密码校验必须先 grep 才知道 11 个调用点散在哪。拆到本文件后，
/// 文件名的职责与内容一致，且仍保持 library 私有（调用点零改动）。
///
/// 内容：
///  - [_saveExportFile]：导出文件落盘（导出目录或"另存为"对话框）
///  - [_pickTableFile]：选择表格文件并读出字节
///  - [_verifyForAction]：按动作级密码策略校验
///  - [_confirmAction]：通用二次确认（非破坏性样式）

/// 保存导出文件：设置了导出路径就直接写，否则弹保存对话框；返回路径（取消返回 null）。
Future<String?> _saveExportFile(
  AppDataProvider provider, {
  required String fileName,
  required List<int> bytes,
}) async {
  // 文件名统一带上"导出选项"里配置的前缀。
  // G-35：再统一消毒 —— 去掉路径分隔符/非法字符/`..`，避免把文件写到导出目录之外。
  fileName = sanitizeFileName(provider.withExportPrefix(fileName));
  final exportPath = provider.appData.settings.exportPath;
  if (exportPath.isNotEmpty) {
    // G-35：导出目录不存在时先建好（此前 `writeAsBytes` 会直接失败）；
    // 改为原子写，避免中断留下半个文件。
    await Directory(exportPath).create(recursive: true);
    final filePath = '$exportPath/$fileName';
    await AtomicFile.writeBytes(filePath, bytes);
    return filePath;
  }
  final extension = fileName.contains('.')
      ? fileName.split('.').last
      : 'dat';
  final target = await FilePicker.platform.saveFile(
    dialogTitle: '保存文件',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: [extension],
  );
  if (target == null) return null;
  await AtomicFile.writeBytes(target, bytes);
  return target;
}

/// 选择表格文件并读出内容。
Future<({List<int> bytes, String name, bool isCsv})?> _pickTableFile(
  BuildContext context, {
  required String dialogTitle,
}) async {
  final picked = await FilePicker.platform.pickFiles(
    dialogTitle: dialogTitle,
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'csv'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return null;
  final file = picked.files.first;
  final bytes = file.bytes;
  if (bytes == null) {
    if (context.mounted) {
      showTopSnackBar(context, '读取文件失败，请重试', isError: true);
    }
    return null;
  }
  return (
    bytes: bytes,
    name: file.name,
    isCsv: (file.extension ?? '').toLowerCase() == 'csv',
  );
}

/// 动作级验证：先身份（若开启），再按该动作的密码规则验证。
Future<bool> _verifyForAction(
  BuildContext context,
  AppDataProvider provider,
  PasswordAction action,
  String message, {
  bool requireIdentity = true,
}) async {
  if (requireIdentity &&
      !await ensureIdentityForAction(context, action: '此操作')) {
    return false;
  }
  if (!context.mounted) return false;
  return ensurePasswordForAction(
    context,
    provider,
    action,
    message: message,
  );
}

/// 破坏性操作（整包还原/从备份恢复/恢复出厂）执行前自动备份当前数据。
/// 备份失败则不继续（B-10），避免“覆盖完才发现没有退路”。
Future<bool> _autoBackupBeforeDestructive(
  BuildContext context,
  AppDataProvider provider,
) async {
  final result = await provider.performBackup();
  if (!result.isSuccess) {
    if (context.mounted) {
      showTopSnackBar(
        context,
        '操作前自动备份失败：${result.error ?? '未知错误'}，已取消本次操作',
        isError: true,
      );
    }
    return false;
  }
  return true;
}

/// 二次确认：确认返回 true，取消返回 false。
Future<bool?> _confirmAction(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
