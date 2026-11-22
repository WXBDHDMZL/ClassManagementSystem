# AI_HANDOFF
> 跨 AI 窗口的唯一共享记忆。每次会话结束必须更新（≤40 行）。开始会话先读本文件 + `AI_RULES.md` + `git status`。
更新时间：2026-11-22
当前状态：V5.0.0 已发布（2026-11-22），GitHub 历史已重建为单一根提交。
支持边界：V5.0.0 只支持 V4.14.1 写出的 LRX3 数据；V4.13 及更早的 LRX2、旧目录、旧日志、旧备份、旧密码、旧包全部不支持。旧格式只做“识别并明确拒绝”，不迁移、不隔离、不生成空库。
验证基线：全量 769 通过（`build/audit_v5/r4_full.log`）；`flutter analyze` 通过；`check_rules` 69/72、`ui_copy_check`、`check_version`、`stamp_version` 通过。
本轮完成：
1. R1：删除旧目录迁移、LRX2 解码、旧日志合并、旧固定名备份特殊处理；统一 `unsupportedFormat`。
2. R2：数据包升级 V2 全字段必填；删除 `periodLabels`；缺日期列直接拒绝；旧固定名备份不再列入恢复列表。
3. R3：版本 5.0.0+185；安装器删除旧迁移工具/快捷方式/旧残留清理；README/更新说明改为 V5 边界。
4. R4：`release_check.py` 删除 LRX2 迁移分支；安装验收通过（4.14.1→5.0.0 覆盖升级、启动、解码、卸载）。
发布结果：`v5.0.0` tag 与 Release 指向 `0566c34`；资产 `ClassManagementSystem_Setup_v5.0.0.exe`（sha256 `12466b2b…`）+ `.sha256` + `.sig` + `UpdateNotes_V1.0.0-V5.0.0.zip`。
工具：`migrate_lrx2.exe` 与源码仅保留在 `D:/Projects/Programs/_audit_backups/migrate_tool/`，不随仓库、安装包或 Release 分发。
已知坑：
- 旧 LRX2 用户必须先留在 4.x 或导出数据重建；V5 不提供迁移入口。
- 数据密钥由 DPAPI 绑定当前 Windows 用户/机器；自动备份仅同机可恢复，手动 `.enc`+`.pkey` 才可换机。
- Windows Release 需 vcvars64；构建前结束旧程序。`build.bat` 调用 `flutter.bat` 必须带 `call`。
- 不要裸跑 `dart format`；`lib/providers/app_data/*.dart` 是 part，不能自行 import。
- `.gitattributes`：bat CRLF，其余 LF；提交前查 `git diff --check`。
- 发布前确认 `release_report_v5.0.0.md` 通过、tag/HEAD/Release target 一致、`.sig` 可验；安装包内无 `migrate_lrx2.exe`/旧钥。
- GitHub 旧 commit 仍可能按 SHA 访问，需 GitHub Support 清理。
