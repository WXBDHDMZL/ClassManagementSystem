[Setup]
AppId={{A5B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName=班级管理系统
AppVersion=4.9.7
AppVerName=班级管理系统 V4.9.7
AppPublisher=WXBDHDMZL
AppCopyright=© 2026 WXBDHDMZL｜AGPL-3.0-only
; 审计 P2-59：显式声明 64 位安装（{autopf} 解析为 Program Files 而不是 (x86)）
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
VersionInfoVersion=4.9.7.0
VersionInfoProductVersion=4.9.7
VersionInfoProductName=班级管理系统
VersionInfoDescription=班级管理系统 安装程序
DefaultDirName={autopf}\班级管理系统
DefaultGroupName=班级管理系统
AllowNoIcons=yes
OutputDir=output
OutputBaseFilename=班级管理系统_安装包_v4.9.7
Compression=lzma/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\班级管理系统.exe
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
; P1-8：把 VC_redist.x64.exe 放在本 iss 同目录即可随包分发（没有该文件时跳过）
Source: "VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\班级管理系统"; Filename: "{app}\班级管理系统.exe"
Name: "{group}\卸载班级管理系统"; Filename: "{uninstallexe}"
Name: "{autodesktop}\班级管理系统"; Filename: "{app}\班级管理系统.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; Flags: skipifdoesntexist runhidden; StatusMsg: "正在安装 VC++ 运行库..."
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