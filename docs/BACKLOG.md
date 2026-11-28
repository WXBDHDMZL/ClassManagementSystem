# BACKLOG

> 发现但**本轮不修**的问题清单。规则：一次会话一个任务；发现新问题先登记，不顺手修。
> 状态：`待办` / `进行中` / `阻塞` / `暂缓`。证据格式：`文件:行号`（行号以当前 HEAD 为准，动手前重新核对）。
> 当前阶段：**优先逻辑 Bug 与工程规范；不考虑分发**。分发/共享设备/加密加固类统一放 §4「暂缓」。

---

## 1. P0 逻辑正确性与数据丢失（建议最先修）

### B-01 多映射原因下批评记录被静默删改
- 状态：**已完成**（`9de9ac0`） | 影响：记录内容丢失，统计条数不变故不可见
- 证据：`lib/providers/app_data_provider.dart:1332-1339`（更新分支剔除全部映射原因后只补第一条，且不判断是否考勤自动生成）、`:1569-1580`（`_mappedReasonsOf`）、默认映射 `lib/models/app_settings.dart:304-308`
- 复现：默认配置录「张三 · 批评 · 迟到+早退」→ 期望落库两条原因，实际只剩「迟到」；操作日志仍写两条
- 修复方向：仅当 `remark == attendanceSyncMarker` 时整体重写；其余记录不由考勤侧改写（D-015）
- 验收：先红 3 例 → 修后 4 例通过；analyze 无问题；全量 668 通过；日志/库/导出一致
- 结果：`test/records_attendance_sync_test.dart` 4 例；净增 +6 行（ARCH-01 例外已登记）

### B-02 启动读失败+无可用备份 → 空库覆盖主文件
- 状态：**已完成**（`a534059`） | 影响：不可逆数据丢失（瞬时读失败也可触发）
- 批准边界：只改 `storage_service.dart` 两件事（损坏文件隔离为 `.corrupt_*`、用户确认前禁止自动覆盖）；净增 ≤15 行；不碰加密格式/LRX2 头
- 结果：`test/storage_corrupt_isolation_test.dart` 4 例；净增 +15 行；隔离失败时保存会被拒并由 saveFailed 横幅提示
- 证据：`lib/services/storage_service.dart:239-276`（失败返回 `resetToEmpty`，不隔离原文件）、`lib/providers/app_data_provider.dart:551-560`（启动迁移无条件 `_save()`）、`lib/services/storage_service.dart:333-363`
- 修复方向：加载失败先原子改名 `.corrupt_时间戳`；用户确认前禁止 `_save()`；提示含路径
- 验收：破坏主文件并删除 `.bak` → 原文件保留、不被覆盖；`data_recovery_test` 增例

---

## 2. P1 数据/流程一致性（B-01/B-02 之后）

### B-03 统计放假日口径自相矛盾
- 状态：**已完成**（`52bacb9`，口径 D-014 = 放假日期产生的记录计入表扬/批评总数）
- 证据：`lib/services/statistics_service.dart:230-251`（计数含放假）、`:268-296`（天数/趋势排除放假，`:282`）
- 修复：按 D-014 统一——放假日期记录计入总数、记录天数、趋势与每日统计；考勤统计的放假排除规则不变；同步更新 X-11 旧测试并在提交正文说明原因
- 验收：单条放假日记录时「表扬总数/记录天数/趋势」四处一致
- 结果：`test/statistics_holiday_test.dart` 3 例；X-11/P2-47 旧断言已更新；README 同步

### B-04 导入记录不生成考勤，事后编辑却补生成
- 状态：**已完成**（V2.36.0，Batch 1）
- 结果：`importRecords(..., syncAttendance: true)` 按当前“考勤状态→批评原因”映射补登考勤；导入确认框提供勾选（默认勾选）并预估条数；已有手工考勤不覆盖，同一时段多条导入只登记一次；`onAttendanceSynced` 回传实际条数
- 回归：`test/import_batch1_test.dart` 覆盖“勾选/不勾选/已有考勤不覆盖”
- 证据：`lib/providers/app_data/import_restore.dart`、`lib/widgets/import_records_dialog.dart`

