[LangOptions]
LanguageName=Chinese (Simplified)
LanguageID=$0804
LanguageCodePage=936

[Messages]

SetupAppTitle=安装程序
SetupWindowTitle=%1 - 安装
UninstallAppTitle=卸载
UninstallAppFullTitle=%1 卸载

InformationTitle=信息
ConfirmTitle=确认
ErrorTitle=错误

SetupLdrStartupMessage=这将安装 %1。您是否希望继续？
LdrCannotCreateTemp=无法创建临时文件。安装程序已中止
LdrCannotExecTemp=无法执行临时目录中的文件。安装程序已中止
HelpTextNote=

LastErrorMessage=%1.%n%n错误 %2: %3
SetupFileMissing=安装目录中缺少文件 %1。请更正问题或获取程序的新副本。
SetupFileCorrupt=安装文件已损坏。请获取程序的新副本。
SetupFileCorruptOrWrongVer=安装文件已损坏或与本版本的安装程序不兼容。请更正问题或获取程序的新副本。
InvalidParameter=命令行中传递了无效参数:%n%n%1
SetupAlreadyRunning=安装程序已在运行。
WindowsVersionNotSupported=此程序不支持您计算机上运行的 Windows 版本。
WindowsServicePackRequired=此程序需要 %1 Service Pack %2 或更高版本。
NotOnThisPlatform=此程序将不在 %1 上运行。
OnlyOnThisPlatform=此程序必须在 %1 上运行。
OnlyOnTheseArchitectures=此程序只能安装在为以下处理器架构设计的 Windows 版本上:%n%n%1
WinVersionTooLowError=此程序需要 %1 版本 %2 或更高版本。
WinVersionTooHighError=此程序不能安装在 %1 版本 %2 或更高版本上。
AdminPrivilegesRequired=安装此程序时，您必须以管理员身份登录。
PowerUserPrivilegesRequired=安装此程序时，您必须以管理员身份或作为 Power Users 组成员登录。
SetupAppRunningError=安装程序检测到 %1 当前正在运行。%n%n请立即关闭其所有实例，然后点击"确定"继续，或点击"取消"退出。
UninstallAppRunningError=卸载程序检测到 %1 当前正在运行。%n%n请立即关闭其所有实例，然后点击"确定"继续，或点击"取消"退出。

PrivilegesRequiredOverrideTitle=选择安装程序安装模式
PrivilegesRequiredOverrideInstruction=选择安装模式
PrivilegesRequiredOverrideText1=%1 可以安装给所有用户（需要管理员权限），或只安装给您自己。
PrivilegesRequiredOverrideText2=%1 可以只安装给您自己，或安装给所有用户（需要管理员权限）。
PrivilegesRequiredOverrideAllUsers=安装给 &所有用户
PrivilegesRequiredOverrideAllUsersRecommended=安装给 &所有用户（推荐）
PrivilegesRequiredOverrideCurrentUser=只安装给 &我自己
PrivilegesRequiredOverrideCurrentUserRecommended=只安装给 &我自己（推荐）

ErrorCreatingDir=安装程序无法创建目录 "%1"
ErrorTooManyFilesInDir=无法在目录 "%1" 中创建文件，因为它包含太多文件

ExitSetupTitle=退出安装程序
ExitSetupMessage=安装程序尚未完成。如果您现在退出，程序将不会被安装。%n%n您可以在其他时间再次运行安装程序以完成安装。%n%n退出安装程序？
AboutSetupMenuItem=&关于安装程序...
AboutSetupTitle=关于安装程序
AboutSetupMessage=%1 版本 %2%n%3%n%n%1 主页:%n%4
AboutSetupNote=
TranslatorNote=

ButtonBack=< &上一步
ButtonNext=&下一步 >
ButtonInstall=&安装
ButtonOK=确定
ButtonCancel=取消
ButtonYes=&是
ButtonYesToAll=全部(&A)
ButtonNo=&否
ButtonNoToAll=全部(&O)
ButtonFinish=&完成
ButtonBrowse=&浏览...
ButtonWizardBrowse=B&rowse...
ButtonNewFolder=&新建文件夹

