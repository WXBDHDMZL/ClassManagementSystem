/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V2.34.2
 * 创建日期 (Created): 2026-10-17
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/update_launcher.dart';

void main() {
  test('程序内更新：exe 安装包在程序退出后静默运行', () {
    final script = UpdateLauncher.buildWaitScript(
      processId: 42,
      installerPath: r'C:\更新\班级管理系统_安装包_v2.34.2.exe',
      relaunchPath: r'C:\Program Files\班级管理系统\班级管理系统.exe',
    );

    expect(script, contains(r'$appPid = 42'));
    expect(script, contains('WaitForExit(60000)'));
    expect(
      script,
      contains("Start-Process -FilePath 'C:\\更新\\班级管理系统_安装包_v2.34.2.exe'"),
    );
    expect(script, contains("'/SILENT /NORESTART'"));
    expect(script, contains('-Wait -PassThru'));
    expect(script, isNot(contains('/VERYSILENT')));
    expect(
      script,
      contains(r"$relaunchPath = 'C:\Program Files\班级管理系统\班级管理系统.exe'"),
    );
    expect(script, contains(r'Start-Process -FilePath $relaunchPath'));
    expect(script, contains('已重新启动程序'));
    expect(script, contains('班级管理系统_更新日志.txt'));
    expect(script, contains(r'Remove-Item -LiteralPath $PSCommandPath'));
  });

  test('程序内更新失败：提示用户并重新打开原程序', () {
    final script = UpdateLauncher.buildWaitScript(
      processId: 42,
      installerPath: r'C:\更新\setup.exe',
      relaunchPath: r'C:\Program Files\班级管理系统\班级管理系统.exe',
    );

    expect(script, contains('function Restart-OriginalApp'));
    expect(script, contains('安装程序未成功完成（退出码 '));
    expect(script, contains('更新过程中出现错误'));
    expect(script, contains('System.Windows.Forms.MessageBox'));
    expect(script, contains('班级管理系统更新'));
    expect(script, contains('详情见日志'));
    expect(script, contains('更新失败后已重新启动程序'));
    // 安装成功或 MSI 要求重启（3010）都按成功处理。
    expect(script, contains(r'$installer.ExitCode -eq 3010'));
  });

  test('程序内更新失败且没有原程序路径：只提示，不重启', () {
    final script = UpdateLauncher.buildWaitScript(
      processId: 3,
      installerPath: r'C:\更新\setup.exe',
    );

    expect(script, contains(r"$relaunchPath = ''"));
    expect(script, contains('未找到原程序，请手动打开'));
    expect(script, contains('function Restart-OriginalApp'));
  });

  test('程序内更新：msi 安装包通过 msiexec 静默安装', () {
    final script = UpdateLauncher.buildWaitScript(
      processId: 7,
      installerPath: r'C:\更新\班级管理系统.msi',
    );

    expect(script, contains("Start-Process -FilePath 'msiexec.exe'"));
    expect(
      script,
      contains('-ArgumentList \'/i "C:\\更新\\班级管理系统.msi" /qn /norestart\''),
    );
    expect(script, contains('-Wait -PassThru'));
    expect(script, isNot(contains('/SILENT')));
  });

  test('安装包路径中的单引号按 PowerShell 规则转义', () {
    final script = UpdateLauncher.buildWaitScript(
      processId: 1,
      installerPath: r"C:\a'b\setup.exe",
    );

    expect(script, contains(r"C:\a''b\setup.exe"));
  });

  test('助手脚本写入临时 ps1 且带 UTF-8 BOM', () async {
    final file = await UpdateLauncher.writeHelperScript(
      processId: 99,
      installerPath: r'C:\更新\setup.exe',
      relaunchPath: r'C:\班级管理系统\班级管理系统.exe',
    );
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });

    expect(file.path.toLowerCase().endsWith('.ps1'), isTrue);
    final bytes = await file.readAsBytes();
    expect(bytes.take(3).toList(), [0xEF, 0xBB, 0xBF]);
    final content = await file.readAsString();
    expect(content, contains(r'$appPid = 99'));
    expect(content, contains(r'C:\更新\setup.exe'));
    expect(content, contains("'/SILENT /NORESTART'"));
    expect(content, contains('-Wait -PassThru'));
    expect(content, contains(r'C:\班级管理系统\班级管理系统.exe'));
    expect(content, contains('已重新启动程序'));
    expect(content, contains(r'Remove-Item -LiteralPath $PSCommandPath'));
  });
}