### B-05 整包还原忽略包内 `periodLabels`
- 状态：**已完成**（V2.36.0，Batch 1）
- 说明：此前 P2-7 的注释声称已修，但 `restoreFromPackage` 组装 settings 时**没有写入 `periodLabels`**，旧包仍会退化为本机标签；本次补上 `periodLabels: data.periods.isNotEmpty ? {} : data.periodLabels` 并加回归测试
- 回归：`test/import_batch1_test.dart` 的“旧包只有 periodLabels 时自定义时段名不丢”

### B-06 时段删除后考勤显示/导出退化为内部 key
- 状态：**已完成**（V2.36.0，Batch 2）
- 结果：`AttendanceRecord` 新增 `periodName` 显示名快照（JSON 兼容旧数据）；考勤登记/导入/记录派生都保存快照；列表、撤销确认、Excel/统计报表/考勤表导出统一用 `periodLabel`；删除时段前提示受影响考勤条数；编辑已删除时段的记录保留原 key 与名称
- 回归：`test/attendance_batch2_test.dart` 覆盖 JSON 往返、删时段后历史显示、编辑保留
- 证据：`lib/models/attendance_record.dart`、`lib/providers/app_data_provider.dart`、`lib/widgets/attendance_dialog.dart`

### B-07 导入判重键与净化不一致 / 取消日期列回导全落今天
- 状态：**已完成**（V2.36.0，Batch 1）
- 修复：判重键抽取到 `lib/utils/record_text.dart`，与写入侧共用 trim/限长/顿号规范化；`ImportPreview.missingDateColumn` 暴露缺日期列，导入确认框显示警告、必须勾选“已知晓按今天导入”才允许确认
- 回归：`test/import_batch1_test.dart` 覆盖带空格/超长姓名判重、缺日期列标记、有日期列标记

### B-08 `.bak` 覆盖只比长度；`backupTo` 非原子
- 状态：**已完成**（V2.36.0，Batch 3）
- 结果：写入后记录内容 SHA-256；保存前长度一致时再比摘要，同长度外部篡改不再顶掉 `.bak`；`backupTo` 改 `AtomicFile.copyAtomic`
- 回归：`test/batch3_backup_storage_test.dart` 覆盖“同长度损坏不覆盖 .bak”“backupTo 内容可解析”
- 证据：`lib/services/storage_service.dart`

### B-09 恢复出厂「可用 .bak 挽回」在 UI 不成立；自动备份失败无提示
- 状态：**已完成**（V2.36.0，Batch 3）
- 结果：备份列表加入主文件 `.bak`（“上一份自动备份（.bak）”）且备份目录不存在也能列出；启动自动备份失败写 `autoBackupError` 并由主界面提示一次
- 回归：`test/batch3_backup_storage_test.dart` 覆盖列表包含 `.bak`、失败原因可读取
- 证据：`lib/providers/app_data/export_backup.dart`、`lib/main.dart`

### B-10 关键操作前不自动备份；成功提示先于异步落盘
- 状态：**已完成**（V2.36.0，Batch 3）
- 结果：新增 `provider.saveNow()`（await 落盘并返回成败）；整包还原/从备份恢复/恢复出厂前自动备份，备份失败即中止；操作成功后先 await `saveNow()` 再提示，失败改为错误提示
- 回归：`test/batch3_backup_storage_test.dart` 覆盖 saveNow 成功/失败
- 证据：`lib/providers/app_data/export_backup.dart`、`lib/widgets/settings/shared_actions.dart`、`backup_restore_actions.dart`、`package_io_actions.dart`