SelectLanguageTitle=选择安装程序语言
SelectLanguageLabel=选择安装过程中使用的语言。

ClickNext=点击"下一步"继续，或点击"取消"退出安装程序。
BeveledLabel=
BrowseDialogTitle=浏览文件夹
BrowseDialogLabel=在下方列表中选择一个文件夹，然后点击"确定"。
NewFolderName=新建文件夹

WelcomeLabel1=欢迎使用 [name] 安装向导
WelcomeLabel2=这将在您的计算机上安装 [name/ver]。%n%n建议在继续之前关闭所有其他应用程序。

WizardPassword=密码
PasswordLabel1=此安装受密码保护。
PasswordLabel3=请提供密码，然后点击"下一步"继续。密码区分大小写。
PasswordEditLabel=&密码:
IncorrectPassword=您输入的密码不正确。请重试。

WizardLicense=开源许可协议
LicenseLabel=请在继续前阅读以下重要信息。
LicenseLabel3=请阅读以下开源许可协议。继续安装前请确认你已了解该许可证。
LicenseAccepted=我 &已了解上述许可证
LicenseNotAccepted=我 &不同意上述许可证

WizardInfoBefore=信息
InfoBeforeLabel=请在继续前阅读以下重要信息。
InfoBeforeClickLabel=准备好继续安装程序时，请点击"下一步"。
WizardInfoAfter=信息
InfoAfterLabel=请在继续前阅读以下重要信息。
InfoAfterClickLabel=准备好继续安装程序时，请点击"下一步"。

WizardUserInfo=用户信息
UserInfoDesc=请输入您的信息。
UserInfoName=&用户名:
UserInfoOrg=&组织:
UserInfoSerial=&序列号:
UserInfoNameRequired=您必须输入一个名称。

WizardSelectDir=选择目标位置
SelectDirDesc=[name] 应该安装在哪里？
SelectDirLabel3=安装程序将把 [name] 安装到以下文件夹。
SelectDirBrowseLabel=要继续，请点击"下一步"。如果您想选择不同的文件夹，请点击"浏览"。
DiskSpaceGBLabel=至少需要 [gb] GB 的可用磁盘空间。
DiskSpaceMBLabel=至少需要 [mb] MB 的可用磁盘空间。
CannotInstallToNetworkDrive=安装程序无法安装到网络驱动器。
CannotInstallToUNCPath=安装程序无法安装到 UNC 路径。
InvalidPath=您必须输入带有驱动器号的完整路径；例如:%n%nC:\APP%n%n或格式如下的 UNC 路径:%n%n\\server\share
InvalidDrive=您选择的驱动器或 UNC 共享不存在或无法访问。请选择其他驱动器。
DiskSpaceWarningTitle=磁盘空间不足
DiskSpaceWarning=安装程序至少需要 %1 KB 的可用空间来安装，但所选驱动器只有 %2 KB 可用。%n%n您仍然想继续吗？
DirNameTooLong=文件夹名称或路径太长。
InvalidDirName=文件夹名称无效。
BadDirName32=文件夹名称不能包含以下任何字符:%n%n%1
DirExistsTitle=文件夹已存在
DirExists=文件夹:%n%n%1%n%n已存在。您仍要安装到此文件夹吗？
DirDoesntExistTitle=文件夹不存在
DirDoesntExist=文件夹:%n%n%1%n%n不存在。您希望创建此文件夹吗？

WizardSelectComponents=选择组件
SelectComponentsDesc=应该安装哪些组件？
SelectComponentsLabel2=选择您要安装的组件；清除您不想安装的组件。准备好继续时点击"下一步"。
FullInstallation=完整安装
CompactInstallation=精简安装
CustomInstallation=自定义安装
NoUninstallWarningTitle=组件已存在
NoUninstallWarning=安装程序检测到以下组件已安装在您的计算机上:%n%n%1%n%n取消选择这些组件不会卸载它们。%n%n您仍然想继续吗？
ComponentSize1=%1 KB
ComponentSize2=%1 MB
ComponentsDiskSpaceGBLabel=当前选择至少需要 [gb] GB 的磁盘空间。
ComponentsDiskSpaceMBLabel=当前选择至少需要 [mb] MB 的磁盘空间。

