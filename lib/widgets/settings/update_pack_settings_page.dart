/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.7
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../settings_pages.dart';

/// 程序更新设置页：选择官方安装包并覆盖升级。
class UpdatePackSettingsPage extends StatefulWidget {
  const UpdatePackSettingsPage({super.key});

  @override
  State<UpdatePackSettingsPage> createState() => _UpdatePackSettingsPageState();
}

class _UpdatePackSettingsPageState extends State<UpdatePackSettingsPage> {
  /// 选择本地安装包并启动它（必须先退出本程序，安装程序才能替换文件）。
  /// 运行更新包会退出程序并覆盖安装，按“程序更新”策略校验密码。
  Future<void> _pickInstaller() async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    final verified = await _verifyForAction(
      context,
      provider,
      PasswordAction.updateRun,
      '运行更新包会退出程序并覆盖安装，请先进入班主任管理。',
    );
    if (!verified || !mounted) return;
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择更新包（安装程序）',
      type: FileType.custom,
      allowedExtensions: ['exe', 'msi'],
    );
    final path = picked?.files.first.path;
    if (path == null || !mounted) return;
    final name = path.split(RegExp(r'[/\\]')).last;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('安装更新包'),
        content: Text(
          '即将运行安装程序：\n$name\n\n'
          '程序内更新会自动安装，本程序会先退出，安装成功后自动重新打开；'
          '安装失败或取消管理员授权时，程序也会重新打开并提示。\n\n'
          '如出现 Windows 管理员授权提示，请选择允许。是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('开始更新'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await UpdateLauncher.launchAfterExit(path);
      if (!mounted) return;
      showTopSnackBar(context, '正在退出并自动更新，请稍候');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await DesktopService.instance.quitApp();
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, '启动更新程序失败：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('程序更新'),
        const SettingsHint(
          '选择官方发布的安装包（.exe / .msi）即可更新：程序会先退出，自动完成安装，'
          '并在安装成功后重新打开。安装失败或取消管理员授权时，程序会重新打开并提示，'
          '详情可查看 %TEMP%\\班级管理系统_更新日志.txt。'
          '记录与设置保存在文档目录，不受影响。',
        ),
        const SizedBox(height: 10),
        SettingsActionButton(label: '选择更新包', onPressed: _pickInstaller),
      ],
    );
  }
}
