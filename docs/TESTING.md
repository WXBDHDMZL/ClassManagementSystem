# 测试分层与影响分析

`tools/check.py` 是唯一测试入口。四条车道都先跑静态门禁，再按需要跑测试；不再用“只跑 flutter test”冒充全量。

| 车道 | 内容 | 实测 |
| --- | --- | --- |
| `fast` | 门禁 + `flutter analyze` + 改动直接影响的纯单元/烟测；Widget 流程测试留给 commit | 56s（改 `history_dialog.dart`）、50s（文档/工具回退）、9s（仅改 tools） |
| `commit` | 门禁 + analyze + 核心域 26 个 suite + **全部**受影响 suite（不再按数量截断） | 71s / 207 用例（小改动）；245s / 884 用例（大面积改动） |
| `full` | 门禁 + analyze + 全部 130 个测试文件 / 884 用例 | 363s（含覆盖率，4 核）；不含覆盖率约 5 分钟 |
| `release` | full + `release_check.py` 真实安装/覆盖升级/冒烟/卸载 | 需合成数据副本与签名私钥 |

## 常用命令

```bash
python tools/check.py --lane fast
python tools/check.py --lane fast --base origin/main     # PR/合并前按基线选测试
python tools/check.py --lane fast --list                 # 只看会跑哪些文件
python tools/check.py --lane commit
python tools/check.py --lane full
python tools/check.py --lane full --coverage
python tools/check.py --lane release --data-source build/audit_review/v3data/class_management_data.enc --signing-key <私钥>
```

`--data-source` 必须指向合成/脱敏副本；release 车道不会自动使用 `Documents\班级管理系统`。

## 影响分析

`tools/test_graph.py` 解析 `lib/` 与 `test/` 的 `import`、`export`、`part`：

- `fast` 只取**直接** import 改动文件的测试；没有直接测试时退回 3 个核心 unit suite，并对 Widget 改动追加一个 `widget_test.dart` 烟测。
- `commit` 先取核心 26 个 suite；受影响 suite 不超过 10 个时才追加，避免一次改对话框就跑 30+ 个 Widget suite。
- 核心文件（storage/security/auth/provider/import/transfer/update）变化时，`select_affected` 返回全量标记；fast 会收敛，commit/full 由调用方决定。
- 非 Dart 改动（tools/docs/CI）不触发 Dart 全量；`pubspec`、`windows/`、`installer/` 变化保守回退。

Python 单测：`python -m unittest discover -s tools -p 'test_*.py' -v`（24 个用例）。

## 覆盖率

`--coverage` 生成 `coverage/lcov.info`，`tools/coverage_check.py` 输出总行覆盖与 9 个核心文件覆盖。

当前基线（2026-11-28 审计 A-01~A-27 修复后，884 用例）：

- 总行覆盖率 76.39%（10686/13989）
- 核心模块 87.04%（2190/2516）
- 最低核心文件：`github_update_service.dart` 50.77%、`import_restore.dart` 81.79%

### 门禁规则（审计 A-27）

- `--coverage` 现在**默认强制**阈值；`full` 车道的 `--enforce-coverage` 只是兼容保留参数，
  只出报告请用 `--no-enforce-coverage`。
- 绝对底线（过渡值）：总 ≥75.0%、核心 ≥85.7%。
- 棘轮基线：`tools/coverage_baseline.json`（一位小数、向下取整）。实测比基线低超过 0.3 个
  百分点即失败；`python tools/coverage_check.py --update-baseline` 只允许上调，下调必须
  `--allow-lower --reason <原因>` 并留痕。
- 回到目标值的路线图：补 `github_update_service`、导入/撤销失败路径与桌面链路的测试，
  总覆盖率过 80%、核心过 85% 后把绝对底线改成 80.0/85.0，并把该基线一并上调。

## CI

`.github/workflows/tests.yml`：

- PR / push main：`commit` 车道（Windows runner，Flutter 3.44.6）
- 每日 02:17（Asia/Shanghai）/ 手动：`full --coverage`

## Windows 原生冒烟（手工/发布前）

先关闭已运行的班级管理系统（单实例互斥体会让新进程直接退出），再运行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/windows_smoke.ps1 `
  -Exe "build\windows\x64\runner\Release\班级管理系统.exe" `
  -DataDir "build\audit_f6\v3data"
```

脚本把合成数据复制到临时目录，设置 `CMS_DATA_DIR` 与 `CMS_STARTUP_TARGET=tray`，启动 10 秒确认进程存活，然后强制结束并清理。它只验证启动/加载链路，不替代 `release_check.py` 的安装与覆盖升级验收。

## 已知边界

- Windows 原生托盘/悬浮球/单实例/安装器/迁移工具仍以手工或 release 车道验收为主，尚未纳入 `fast/commit`。
- 更新检查只有解析与签名单测；真实 GitHub 302 跳转仍靠 release 验收。
- 覆盖率绝对底线仍是过渡值（75.0/85.7），距离目标 80/85 还差约 3.6 个百分点。