WizardSelectTasks=选择附加任务
SelectTasksDesc=应该执行哪些附加任务？
SelectTasksLabel2=选择您希望安装程序在安装 [name] 时执行的附加任务，然后点击"下一步"。

WizardSelectProgramGroup=选择开始菜单文件夹
SelectStartMenuFolderDesc=安装程序应该将程序快捷方式放在哪里？
SelectStartMenuFolderLabel3=安装程序将在以下开始菜单文件夹中创建程序快捷方式。
SelectStartMenuFolderBrowseLabel=要继续，请点击"下一步"。如果您想选择不同的文件夹，请点击"浏览"。
MustEnterGroupName=您必须输入一个文件夹名称。
GroupNameTooLong=文件夹名称或路径太长。
InvalidGroupName=文件夹名称无效。
BadGroupName=文件夹名称不能包含以下任何字符:%n%n%1
NoProgramGroupCheck2=&不创建开始菜单文件夹

WizardReady=准备安装
ReadyLabel1=安装程序现已准备好在您的计算机上开始安装 [name]。
ReadyLabel2a=点击"安装"继续安装，或点击"上一步"查看或更改任何设置。
ReadyLabel2b=点击"安装"继续安装。
ReadyMemoUserInfo=用户信息:
ReadyMemoDir=目标位置:
ReadyMemoType=安装类型:
ReadyMemoComponents=所选组件:
ReadyMemoGroup=开始菜单文件夹:
ReadyMemoTasks=附加任务:

DownloadingLabel2=正在下载文件...
ButtonStopDownload=&停止下载
StopDownload=您确定要停止下载吗？
ErrorDownloadAborted=下载已中止
ErrorDownloadFailed=下载失败: %1 %2
ErrorDownloadSizeFailed=获取大小失败: %1 %2
ErrorProgress=无效进度: %1 / %2
ErrorFileSize=无效文件大小: 预期 %1，找到 %2

ExtractingLabel=正在解压文件...
ButtonStopExtraction=&停止解压
StopExtraction=您确定要停止解压吗？
ErrorExtractionAborted=解压已中止
ErrorExtractionFailed=解压失败: %1

ArchiveIncorrectPassword=密码不正确
ArchiveIsCorrupted=存档已损坏
ArchiveUnsupportedFormat=存档格式不受支持

WizardPreparing=准备安装
PreparingDesc=安装程序正在准备在您的计算机上安装 [name]。
PreviousInstallNotCompleted=先前程序的安装/删除未完成。您需要重新启动计算机以完成该安装。%n%n重新启动计算机后，再次运行安装程序以完成 [name] 的安装。
CannotContinue=安装程序无法继续。请点击"取消"退出。
ApplicationsFound=以下应用程序正在使用安装程序需要更新的文件。建议您允许安装程序自动关闭这些应用程序。
ApplicationsFound2=以下应用程序正在使用安装程序需要更新的文件。建议您允许安装程序自动关闭这些应用程序。安装完成后，安装程序将尝试重新启动这些应用程序。
CloseApplications=&自动关闭应用程序
DontCloseApplications=&不关闭应用程序
ErrorCloseApplications=安装程序无法自动关闭所有应用程序。建议在继续之前关闭所有使用安装程序需要更新的文件的应用程序。
PrepareToInstallNeedsRestart=安装程序必须重新启动您的计算机。重新启动计算机后，再次运行安装程序以完成 [name] 的安装。%n%n您现在想重新启动吗？

WizardInstalling=正在安装...
InstallingLabel=请等待安装程序在您的计算机上安装 [name]。

