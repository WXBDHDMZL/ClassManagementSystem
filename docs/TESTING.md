# 测试分层与影响分析

`tools/check.py` 是唯一测试入口。四条车道都先跑静态门禁，再按需要跑测试；不再用“只跑 flutter test”冒充全量。

| 车道 | 内容 | 实测 |
| --- | --- | --- |
| `fast` | 门禁 + `flutter analyze` + 改动直接影响的纯单元/烟测；Widget 流程测试留给 commit | 56s（改 `history_dialog.dart`）、50s（文档/工具回退）、9s（仅改 tools） |
| `commit` | 门禁 + analyze + 核心域 26 个 suite + **全部**受影响 suite（不再按数量截断） | 71s / 207 用例（小改动）；252s / 929 用例（大面积改动） |
| `full` | 门禁 + analyze + 全部 131 个测试文件 / 929 用例 | 535s（含覆盖率，4 核）；不含覆盖率约 5 分钟 |
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

Python 单测：`python -m unittest discover -s tools -p 'test_*.py' -v`（32 个用例）。

## 覆盖率

`--coverage` 生成 `coverage/lcov.info`，`tools/coverage_check.py` 输出总行覆盖与 9 个核心文件覆盖。

当前基线（2026-11-28 全量审查 P1/P2/P3 闭环 + 增量补强 + 提交前收尾后，929 用例）：

- 总行覆盖率 76.78%（10990/14314）
- 核心模块 89.37%（2329/2606）
- 最低核心文件：`github_update_service.dart` 72.68%（下载分支已补 6 例假 `HttpClient` 单测，真实 302 仍靠冒烟）、`storage_service.dart` 86.19%、`import_restore.dart` 89.39%

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

### 真机 DPI / 关机落盘冒烟清单

能自动化的部分已由 `tools/test_native_guards.py` 守住（悬浮球必须处理
`WM_DPICHANGED` / `WM_DISPLAYCHANGE` / `WM_SETTINGCHANGE`；Dart 侧关机预算
300ms + 150ms 必须小于原生 500ms 等待）。以下必须真机执行，发布前逐条打勾：

| # | 操作 | 预期 | 失败判据 |
|---|---|---|---|
| 1 | 应用运行中把显示缩放从 100% 改到 150% | 悬浮球立即重绘清晰、贴边位置不跑偏 | 悬浮球模糊、错位或尺寸不对 |
| 2 | 用 Win+P 切换扩展/复制到另一块屏 | 悬浮球出现在新主屏可拖范围内 | 悬浮球留在屏外、拖不回来 |
| 3 | 切换深色主题与高对比度模式 | 悬浮球图标与底色对比明显 | 图标与背景同色、看不见 |
| 4 | 录入一条记录，3 秒内「开始 → 电源 → 关机」，重启 | 刚录入的记录仍在 | 记录丢失 |
| 5 | 开启「关闭时最小化到托盘」后重复第 4 步 | 关机不被托盘逻辑拦截，正常落盘退出 | 关机卡住或黑屏 |
| 6 | 关机过程中长按电源强制断电，再开机 | 主数据文件可打开（必要时走 `.bak`），无 0 字节数据文件 | 提示数据损坏或名单丢失 |

### 更新下载冒烟清单（纯网络部分）

单测已覆盖：重定向超过 5 次、重定向到非 GitHub 主机、HTTP 非 200、中途取消、
收到字节数与声明长度不符、正常落盘（`test/github_update_service_test.dart`）。
下列真实网络行为仍需人工执行：

| # | 操作 | 预期 | 失败判据 |
|---|---|---|---|
| 1 | 拔网线后点「检查更新」 | 提示网络失败，界面可继续操作 | 卡死、崩溃或误报「已是最新」 |
| 2 | 下载安装包途中点「取消」 | 进度框关闭，更新目录里没有残留的半个安装包 | 残留文件或仍在下 |
| 3 | 下载途中断开网络 30 秒以上 | 提示「下载长时间无数据」，半成品被清理 | 无限等待 |
| 4 | 有真实新版本时走完整流程 | 302 跳转到 `objects.githubusercontent.com` 后下载成功，SHA-256 校验通过才启动安装 | 跳转被拦、校验失败仍安装 |

## 已知边界

- Windows 原生托盘/悬浮球/单实例/安装器/迁移工具仍以手工或 release 车道验收为主，尚未纳入 `fast/commit`。
- 更新检查：解析、版本比较、多资产校验和、下载分支（重定向次数/跨主机拒绝/取消/长度不符/正常落盘）已有单测（`test/github_update_service_test.dart`）；真实 `github.com → objects.githubusercontent.com` 302 跳转仍靠 release 验收，步骤见上文「更新下载冒烟清单」。
- 覆盖率绝对底线仍是过渡值（75.0/85.7），距离目标 80/85 还差约 3.6 个百分点。
