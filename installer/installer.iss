[Setup]
AppId={{A5B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName=班级管理系统
AppVersion=5.0.1
AppVerName=班级管理系统 V5.0.1
AppPublisher=WXBDHDMZL
AppCopyright=© 2026 WXBDHDMZL｜AGPL-3.0-only
; 审计 P2-59：显式声明 64 位安装（{autopf} 解析为 Program Files 而不是 (x86)）
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
VersionInfoVersion=5.0.1.0
VersionInfoProductVersion=5.0.1
VersionInfoProductName=班级管理系统
VersionInfoDescription=班级管理系统 安装程序
DefaultDirName={autopf}\班级管理系统
DefaultGroupName=班级管理系统
AllowNoIcons=yes
OutputDir=output
OutputBaseFilename=班级管理系统_安装包_v5.0.1
Compression=lzma/ultra64
SolidCompression=yes
WizardStyle=modern
; 审计 S-P1-4：运行中的程序会拦截 WM_CLOSE（托盘常驻），安装/卸载前由
; Inno 的 Restart Manager 和互斥量判断处理，避免文件占用后留下半套文件。
AppMutex=ClassManagementSystem.Local.SingleInstance
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\班级管理系统.exe
SetupIconFile=..\assets\icons\tray.ico
DisableProgramGroupPage=yes
LicenseFile=LICENSE.txt

[Languages]
Name: "chinese"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式(&D)"; GroupDescription: "附加图标"

[Files]
; 审计 P2-60：Excludes 排除历史依赖残留的 flutter_acrylic_plugin.dll（若存在）
Source: "..\build\windows\x64\runner\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "CMakeFiles\*,CMakeFiles,cmake_install.cmake,*.pdb,*占用中*,flutter_acrylic_plugin.dll"
; 许可协议也复制一份到安装目录，装完仍可随时查看
Source: "LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
; P0-2：VC++ 运行库必须随包分发。缺少该文件时让 ISCC 直接编译失败，
; 绝不能生成“安装成功但双击无反应”的安装包（干净 Windows 没有 MSVCP140.dll）。
Source: "VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: ignoreversion

[InstallDelete]
; 5.0.1 起不再随包分发旧数据迁移工具；覆盖升级时删除 5.0.0 及更早版本留下的副本。
Type: files; Name: "{app}\migrate_lrx2.exe"
; 旧版本开始菜单里的迁移入口也一并清理，避免指向已删除的工具。
Type: files; Name: "{group}\转换历史加密数据.lnk"

[Icons]
Name: "{group}\班级管理系统"; Filename: "{app}\班级管理系统.exe"
Name: "{group}\卸载班级管理系统"; Filename: "{uninstallexe}"
Name: "{autodesktop}\班级管理系统"; Filename: "{app}\班级管理系统.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; Flags: runhidden; StatusMsg: "正在安装 VC++ 运行库..."
; 手动双击安装：走正常向导，装完由用户勾选是否启动。
; 程序内更新由更新助手在安装成功后主动重启程序，不依赖这里的静默启动项。
Filename: "{app}\班级管理系统.exe"; Description: "启动班级管理系统"; Flags: nowait postinstall skipifsilent runasoriginaluser

[Code]
procedure InitializeWizard;
begin
  // 静默安装不创建/不显示向导页，避免访问 WizardForm。
  if not WizardSilent then
  begin
    WizardForm.LicenseAcceptedRadio.Checked := False;
    WizardForm.LicenseNotAcceptedRadio.Checked := True;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  // 审计 F1-4：只删除程序自写的 Run 值，不在安装时创建空值。
  if CurUninstallStep = usPostUninstall then
  begin
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run',
      'ClassManagementSystem');
    // 审计 A-26：卸载只移除程序文件，班级数据与备份仍留在文档目录。必须
    // 明确告知，否则用户会以为数据随程序一起被删除；静默卸载不弹窗。
    if not UninstallSilent then
      MsgBox('程序文件已卸载，你的班级数据与备份仍保留在：' + #13#10 +
             ExpandConstant('{userdocs}\班级管理系统') + #13#10 + #13#10 +
             '如需彻底清理，请手动删除该文件夹（删除后无法恢复）。',
             mbInformation, MB_OK);
  end;
end;