FinishedHeadingLabel=完成 [name] 安装向导
FinishedLabelNoIcons=安装程序已完成在您的计算机上安装 [name]。
FinishedLabel=安装程序已完成在您的计算机上安装 [name]。可以通过选择已安装的快捷方式启动应用程序。
ClickFinish=点击"完成"退出安装程序。
FinishedRestartLabel=要完成 [name] 的安装，安装程序必须重新启动您的计算机。您现在想重新启动吗？
FinishedRestartMessage=要完成 [name] 的安装，安装程序必须重新启动您的计算机。%n%n您现在想重新启动吗？
ShowReadmeCheck=是，我想查看 README 文件
YesRadio=&是，立即重新启动计算机
NoRadio=&否，我稍后会重新启动计算机
RunEntryExec=运行 %1
RunEntryShellExec=查看 %1

ChangeDiskTitle=安装程序需要下一张磁盘
SelectDiskLabel2=请插入磁盘 %1 并点击"确定"。%n%n如果此磁盘上的文件可以在以下显示的文件夹以外的其他文件夹中找到，请输入正确路径或点击"浏览"。
PathLabel=&路径:
FileNotInDir2=文件 "%1" 无法在 "%2" 中找到。请插入正确的磁盘或选择其他文件夹。
SelectDirectoryLabel=请指定下一张磁盘的位置。

SetupAborted=安装程序未完成。%n%n请更正问题并再次运行安装程序。
AbortRetryIgnoreSelectAction=选择操作
AbortRetryIgnoreRetry=&重试
AbortRetryIgnoreIgnore=&忽略错误并继续
AbortRetryIgnoreCancel=取消安装
RetryCancelSelectAction=选择操作
RetryCancelRetry=&重试
RetryCancelCancel=取消

StatusClosingApplications=正在关闭应用程序...
StatusCreateDirs=正在创建目录...
StatusExtractFiles=正在解压文件...
StatusDownloadFiles=正在下载文件...
StatusCreateIcons=正在创建快捷方式...
StatusCreateIniEntries=正在创建 INI 条目...
StatusCreateRegistryEntries=正在创建注册表条目...
StatusRegisterFiles=正在注册文件...
StatusSavingUninstall=正在保存卸载信息...
StatusRunProgram=正在完成安装...
StatusRestartingApplications=正在重新启动应用程序...
StatusRollback=正在回滚更改...

ErrorInternal2=内部错误: %1
ErrorFunctionFailedNoCode=%1 失败
ErrorFunctionFailed=%1 失败；代码 %2
ErrorFunctionFailedWithMessage=%1 失败；代码 %2.%n%3
ErrorExecutingProgram=无法执行文件:%n%1

ErrorRegOpenKey=打开注册表项时出错:%n%1\%2
ErrorRegCreateKey=创建注册表项时出错:%n%1\%2
ErrorRegWriteKey=写入注册表项时出错:%n%1\%2

ErrorIniEntry=在文件 "%1" 中创建 INI 条目时出错。

FileAbortRetryIgnoreSkipNotRecommended=&跳过此文件（不推荐）
FileAbortRetryIgnoreIgnoreNotRecommended=&忽略错误并继续（不推荐）
SourceIsCorrupted=源文件已损坏
SourceDoesntExist=源文件 "%1" 不存在
SourceVerificationFailed=源文件验证失败: %1
VerificationSignatureDoesntExist=签名文件 "%1" 不存在
VerificationSignatureInvalid=签名文件 "%1" 无效
VerificationKeyNotFound=签名文件 "%1" 使用了未知密钥
VerificationFileNameIncorrect=文件名不正确
VerificationFileTagIncorrect=文件标签不正确
VerificationFileSizeIncorrect=文件大小不正确
VerificationFileHashIncorrect=文件哈希不正确
ExistingFileReadOnly2=无法替换现有文件，因为它被标记为只读。
ExistingFileReadOnlyRetry=&移除只读属性并重试
ExistingFileReadOnlyKeepExisting=&保留现有文件
ErrorReadingExistingDest=读取现有文件时发生错误:
FileExistsSelectAction=选择操作
FileExists2=文件已存在。
FileExistsOverwriteExisting=&覆盖现有文件
FileExistsKeepExisting=&保留现有文件
FileExistsOverwriteOrKeepAll=&对后续冲突执行此操作
ExistingFileNewerSelectAction=选择操作
ExistingFileNewer2=现有文件比安装程序尝试安装的文件更新。
ExistingFileNewerOverwriteExisting=&覆盖现有文件
ExistingFileNewerKeepExisting=&保留现有文件（推荐）
ExistingFileNewerOverwriteOrKeepAll=&对后续冲突执行此操作
ErrorChangingAttr=更改现有文件属性时发生错误:
ErrorCreatingTemp=在目标目录中创建文件时发生错误:
ErrorReadingSource=读取源文件时发生错误:
ErrorCopying=复制文件时发生错误:
ErrorDownloading=下载文件时发生错误:
ErrorExtracting=解压存档时发生错误:
ErrorReplacingExistingFile=替换现有文件时发生错误:
ErrorRestartReplace=RestartReplace 失败:
ErrorRenamingTemp=在目标目录中重命名文件时发生错误:
ErrorRegisterServer=无法注册 DLL/OCX: %1
ErrorRegSvr32Failed=RegSvr32 失败，退出代码 %1
ErrorRegisterTypeLib=无法注册类型库: %1

