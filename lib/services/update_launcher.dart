/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.10.0
 * 创建日期 (Created): 2026-10-17
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 程序内更新的启动器：先等当前程序退出，再静默运行安装包；
/// 安装成功后再主动重新打开原程序。
///
/// 安装失败、取消管理员授权或助手异常时，会记录日志、尝试重新打开原程序，
/// 并弹出提示框告知失败原因，避免程序关闭后没有任何后续。
/// 手动双击安装包仍走安装向导；只有 [launchAfterExit] 会附加静默参数，
/// 两条路径互不影响。
class UpdateLauncher {
  UpdateLauncher._();

  /// 等待 [processId] 退出后启动安装包、并在成功后重新打开 [relaunchPath]。
  @visibleForTesting
  static String buildWaitScript({
    required int processId,
    required String installerPath,
    String? relaunchPath,
  }) {
    final escapedPath = _escapePowerShellLiteral(installerPath);
    final escapedRelaunch = (relaunchPath == null || relaunchPath.isEmpty)
        ? null
        : _escapePowerShellLiteral(relaunchPath);
    final startCommand = _isMsi(installerPath)
        ? "Start-Process -FilePath 'msiexec.exe' "
              "-ArgumentList '/i \"$escapedPath\" /qn /norestart' "
              '-Wait -PassThru -ErrorAction Stop'
        : "Start-Process -FilePath '$escapedPath' "
              "-ArgumentList '/SILENT /NORESTART' -Wait -PassThru -ErrorAction Stop";
    final relaunchLiteral = escapedRelaunch == null
        ? "''"
        : "'$escapedRelaunch'";
    return '''
\$appPid = $processId
\$log = Join-Path \$env:TEMP '班级管理系统_更新日志.txt'
\$relaunchPath = $relaunchLiteral
function Write-UpdateLog([string]\$message) {
  \$line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + \$message
  Add-Content -LiteralPath \$log -Value \$line -Encoding UTF8 -ErrorAction SilentlyContinue
}
function Show-UpdateMessage([string]\$message) {
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    [System.Windows.Forms.MessageBox]::Show(
      \$message,
      '班级管理系统更新',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
  } catch {
    Write-UpdateLog ('无法显示提示窗口: ' + \$_.Exception.Message)
  }
}
function Restart-OriginalApp([string]\$failure) {
  Write-UpdateLog \$failure
  \$tip = \$failure + [Environment]::NewLine + [Environment]::NewLine + '详情见日志：' + \$log
  if (\$relaunchPath -ne '' -and (Test-Path -LiteralPath \$relaunchPath)) {
    try {
      Start-Sleep -Milliseconds 800
      Start-Process -FilePath \$relaunchPath -ErrorAction Stop
      \$tip += [Environment]::NewLine + '程序已重新打开。'
      Write-UpdateLog '更新失败后已重新启动程序'
    } catch {
      \$tip += [Environment]::NewLine + '原程序自动打开失败，请手动打开。'
      Write-UpdateLog ('更新失败后重启程序失败: ' + \$_.Exception.Message)
    }
  } else {
    \$tip += [Environment]::NewLine + '未找到原程序，请手动打开。'
  }
  Show-UpdateMessage \$tip
}
try {
  Write-UpdateLog '更新助手启动，等待程序退出（PID $processId）'
  \$app = Get-Process -Id \$appPid -ErrorAction SilentlyContinue
  if (\$app) { \$app.WaitForExit(60000) | Out-Null }
  if (Get-Process -Id \$appPid -ErrorAction SilentlyContinue) {
    \$message = '程序未在 60 秒内退出，已取消更新。'
    Write-UpdateLog \$message
    Show-UpdateMessage (\$message + [Environment]::NewLine + [Environment]::NewLine + '详情见日志：' + \$log)
    exit 1
  }
  Start-Sleep -Milliseconds 400
  Write-UpdateLog '程序已退出，启动安装程序'
  \$installer = $startCommand
  Write-UpdateLog ('安装程序退出码: ' + \$installer.ExitCode)
  if (\$installer.ExitCode -eq 0 -or \$installer.ExitCode -eq 3010) {
    if (\$relaunchPath -ne '' -and (Test-Path -LiteralPath \$relaunchPath)) {
      Start-Sleep -Milliseconds 800
      Start-Process -FilePath \$relaunchPath -ErrorAction Stop
      Write-UpdateLog '已重新启动程序'
    } else {
      \$message = '更新已安装，但找不到原程序，未能自动打开。'
      Write-UpdateLog \$message
      Show-UpdateMessage (\$message + [Environment]::NewLine + [Environment]::NewLine + '详情见日志：' + \$log)
    }
  } else {
    Restart-OriginalApp ('安装程序未成功完成（退出码 ' + \$installer.ExitCode + '），更新已取消或失败。')
  }
} catch {
  Restart-OriginalApp ('更新过程中出现错误：' + \$_.Exception.Message)
} finally {
  Remove-Item -LiteralPath \$PSCommandPath -Force -ErrorAction SilentlyContinue
}
''';
  }

  /// 把助手脚本写入临时 `.ps1`（UTF-8 BOM，兼容中文安装包路径）。
  ///
  /// 不用 `-EncodedCommand`：本机实测 `-WindowStyle Hidden` 与
  /// `-Command/-EncodedCommand` 组合会让 PowerShell 直接退出；`-File` 正常。
  @visibleForTesting
  static Future<File> writeHelperScript({
    required int processId,
    required String installerPath,
    String? relaunchPath,
  }) async {
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'cms_update_${processId}_${DateTime.now().microsecondsSinceEpoch}.ps1';
    final file = File(path);
    await file.writeAsString(
      '\uFEFF${buildWaitScript(processId: processId, installerPath: installerPath, relaunchPath: relaunchPath)}',
      flush: true,
    );
    return file;
  }

  /// 启动后台助手；安装成功后由助手重新打开原程序。
  static Future<void> launchAfterExit(
    String installerPath, {
    String? relaunchPath,
  }) async {
    final file = await writeHelperScript(
      processId: pid,
      installerPath: installerPath,
      relaunchPath: relaunchPath ?? Platform.resolvedExecutable,
    );
    // 本机实测 detached 模式启动的 PowerShell 不执行脚本；
    // normal 子进程在父进程退出后仍能继续运行，故这里用 normal 并排空输出。
    final process = await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      file.path,
    ], mode: ProcessStartMode.normal);
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
  }

  static bool _isMsi(String path) => path.toLowerCase().endsWith('.msi');

  /// PowerShell 单引号字符串里的单引号用两个单引号转义。
  static String _escapePowerShellLiteral(String value) =>
      value.replaceAll("'", "''");
}