### B-11 跨零点迁移在自定义时段生效前执行；可能造同日重复考勤
- 状态：**已完成**（V2.36.0，Batch 2）
- 结果：initialize/loadForTest/整包还原/**从备份恢复**都改为**先套用自定义时段、再跑 id 修复与迁移**；跨零点迁移遇到目标日期同学生同时段冲突时保留已有考勤、丢弃重复项并写日志
- 回归：`test/attendance_batch2_test.dart` 覆盖“自定义时段凌晨记录正确归前一天”“目标已有考勤不造重复”“从备份恢复迁移顺序”
- 证据：`lib/providers/app_data_provider.dart`、`lib/providers/app_data/import_restore.dart`、`lib/providers/app_data/export_backup.dart`

### B-12 考勤被改写时更新时间但不更新记录人
- 状态：**已完成**（V2.36.0，Batch 2；复查补强）
- 结果：同一时段再次登记/改写时，`recordedBy` 更新为最近一次操作者（无身份时按空），同时更新显示名快照；**复查修正**：关闭记录身份后改写考勤保留原记录人，避免清空历史快照
- 回归：`test/attendance_batch2_test.dart` 的“考勤改写更新记录人”“关闭身份后保留原记录人”

---

## 3. P2 工程规范与可维护性（P1 规则，按 30 天目标推进）

### B-13 存量裸 catch 74 处
- 状态：**已转为长期治理（不阻塞交付）**（V2.36.0，Batch 6）
- 治理方式：`tools/rule_baseline.json` 锁定“只降不升”，`build.bat` 构建前拦截新增；每次触碰相关文件时收敛该文件裸 catch
- 现状：按“无 on 分支的 catch”口径 **74 处**（`tools/check_rules.py` 实测，基线同步为 74）；目标 ≤8 保留为长期指标，不再作为一次性修复阻塞
- 决策：见 DECISIONS D-030（不把“改成 on Exception”当作修复——会改变 Error 处理语义）

### B-14 版本号多处手写（91 个 lib 文件 + 104 个跟踪文件）
- 状态：**已完成**（V2.36.0，Batch 4）
- 结果：新增 `tools/stamp_version.py`（以 `pubspec.yaml` 为唯一来源，`--check/--fix` 同步 app_version/iss/LICENSE/README/真机清单/lib 文件头）；`check_version.py` 已接入 `build.bat` 构建门禁
- 未做：`check_version.py` 与 stamp 的检查逻辑仍有少量重复，后续可合并

### B-15 测试命名/结构债务
- 状态：**已完成**（V2.36.0，Batch 5）
- 结果：`test/import_service_test.dart` 内的字面 NUL 字符改为 `\u0000` 转义（git 不再按二进制处理，增量 diff 可读）；新测试统一按行为命名（Batch 1–4 均未新增审计轮次命名）；测试文件头允许滞后策略保留
- 未做：25 个历史审计命名文件不重命名（避免无意义 churn）

### B-16 发布/质量门禁缺失
- 状态：**已完成（最小门禁）**（V2.36.0，Batch 4）
- 结果：`tools/check_rules.py` + `tools/rule_baseline.json`（裸 catch 只降不升、lib 文件头必须同步）；`build.bat` 在构建前先跑 `check_version.py` + `check_rules.py`，失败即中止
- 未做：pre-commit 钩子 / CI（当前项目无 CI，构建门禁已覆盖发版路径）

### B-17 README 已知漂移 ≥7 处
- 状态：**已完成**（V2.36.0，Batch 5）
- 已修正：错误日志文件名（两处，改为按月）；依赖清单补 `archive`/`flutter_js`/`screen_retriever`；目录树补 `auth_service`/`atomic_file`/`dev`/`utils`；设置模型说明补两套密码/身份；改密对话框说明改两套密码；恢复出厂补“自动备份”；构建说明补版本/规则门禁；数据路径补 OneDrive 重定向说明
- 未做：README 不逐文件维护完整目录树（顶部已注明“仅示意”）

### B-18 历史审计/交接文档缺失
- 状态：**已完成**（V2.36.0，Batch 5）
- 结果：新建 `docs/audit/INDEX.md`，记录已知审计轮次、产出与落点（BACKLOG/DECISIONS/git log），并约定原始报告找回与 PII 处理方式

### B-19 测试环境 path_provider 替身缺失导致日志噪声
- 状态：**已完成（基础设施）**（V2.36.0，Batch 4）
- 结果：新增 `test/test_bootstrap.dart`（临时文档目录 + path_provider mock + 清理）；Batch 1/2 新测试已接入；之后新测试一律接入，存量测试按需迁移
- 未做：存量测试全量替换（不影响断言，属分批清理）

### B-20 损坏主文件“隔离失败”路径无稳定测试
- 状态：**已完成**（V2.36.0，Batch 6）
- 结果：`StorageService.debugIsolateOverride` 可注入 rename 故障；回归验证“隔离失败 → 原文件保留、saveData 返回 false、主文件不被覆盖”
- 回归：`test/batch6_security_storage_test.dart`
- 证据：`lib/services/storage_service.dart`

### B-21 修改2：操作密码与班主任密码分离 + 身份门禁
- 状态：已完成（V2.36.0+113）
- 结果：AppSettings 新增 `headTeacherPasswordHash`/`passwordRelationMode`；四种密码模式（合并/独立/班主任优先/操作优先）；安全页可设置/关闭/重置；身份门禁仅在记录身份功能开启时生效（用户确认“不强制”）；班主任默认闲置退出；恢复/出厂提示密码影响；provider 写门禁；新增 `test/password_relation_test.dart` 13 例
- 遗留：两套密码的重置 UI 尚无专门 widget 测试（模型层已覆盖）；锁定持久化已在 B-23 完成

### B-22 全量测试偶发失败
- 状态：**已完成（稳定性工具 + 连续验证）**（V2.36.0，Batch 6）
- 结果：新增 `tools/run_full_tests.py`，可重复跑全量并自动保留每次日志/失败用例名；V2.36.0 收尾连续 2 次全量 **716 全绿**，未再复现
- 说明：若日后再次出现，`build/test_runs/run_N_failed.txt` 会直接给出失败用例名，不再依赖聊天记录里的截断输出
- 证据：`tools/run_full_tests.py`

### B-23 密码失败锁定状态未持久化
- 状态：**已完成**（V2.36.0，Batch 6）
- 结果：锁定状态（失败次数/锁定截止/连续锁定次数）写入文档目录 `class_management_auth_guard.json`，重启后仍生效；文件不含密码或哈希，仅计数与时间戳；读取失败退回内存策略，不阻断验证
- 回归：`test/batch6_security_storage_test.dart` 的“重启后仍锁定”
- 证据：`lib/services/auth_service.dart`

### B-24 本机测试版（DEV）运维
- 状态：**已移除**（用户决定不再保留 DEV）
- 结果：`lib/dev/`、`DEV_ADMIN` 免密分支、独立数据/日志/备份、`build_dev` 工具与文档全部删除；正式版只保留正常鉴权与数据路径
- 说明：DEV 无法充当运行时“修改器/令牌”，且独立数据帮不上正式数据；用户明确不需要，故移除

### B-25 provider 写门禁的覆盖边界
- 状态：**已决策不修（已知限制）**（V2.36.0，Batch 6）
- 现状：记录/考勤/名单/原因库/时段/校历/导入恢复/出厂等数据写操作已有 provider 门禁（30 分钟会话授权 + 内部派生写入豁免）；密码、主题、窗口等设置类写操作仍只在 UI 层门禁
- 决策：不再给所有设置 setter 加门禁——会与“首次设置密码”“恢复出厂”“测试直调”等流程互相冲突，收益低于风险；仅作为纵深防御层，真实安全边界仍是本机账户与加密文件
- 后续如需更强隔离：统一 `AuthContext` capability 需整层重构，列入重构期议题（D-031）

### B-26 旧 p2 密码哈希兼容回归（用户实测）
- 状态：**已完成**（V2.36.0，复查后紧急修复）
- 现象：旧版（V2.30.2～V2.36.0 早期）p2 哈希未写迭代次数；V2.36.0 把默认迭代 20,000→100,000 后，旧用户原密码（如 000000）全部验证失败
- 修复：哈希格式加迭代次数；校验先按 20,000 再按 100,000 兼容旧两段式 p2；成功后自动升级
- 回归：`test/security_service_test.dart` 用固定旧 p2/20k 哈希验证 000000 可通过；全量 720 通过

### B-28 本地文件未全覆盖加密
- 状态：**已完成**（V2.38.0）
- 背景：主数据/备份是 LRX2，但操作日志、错误日志、密码锁定状态、插件启用状态、插件参数仍是明文
- 结果：`EncryptedTextFile` 复用 LRX2 逐条/逐行加密；旧明文文件读取兼容，**启动时主动迁移历史日志/插件状态，写入时也会自动迁移**；日志导出前解密为明文；插件状态/参数加密；主数据与备份格式不变
- 范围外（有意保留可读）：用户导出的 Excel/设置方案/数据包/插件包、插件代码（plugin.json/main.js，需支持编辑/导入）、更新包与诊断报告
- 回归：`test/encrypted_text_file_test.dart`；日志/插件/锁定测试增加“磁盘不含明文”断言
- 限制：扩展名仍是 `.txt`，内容为密文；密钥内置，安全级别与主数据 .enc 相同，仍属防误看/防损坏

### B-29 本地文件散落在文档根目录
- 状态：**已完成**（V2.39.0）
- 背景：主数据、备份目录、日志、锁定状态、插件目录都直接散落在系统文档根目录，用户难以整体备份/迁移
- 结果：新增 `LocalStoragePaths`，统一收进 `文档\班级管理系统\`：
  - 根：主数据、`.bak`、锁定状态
  - `备份\`、`日志\`、`插件\`
- 迁移：启动时自动把旧根目录的数据/`班级管理系统_备份`/`班级管理系统_插件`/日志/锁定状态搬入；新位置已存在时旧文件移入 `_迁移备份_<时间>`，绝不覆盖
- 兼容：根文件夹不存在时路径回退旧布局（测试与迁移失败兜底）；正式启动迁移后走新布局
- 回归：`test/local_storage_paths_test.dart`（新布局、旧布局迁移、冲突保护）

### B-27 忘记密码找回（恢复码 + 本机离线工具）
- 状态：**已完成**（V2.37.0）
- 方案 A：设置 → 安全 → 密码找回生成一次性恢复码（20 位分组、随机、只存加盐哈希、不显示明文）；密码框“忘记密码”输入恢复码后把两套密码重置为同一新密码，恢复码作废并清锁定；尝试走 AuthService 锁定
- 方案 B：`tools/local_recovery` 离线工具（不进安装包、不在程序内）；备份数据与锁定文件、重置两套密码、复核编码后写回；支持 dry-run
- 安全：恢复码未设置时 AuthService 明确失败，不会像未启用密码那样放行；恢复码导出设置方案时剥离
- 回归：`test/recovery_code_test.dart`（生成/校验/重置/锁定/字段）；`settings_pages_smoke_test.dart` 覆盖生成 UI；离线工具已用临时数据实际跑通


---

### B-30 设置项分类与权限项审计（V2.40.0）
- 状态：**已完成**
- 内容：安全页拆「安全与密码」+「操作权限」；导出/日志拆页；恢复出厂移到备份页；定期自动导出移回导出页；统计口径独立成页；菜单按 6 组重排；批量新增记录接入身份+记录密码；新增考勤状态设置分类导入导出、备份保留份数、打开数据文件夹、天气地区入口；数据包导出加明文确认，日志导出提示含姓名
- 说明：单条新增记录仍不验证身份/密码，避免打断课堂录入；批量新增（≥2 人）验证
- 范围外：更新与插件页拆分为两个入口、主题/窗口合并为本轮已完成；未做“新增记录严格模式”开关

---

### B-31 操作权限粒度过粗（V2.41.0）
- 状态：**已完成**
- 问题：旧版 8 个模块开关无法表达“只保护编辑/删除记录”“只保护导入”等细粒度需求
- 结果：动作级权限（记录/考勤/名单/原因/时段/校历/数据/备份/日志/更新/插件等 30+ 动作）；预设（不验证/仅修改与删除/仅危险操作/全部写操作/自定义）；页面进入验证作为独立可选层；每次验证或 30 分钟内免重复验证；旧数据按 8 开关推导动作规则，页面开关默认不迁移（避免双弹窗）
- 回归：`test/password_policy_test.dart`；设置页冒烟；原有 742 项全量回归

### B-32 页面验证与动作权限互相干扰（V2.41.1）
- 状态：**已完成**
- 问题：关闭页面验证后，动作规则仍会在打开页面时弹密码；密码模式下拉切换后可能残留遮罩
- 结果：页面开关只控制“进页面时验证”，页面内修改/导入在真正执行时按动作规则验证；密码模式改为按钮组，切换后无残留遮罩；补班主任密码设置对话框标签
- 回归：`test/password_policy_test.dart`、`test/security_mode_overlay_test.dart`

---

### B-33 全量代码审查（2026-11-28）问题修复
- 状态：**已完成**
- 来源：`AUDIT_REPORT_2026-11-28.md`（仓库根，本次审查产出，P1 七条 / P2 二十六条 / P3 二十余条）
- P1（数据正确性，均已修并补回归）：
  - P1-1 主文件缺失 + 唯一 `.bak` 解不开 → 旧实现按"首次启动"放行，第二次保存把空库写进 `.bak`。现 `DataLoadResult.backupUnreadable` + `_unreadableBackupProtected` 阻断写入，确认空库时先把 `.bak` 改名为 `.bak.corrupt_*`
  - P1-2 删除自定义时段后编辑记录 → `periodName` 被改写成裸 key。现 `keepUnidentifiedPeriod` 同时接受"与原 key 相同"，保留 `periodName` 快照
  - P1-3 原因改名跨时段污染 → `_renameReasonInRecordHistory` 增加 `periodKey` 精确匹配，同步映射只在原因从**所有分组**消失时改名/删除
  - P1-4 导出「全天」后回导判重失效 → `matchTimePeriodKey` 补 `all_day` 分支
  - P1-5 恢复写入成功但校验失败时 `finally` 用旧内存回写主文件 → 现置写阻断并提示重启，不再回写
  - P1-6 CSV 字段中间裸引号吞掉后续行 → `_parseCsv` 重写为 RFC 4180 状态机，EOF 未闭合抛 `FormatException`
  - P1-7 名单标题行被当姓名导入 → 表格路径与纯文本首行均过滤标题行
- P2：批量导入原子化（`replaceDuplicateRecords` 只落盘一次）、导入覆盖清 `syncedFromRecord`、`deleteRecords` 补删派生考勤、`idRemap` 改 `putIfAbsent`、`getRecordsForDates` 全表按归属日过滤、`_findLinkedRecord`/`_removeRecordsByIds` 跨桶兜底、`_saveDataNow` 两阶段备份轮转（主写失败不毁 `.bak`）、`restoreFrom` 路径用 `resolveSymbolicLinks` 归一、密钥文件 `create(exclusive:)` 原子占位、原因库导入布局判定、合并单元格展开（新增 `lib/services/xlsx_merge.dart`）、库导入体积/行数上限、CSV 字节上限、`XlsxReader` 按表头关键词选表、时段库一列格式反查、数据包考勤「缺失 vs 空数组」语义、恢复码/密码落盘失败回滚、更新下载空闲超时与取消、`parseChecksum` 逐行匹配多资产、托盘不可用兜底、关机落盘预算 450ms（< 原生 500ms）
- P2-11（`.keyid` 指纹缺失时按数据损坏处理）已在提交前收尾中修复：先试 `.bak` 用当前密钥恢复，不可解再按「密钥不可用 / 内容损坏」区分处理，详见 B-34；B-35（`setExportOptions([])` 静默回退默认列）改为返回 false 并拒绝，详见 B-35
- P3：设置器统一返回 bool 并按真实结果提示、提交防重入、失焦保存、列表 key 去 index、通知监听器不再被清空、导出计数后置、长文案可滚动、学生卡片补 `Semantics`、日志尾读按字节拼接、`deleteAllLogs` 解除 ACL 保护项、`appendLine` 补行尾换行、悬浮球 DPI 变化重绘、窗口最小尺寸并发序号、`verify` 在 await 前同步登记尝试计数（并发也逐个计数）、PBKDF2 迭代上限、UTF-16 裁剪改按 runes、文件名长度截断、`forPeriod` 去重、`setWeekStart` 补权限与阻断检查、`importAttendance` 区分未变更条数
- 回归：`test/audit_2026_11_28_fixes_test.dart`（31 例，含"空密钥占位自愈"2 例、P1-5 故障注入 1 例、B-34 降级 2 例、B-35 拒绝空列 1 例）+ `test/management_password_test.dart` 并发锁定 1 例 + `test/github_update_service_test.dart` 下载分支 6 例+ `test/update_launcher_test.dart` MSI 转义 3 例 + `tools/test_native_guards.py` 原生守卫 2 例；全量 929 用例通过、`flutter analyze` 无问题、`check_rules` 全绿、覆盖率 `--enforce` 通过（总 76.78%、核心 89.37%）、Windows Release 构建成功，详见 `docs/AI_HANDOFF.md` 与仓库根 `AUDIT_FIX_CLOSURE_2026-11-28.md`
- 验收审计发现的衍生问题（均已修）：① `StorageKeyStore` 改 `create(exclusive:)` 后，进程死在"建 0 字节占位 → 写正式内容"之间会永久留空密钥文件；`initializeKey()` 现在"无数据文件 + 空占位"时删占位重建密钥并记错误日志，有数据文件时仍抛 `DataKeyUnavailableException`（绝不覆盖旧数据）。② 删除无调用的 `@visibleForTesting` 钩子 `debugShutdownSaveBudget` / `debugShutdownLogBudget`，改私有 const。

---

### B-34 `_keyIdMismatch` 指纹缺失时的可用性降级（已修复，2026-11-28 提交前收尾）
- 状态：**已修复（方案 1：先试 `.bak` 自动恢复；不可解才隔离，并判定为「密钥不可用」而非「内容损坏」）**
- 原问题：`lib/services/storage_service.dart` 的密钥指纹（`*.keyid`）缺失时 `_keyIdMismatch()` 返回 false，于是「主文件 + `.bak` 都解不开」一律按**内容损坏**处理（`resetToEmpty`）——换机/换 Windows 用户的用户会看到「数据损坏、可确认以空库继续」，而不是「密钥不对、请换回原 `.enc.key`」。
- 现行实现（两层，均不违反「绝不用新密钥覆盖旧数据」）：
  1. **先试恢复**：主文件解不开时，`.bak` 用**当前可用密钥**尝试解密（`_loadDataOrThrow` 的 `_tryLoadFile('$filePath.bak')` 分支）；可解则原子写回主文件、返回 `restoredFromBackup`，并记日志「主文件无法解密，已用备份恢复并写回主文件」。此路径只做「用能解开的那份备份覆盖已损坏的主文件」，不使用新密钥、不重建任何密钥文件。
  2. **区分密钥问题与内容问题**：`.bak` 也不可用时，用 `StorageCrypto.looksEncrypted()` 看主文件**是不是格式合法的 LRX3 密文**。是 → 结论是「密钥不对或数据由别的机器写入」，隔离为 `*.corrupt_<毫秒>`（逐字节保留）后返回 `keyUnavailable: true`，界面按既有文案提示「数据密钥丢失或无法由当前 Windows 用户解密，已暂停保存…」；不是 → 保持原 `resetToEmpty` 判定（`test/storage_key_mismatch_test.dart` 固化的「无指纹旧数据按损坏隔离」语义不变）。
  3. `loadData()` 的写阻断条件补上 `result.keyUnavailable`（此前不在其中，若只返回该 flag 会让后续保存用空库覆盖）。
- **有指纹且不匹配**（`.keyid` 存在但值不同）**不降级**，仍是 `keyMismatch` 拦截、`.bak` 不顶替：那种情况下主文件是**另一把密钥的有效数据**（例如用户刚把别的机器的 `.enc` 拷回来），用本机 `.bak` 顶替等于静默丢掉用户刚还原的文件；`test/storage_key_mismatch_test.dart` ① 也固化了「不隔离、不重置、拒绝写入」。用户仍可通过显式的「以空库继续」确认操作脱困。
- 回归证据：`test/audit_2026_11_28_fixes_test.dart` 的 `group('B-34 指纹缺失时的降级')` 2 例——正例（`.bak` 可解 → `restoredFromBackup` 为真、`students` 含备份内容、不产生 `.corrupt`、主文件内容与备份一致）、反例（`.bak` 也不可解 → `keyUnavailable` 为真、`resetToEmpty` 为假、恰好 1 个 `.corrupt` 且内容与原文件逐字节相同、主文件不存在、`saveData` 返回 false 且不重建主文件、`.enc.key` 未被重建）。反证：把 `if (sealedButUndecryptable)` 短路成 `false` 后该反例失败（`Expected: true / Actual: false`，退出码 1）。
- 影响面：仅换机 / 换 Windows 用户 / 手动删过 `.keyid`、且 `.bak` 也解不开的场景。
- 是否可后续补：可。若希望「密钥不可用」时也提供「确认后以空库继续」的出口，需补一条与 `discardKeyMismatchAndStartEmpty` 对称的确认流程与文案。

### B-35 `setExportOptions([])` 静默回退默认列（已修复，2026-11-28 提交前收尾）
- 状态：**已修复**（空列表 / 全部是未知列键 → 返回 false 且不改状态）
- 原问题：`lib/providers/app_data/settings.dart` 的 `setExportOptions(recordColumns: <String>[])` 把空列表归一为 `null`（= 默认列集），调用方拿到 `true` 以为设置成功，实际导出列被换成默认值。
- 现行实现：`if (cleanedColumns != null && cleanedColumns.isEmpty) return false;`，随后 `recordExportColumns: cleanedColumns`（不再归一为 null）；未知列键仍先被过滤（过滤器保留），但过滤后为空即拒绝。
- 调用点同步：`lib/widgets/settings/data_settings_page.dart` 的列勾选回调改为 `final saved = provider.setExportOptions(recordColumns: next); if (!saved) showTopSnackBar(..., '导出列未保存：至少需要保留一列，且当前需可写入数据文件', isError: true)`；该页原有的「至少要保留一列」勾选拦截保留（双保险）。
- 回归证据：`test/audit_2026_11_28_fixes_test.dart` 的 `group('B-35 setExportOptions 拒绝空列')`——空列表返回 false 且 `recordExportColumns` 保持原值、未知列同样被拒、`['name']` 返回 true 且生效。反证：把守卫去掉后该用例失败（`Expected: false / Actual: true`，退出码 1）。

---

## 4. 暂缓（分发/共享设备/加密加固——当前阶段不排期，但不新增债务）

| 编号 | 事项 | 说明 |
|---|---|---|
| D-01 | PII 清理（真实名单、git 历史、安装包、旧网页版） | 第一、二、三、四轮已完成：删除内置真实名单，默认/恢复出厂为空名单，测试改用合成姓名（D-063）；作者名统一为 `WXBDHDMZL` 并保留邮箱（D-064）；`main`/`glass-attempt` 全历史已重建，55 个姓名与截图已从历史移除（D-065）；V4.9.0 已用清理后的源码重建 Release、符号与安装包并完成产物扫描（D-066） |
| D-02 | 更新包签名/代码签名/安装器硬化 | 冻结区；只修明确指派的 Bug |
| D-03 | 启动锁/查看导出门禁（共享设备场景） | 等用户重启“教室共享设备”议题再评估 |
| D-04 | 加密密钥 DPAPI/口令派生、LRX1 恢复入口收口 | 冻结区；需产品决策 |
| D-05 | ~~插件签名/进程隔离/超时强杀~~ | 已取消：V4.0.0 完全移除插件功能 |
| D-06 | 依赖升级（excel） | 需单独评估，不在当前排期 |
| D-07 | 学生 ID 模型 / schemaVersion / 审计字段 | P2 重构期，等用户明确发起 |

---

## 登记模板

```
### B-XX 标题
- 状态：待办/进行中/阻塞/暂缓
- 影响：
- 证据：文件:行号
- 复现：
- 修复方向：
- 验收：
```
