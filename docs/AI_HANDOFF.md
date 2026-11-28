# AI_HANDOFF
> 跨 AI 窗口的唯一共享记忆。每次会话结束必须更新（≤40 行）。开始会话先读本文件 + `AI_RULES.md` + `git status`。
更新时间：2026-11-28
当前状态：V5.0.1 已发布（2026-11-22），版本 5.0.1+186；2026-11-28 起在 `main` 上合入 P0 与 P1–P3 核心项修复（未发新版本，剩余项见文末）。
支持边界：V5 只支持 V4.14.1 写出的 LRX3 数据；V4.13 及更早的 LRX2、旧目录、旧日志、旧备份、旧密码、旧包全部不支持。旧格式只做“识别并明确拒绝”，不迁移、不隔离、不生成空库。
验证基线：全量 779 通过（2026-11-28 `flutter test`）；`flutter analyze` 通过；`check_rules` 69/69、`ui_copy_check`、`check_version`、`stamp_version` 通过。
本次改动（2026-11-28，P0 与 P1–P3 核心项）：
1. `lib/utils/today_boundary.dart` 统一归属日计算；`DayRolloverTracker` 按归属日刷新，修复过零点今日面板/角标/悬浮球不刷新；记录/考勤对话框提交时校准未手改的自动默认值。
2. 安装器覆盖升级删除旧 `migrate_lrx2.exe` 与快捷方式；`performExitBackup` 把退出备份失败写入错误日志；旧 LRX2 锁定文件改名 `.lrx2_legacy` 并提示。
3. 加固 UI 文案门禁（文件级豁免）、覆盖率阈值、release_check 跳过项报告、VC_redist 签名校验、日志导出坏行提示、发布说明过滤、考勤日期/组标题、日期区间与悬浮球/关闭确认等低风险细节。
发布结果：`v5.0.1` tag 与 Release 指向 `b73c49b`；资产 `ClassManagementSystem_Setup_v5.0.1.exe`（29,851,436 B，sha256 `3c93294d…`）+ `.sha256` + `.sig` + `UpdateNotes_V1.0.0-V5.0.1.zip`。
工具：`migrate_lrx2.exe` 与源码仅保留在 `D:/Projects/Programs/_audit_backups/migrate_tool/`，不随仓库、安装包或 Release 分发。
已知坑：
- 旧 LRX2 用户必须先留在 4.x 或导出数据重建；V5 不提供迁移入口。
- 数据密钥由 DPAPI 绑定当前 Windows 用户/机器；自动备份仅同机可恢复，手动 `.enc`+`.pkey` 才可换机。
- Windows Release 需 vcvars64；构建前结束旧程序。`build.bat` 调用 `flutter.bat` 必须带 `call`。
- 不要裸跑 `dart format`；`lib/providers/app_data/*.dart` 是 part，不能自行 import。
- `.gitattributes`：bat CRLF，其余 LF；提交前查 `git diff --check`。
- 发布前确认 `release_report_v5.0.1.md` 通过、tag/HEAD/Release target 一致、`.sig` 可验；安装包内无 `migrate_lrx2.exe`/旧钥。
- GitHub 旧 commit 仍可能按 SHA 访问，需 GitHub Support 清理。
- 尚未处理：关机 `WM_QUERYENDSESSION` 同步写盘、悬浮球 5 档不透明度/逐帧重绘、check_rules 缺失的架构/提交规则等；均已在 P1–P3 清单登记。默认密码固定哈希仍内置，但 Release 首次启动会提示修改。
