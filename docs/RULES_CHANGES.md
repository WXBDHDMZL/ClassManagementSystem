# 规则变更提案

> 按 `AI_RULES.md` §10：AI 不得自行修改 `AI_RULES.md`，需要调整时在此提案，等用户批准后再改规则文件。

---

## 提案 1：UI-01 增加“每次改动必跑文案门禁”（已生效）

**提出时间**：2026-11-14
**批准**：用户 2026-11-14 原话“请将其加入到每次项目有更改时的流程中，全面杜绝这种行为”，即授权把该检查写入流程。
**生效**：2026-11-14，已按下方文字修改 `AI_RULES.md` §4 UI-01 与 §11。

### 现状

- `AI_RULES.md` §4 UI-01 已规定“功能界面禁止写版本变化、旧版对比、迁移说明、设计理由”，并写明“违反时任务不算完成；必须清理文案并补 UI 文案检查”。
- 但执行层此前只有 `test/ui_copy_policy_test.dart`：只扫 `lib/widgets` 与 `lib/main.dart`，只认单/双引号字符串，**漏掉三引号长文案**，也没覆盖 `lib/providers`、`lib/services` 里的用户可见提示。本次违规正是从三引号长文案漏过的。
- 本次已补：`tools/ui_copy_rules.json`（规则唯一来源）、`tools/ui_copy_check.py`（Python 门禁）、重写后的 `test/ui_copy_policy_test.dart`（与 Python 同构，读同一份 JSON）、`tools/check_rules.py` 接入 UI-01。
- `build.bat:11` 已调用 `check_rules.py`，所以**构建前一定会拦**；缺口是“日常改完就提交、不构建”的路径。

### 建议改动（AI_RULES.md）

1. §4 UI-01 末尾追加一段：

   > **每次改动必跑**：只要本次会话修改了 `lib/` 下的任何 Dart 文件，提交前必须执行 `python tools/ui_copy_check.py`（等价 `flutter test test/ui_copy_policy_test.dart`），结果必须是 `[OK] 界面文案门禁通过`。未跑或未通过不得提交、不得声称完成。
   >
   > **规则来源**：界面文案的禁用词表统一维护在 `tools/ui_copy_rules.json`，Python 门禁与 Dart 测试共用；不得只改其中一处。

2. §11 自动化检查规格表增加一行：

   | 规则 | 检查方式 | 基线 |
   |---|---|---|
   | UI-01 | `tools/ui_copy_check.py` 扫描 `lib/**/*.dart` 全部字符串字面量（含三引号，跳过注释），比对 `tools/ui_copy_rules.json` | 0 违规 |

3. §11 运行顺序改为：`check_rules.py`（含 UI-01）→ `flutter analyze` → `flutter test`。**任一失败，不得声称完成。**

### 影响

- 仅增加一道检查，不改任何业务逻辑、不改数据结构。
- 误报风险：`tools/ui_copy_rules.json` 的 `allowed` 白名单可放运行时状态词（当前只有 `更新日志.txt`）；如出现合理误报，改 JSON 而不是放宽规则。
- 不涉及 `docs/`、`更新/`，与“更新内容只写 `更新/更新内容_V*.md`”一致。

### 确认结果

- [x] 用户 2026-11-14 要求把该检查加入每次改动流程，视为批准
- [x] `AI_RULES.md` §4 UI-01 已追加“每次改动必跑 / 规则单一来源 / 覆盖范围”三条
- [x] §11 已增加 UI-01 检查行，运行顺序改为 `check_rules.py`（含 UI-01）→ `flutter analyze` → `flutter test`

实现落点：`tools/ui_copy_rules.json`、`tools/ui_copy_check.py`、`test/ui_copy_policy_test.dart`、`tools/check_rules.py`。
