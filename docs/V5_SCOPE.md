# V5.0.0 兼容边界与执行范围

状态：R0 已冻结（2026-11-22）；R1–R4 已完成，R5 待清空历史并发布。
目标：彻底移除 V4.13 及更早版本的旧数据兼容，只保留 V4.14.1 的当前 LRX3 数据作为 5.0 基线；随后全面复审、清空 GitHub 历史并发布 5.0.0。

R0 基线实测（分支 `feat/5.0.0`，HEAD `2d09e74`）：

- 全量测试：779 用例全部通过（`build/audit_v5/baseline_test.log`）。
- `flutter analyze`：No issues found（6.0s）。
- 旧引用盘点：约 28 个 `lib/` 文件、31 个 `test/` 文件、5 个 `tools/` 文件、7 个文档命中 `LRX2/legacy/periodLabels/旧版` 等关键词；后续按本文件删除矩阵逐项处理。

## 1. 支持边界

V5.0.0 只支持：

- V4.14.1 写出的 LRX3 主数据、`.bak`、当前时间戳备份和当前 LRX3 日志。
- V5 数据包（`packageVersion = 2`，包含全部必填字段）。
- 当前 `p2:` 密码格式，以及内置出厂默认密码哈希（当前功能，不算旧版兼容）。

V5.0.0 不支持、不迁移、不回退：

- V4.13 及更早的 LRX2 主数据、备份、日志、锁定状态。
- V3.7.x 文档根目录布局。
- 旧固定名备份 `班级管理系统_备份.enc`。
- `periodLabels` 旧时段字段。
- 旧数据包缺失字段的“保持本机”语义。
- 旧表格缺少“日期”列的“按今天导入”语义。
- 旧版表头别名/旧列顺序。
- 旧版明文日志合并。
- 旧版安装器残留清理。

## 2. 必须保留的安全拒绝

以下代码不是兼容，不能直接删：

- 识别 `LRX2` 魔数后拒绝加载，不能把旧文件送进损坏文件隔离。
- 旧目录布局存在但新目录无数据时，拒绝启动写库并提示，不自动复制。
- 旧固定名备份不列入可恢复列表，但不能静默删除。
- 旧日志文件不合并，但不能覆盖原文件。

拒绝提示统一为：“此数据由旧版本创建，V5.0.0 不支持；请继续使用 V4.14.1，或在 4.x 中导出数据后重建。”

## 3. 删除矩阵

| 领域 | 位置 | 处理 |
| --- | --- | --- |
| 旧目录迁移 | `lib/services/local_storage_paths.dart:113-123`、`lib/services/storage_service.dart:343-454` | 删除复制/迁移；只保留旧路径存在性检测与拒绝 |
| LRX2 解码 | `lib/services/storage_crypto.dart:89-108,152-158` | 删除 `decodeV2` 与 V2 子密钥派生；只保留魔数识别 |
| LRX2 状态 | `lib/services/storage_service.dart:43-50,76-81,201-202,253-266,489-490` | 改名为 `unsupportedFormat`；不读取、不迁移 |
| 旧固定名备份 | `lib/providers/app_data/export_backup.dart:170,197-205,247-258,343-390` | 只识别时间戳备份；旧固定名不再列出/轮换 |
| 旧日志合并 | `lib/main.dart:74-75`、`lib/services/log_file_service.dart:52-55,141-216,417-446` | 删除合并入口与明文兜底；旧日志不再处理 |
| `periodLabels` | `lib/models/app_settings.dart:62,227,356,418,492,557`、`lib/services/transfer_service.dart:61,79,868,933,1051`、`lib/providers/app_data_provider.dart:489-495`、`lib/providers/app_data/import_restore.dart:604-614,640-641,679-680`、`lib/widgets/settings/package_io_actions.dart:202-203,360` | 从模型、包、设置、UI 全部删除 |
| 旧包缺字段 | `lib/services/transfer_service.dart:77-104,887-1051` | `packageVersion=2`，必填字段缺失直接拒绝 |
| 旧表格缺日期 | `lib/services/import_service.dart:57` | 缺“日期”列直接报错，不再按今天 |
| 旧模型兜底 | `lib/models/app_data.dart:216-245`、`student_record.dart:175-210`、`attendance_record.dart:97-103`、`identity.dart:103-108`、`app_settings.dart:546-642` | 只保留当前字段解析；旧字段缺失按格式错误拒绝 |
| 旧锁定注释 | `lib/services/auth_service.dart:103` | 改为 LRX3 当前格式 |
| 旧安装器清理 | `installer/installer.iss:47-53` | 删除旧迁移工具/快捷方式清理 |
| 旧测试/文档 | `test/v37_legacy_upgrade_test.dart`、`test/r1_package_compat_test.dart` 等 | 删除旧兼容用例；保留“拒绝旧格式”用例 |

## 4. 数据包 V2

- `packageFormat` 不变，`packageVersion = 2`。
- 必填：`format`、`version`、`exportedAt`、`students`、`periods`、`weekStart`、`attendanceEnabled`、`attendanceSyncMap`、`reasons`、`attendanceStatuses`、`attendanceAbsentStatuses`、`records`、`attendance`。
- 不再有 `periodLabels`。
- 缺任一必填字段、`version != 2`、字段类型错误：整包拒绝，不进入预览/导入。
- 旧 v1 包提示“此数据包由旧版本创建，V5.0.0 不支持”。

## 5. 密码与身份

- 旧自定义裸 SHA-256 密码已不支持；维持。
- 内置默认密码哈希是否移除，R3 单独决定。若移除，必须同时提供首启强制设置密码，避免默认密码用户被锁死。
- `auth_guard` 只接受 LRX3；旧 LRX2 锁定文件按“不支持”处理，不静默清空锁定（需显式重置并提示）。

## 6. 安装器与发布

- 安装器不再携带迁移工具、旧快捷方式或旧版清理逻辑。
- 升级只支持从 V4.14.1 覆盖到 V5.0.0；旧安装包不承诺升级。
- 发布资产：exe、`.sha256`、Ed25519 `.sig`、历史更新记录 zip。
- 最终仍执行无父根重建、force-push、删除旧 tag/Release，并请 GitHub Support 清理旧 SHA。

## 7. 验收

- `flutter analyze` 无问题。
- 全量测试通过；旧兼容测试删除后，新增“旧格式拒绝”测试。
- `check_rules`、`ui_copy_check`、`check_version`、`stamp_version`、`git diff --check` 全过。
- `build.bat` 干净构建。
- `release_check.py` 用合成 V4.14.1 LRX3 数据完成 4.14.1→5.0.0 覆盖升级、启动、解码、卸载。
- 合成 V4.13 LRX2 数据/旧包验证：明确拒绝、不隔离、不清空。
- 安装包内无旧迁移工具、旧静态钥、真实 PII。
- 发布后下载远端 exe 复算 sha256、验签。