UninstallDisplayNameMark=%1 (%2)
UninstallDisplayNameMarks=%1 (%2, %3)
UninstallDisplayNameMark32Bit=32位
UninstallDisplayNameMark64Bit=64位
UninstallDisplayNameMarkAllUsers=所有用户
UninstallDisplayNameMarkCurrentUser=当前用户

ErrorOpeningReadme=打开 README 文件时发生错误。
ErrorRestartingComputer=安装程序无法重新启动计算机。请手动执行此操作。

UninstallNotFound=文件 "%1" 不存在。无法卸载。
UninstallOpenError=无法打开文件 "%1"。无法卸载
UninstallUnsupportedVer=卸载日志文件 "%1" 的格式不被此版本的卸载程序识别。无法卸载
UninstallUnknownEntry=在卸载日志中遇到未知条目 (%1)
ConfirmUninstall=您确定要完全移除 %1 及其所有组件吗？
UninstallOnlyOnWin64=此安装只能在 64 位 Windows 上卸载。
OnlyAdminCanUninstall=此安装只能由具有管理员权限的用户卸载。
UninstallStatusLabel=请等待 %1 从您的计算机上移除。
UninstalledAll=%1 已成功从您的计算机上移除。
UninstalledMost=%1 卸载完成。%n%n某些元素无法移除。这些可以手动移除。
UninstalledAndNeedsRestart=要完成 %1 的卸载，必须重新启动您的计算机。%n%n您现在想重新启动吗？
UninstallDataCorrupted="%1" 文件已损坏。无法卸载

ConfirmDeleteSharedFileTitle=删除共享文件？
ConfirmDeleteSharedFile2=系统表明以下共享文件不再被任何程序使用。您希望卸载程序删除此共享文件吗？%n%n如果任何程序仍在使用此文件且将其删除，这些程序可能无法正常运行。如果不确定，请选择"否"。将文件留在系统上不会造成任何损害。
SharedFileNameLabel=文件名:
SharedFileLocationLabel=位置:
WizardUninstalling=卸载状态
StatusUninstalling=正在卸载 %1...

ShutdownBlockReasonInstallingApp=正在安装 %1。
ShutdownBlockReasonUninstallingApp=正在卸载 %1。

[CustomMessages]

NameAndVersion=%1 版本 %2
AdditionalIcons=附加图标:
CreateDesktopIcon=创建桌面快捷方式(&D)
CreateQuickLaunchIcon=创建快速启动快捷方式(&Q)
ProgramOnTheWeb=%1 在网上
UninstallProgram=卸载 %1
LaunchProgram=启动 %1
AssocFileExtension=&将 %1 与 %2 文件扩展名关联
AssocingFileExtension=正在将 %1 与 %2 文件扩展名关联...
AutoStartProgramGroupDescription=启动:
AutoStartProgram=自动启动 %1
AddonHostProgramNotFound=无法在您选择的文件夹中找到 %1。%n%n您仍然想继续吗？