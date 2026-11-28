# AI_HANDOFF
> 跨 AI 窗口的唯一共享记忆。每次会话结束必须更新（≤40 行）。开始会话先读本文件 + `AI_RULES.md` + `git status`。
更新时间：2026-11-28（V5.0.2 已发布）
当前状态：**V5.0.2 已发布**（2026-11-28 23:18，版本 5.0.2+187，tag/Release target `62aef89`）。此前状态：V5.0.1 于 2026-11-22 发布；2026-11-28 在 `main` 上完成两批修复（上午 P0/P1–P3，下午全量审查 `AUDIT_REPORT_2026-11-28.md`），并为本版添加 README 界面预览截图（`docs/images/`，演示数据，姓名均为模拟）。
支持边界：V5 只支持 V4.14.1 写出的 LRX3 数据；V4.13 及更早的 LRX2、旧目录、旧日志、旧备份、旧密码、旧包全部不支持。旧格式只做“识别并明确拒绝”，不迁移、不隔离、不生成空库。
验证基线（2026-11-28 21:29 实测，`python tools/check.py --lane full --coverage` 退出码 0）：静态门禁全绿 → `flutter test` **929 通过 / 0 失败**（`test/audit_2026_11_28_fixes_test.dart` 31 例（含无障碍/通知契约 2 例、B-34 降级 2 例、B-35 拒绝空列 1 例）、`management_password_test.dart` 并发锁 1 例、`github_update_service_test.dart` 新增下载分支 6 例、`update_launcher_test.dart` 新增 MSI 转义 3 例；基线由 886 提升）；`flutter analyze --no-pub` 无问题；`check_rules` 全绿（裸 catch 68/68、文件头版本一致、services 不反向依赖 providers、UI-01 文案）；`coverage_check.py --enforce` 通过（总 76.78% 10990/14314，核心 89.37% 2329/2606，基线 76.3/87.0）；`python -m unittest discover -s tools` **32 用例 OK**（commit/full 车道已纳入，见下）（新增 `tools/test_native_guards.py`：悬浮球 DPI 消息 + 关机预算 < 原生 500ms）；Windows Release 构建成功（需先 `vcvars64.bat`，见 B-33）。
本次改动（2026-11-28 下午，全量审查闭环，详见 `docs/BACKLOG.md` B-33）：
1. P1 数据安全：`DataLoadResult.backupUnreadable` 阻断"主文件缺失+唯一备份不可读"（否则第二次保存会顶掉唯一 `.bak`）；删时段后编辑记录保留 `periodName` 快照；原因改名按 `periodKey` 精确匹配分组；`matchTimePeriodKey` 认「全天」；恢复校验失败不再用旧内存回写；CSV 改 RFC 4180 状态机；名单标题行不再当姓名。
2. P2：批量覆盖重复改单次落盘、导入覆盖清 `syncedFromRecord`、`_saveDataNow` 两阶段备份轮转、`_keyIdMismatch` 指纹缺失不再一律按损坏隔离（提交前收尾改为 B-34 方案 1，见第 5 条）、密钥文件 `create(exclusive:)`、合并单元格展开（`lib/services/xlsx_merge.dart`）、各项导入体积/行数上限、数据包考勤 null/空数组语义、恢复码与密码落盘失败回滚、更新下载空闲超时+取消、多资产 checksum 解析、托盘兜底、关机落盘预算 450ms。
3. P3：设置器统一返回 bool 并按真实结果提示、提交防重入、失焦保存、列表 key 去 index、通知监听器修复、日志尾读按字节拼接、ACL 保护项解除、悬浮球 DPI 重绘、`verify` 在 await 前同步登记尝试计数（并发也逐个计入锁定阈值）、UTF-16 裁剪改 runes 等。
4. 验收审计补充（`AUDIT_FIX_CLOSURE_2026-11-28.md`）：修掉两处衍生问题 —— 密钥文件 `create(exclusive:)` 留下的 0 字节占位在"无数据文件"时自愈重建（有数据文件仍抛 `DataKeyUnavailableException`，绝不用新钥覆盖旧数据）；删除无用测试钩子 `debugShutdownSaveBudget`/`debugShutdownLogBudget`，改私有 const（合计 450ms 不变）。
5. 提交前收尾（2026-11-28 21:00–21:30，`AUDIT_FIX_CLOSURE_2026-11-28.md` 第十节）：B-34 落地方案 1——主文件为合法 LRX3 密文却解不开时先试 `.bak`（当前密钥）自动恢复并记日志，`.bak` 也不可用才隔离 `*.corrupt_*` 并返回 `keyUnavailable`（写阻断条件已补该 flag；非密文内容仍按 `resetToEmpty`，`storage_key_mismatch_test` 契约不变；有指纹且不匹配仍拦截不降级）；B-35 `setExportOptions([])` 改为返回 false 且不改状态（UI 按返回值提示）；`tools/check.py` 的 commit/full 车道补上 `run_tool_tests()`（此前只有 fast 车道跑 Python 自测，原生守卫等于没门禁）；`StorageService.debugLoadOverride` 读取处加 `kReleaseMode` 短路。回归 31 例、全量 929 通过。
发布结果：`v5.0.2` tag 与 Release 指向 `62aef89`；资产 `ClassManagementSystem_Setup_v5.0.2.exe`（29,875,866 B，sha256 `f0ad6f65…`）+ `.sha256` + `.sig` + `UpdateNotes_V1.0.0-V5.0.2.zip`（286,461 B）。发布前 `python tools/check.py --lane release --data-source "D:\tmp\demo_data\班级管理系统\class_management_data.enc" --signing-key "D:\ClassManagementSystem-signing\ed25519_private.b64"` 通过（929 测试 / 报告「通过」/ 签名有效）。**本版轮换更新签名密钥**（D-109）：旧私钥已丢失，新公钥 `oDEfgqSgLGSSij55Y5pbenzKhsQeFfO7SczGQxGijQA=`，私钥离线存于 `D:\ClassManagementSystem-signing\ed25519_private.b64`（含说明 txt，绝不入库）；V5.0.0/V5.0.1 客户端只认旧公钥，无法自动更新到本版，需手动覆盖安装一次。
v5.0.1 历史：tag/Release 指向 `b73c49b`，`ClassManagementSystem_Setup_v5.0.1.exe` 29,851,436 B，sha256 `3c93294d…`。
工具：`migrate_lrx2.exe` 与源码仅保留在 `D:/Projects/Programs/_audit_backups/migrate_tool/`，不随仓库、安装包或 Release 分发。
已知坑：
- 旧 LRX2 用户必须先留在 4.x 或导出数据重建；V5 不提供迁移入口。
- 数据密钥由 DPAPI 绑定当前 Windows 用户/机器；自动备份仅同机可恢复，手动 `.enc`+`.pkey` 才可换机。
- Windows Release 需 vcvars64；构建前结束旧程序。`build.bat` 调用 `flutter.bat` 必须带 `call`。
- 不要裸跑 `dart format`；`lib/providers/app_data/*.dart` 是 part，不能自行 import。
- `.gitattributes`：bat CRLF，其余 LF；提交前查 `git diff --check`。
- 发布前确认 `release_report_v5.0.2.md` 通过、tag/HEAD/Release target 一致、`.sig` 可验；安装包内无 `migrate_lrx2.exe`/旧钥。
- 签名私钥只此一份（`D:\ClassManagementSystem-signing\ed25519_private.b64`），丢失即无法再发自动更新；`git ls-remote`/`push` 必须加 `-c credential.helper=wincred`，否则 git 会生成名为 `CON` 的杂物文件让工作树变脏。
- GitHub 旧 commit 仍可能按 SHA 访问，需 GitHub Support 清理。
- 尚未处理：check_rules 的提交/版本等其余规则、悬浮球逐帧重绘等性能细节、`update_launcher.dart` 的 MSI 参数 `\"` 需真机验证（静态分析无法确认 msiexec 是否接受）、`import_limits` 依赖 zip 中央目录声明值（伪造 size 属理论边界）。关机 `WM_QUERYENDSESSION` 已在本轮处理（原生等 500ms、Dart 侧预算收紧到 300+150ms）。默认密码固定哈希仍内置，但 Release 首次启动会提示修改；`services` 已禁止反向依赖 `providers`。
