# 班级管理系统

**Class Management System** · 面向班主任的本地优先班级记录与统计工具

**V4.10.0** · Windows 10/11 · AGPL-3.0-only

[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D4?logo=windows)](https://github.com/WXBDHDMZL/ClassManagementSystem/releases)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-AGPL--3.0--only-blue)](LICENSE.txt)
[![Release](https://img.shields.io/github/v/release/WXBDHDMZL/ClassManagementSystem?display_name=tag)](https://github.com/WXBDHDMZL/ClassManagementSystem/releases)

[下载](https://github.com/WXBDHDMZL/ClassManagementSystem/releases/latest) ·
[HTML 演示](https://github.com/WXBDHDMZL/ClassManagementSystem/releases/tag/v0.0.0) ·
[问题反馈](https://github.com/WXBDHDMZL/ClassManagementSystem/issues) ·
[许可证](LICENSE.txt)

---

## 简介

班级管理系统是一款为班主任日常工作设计的 Windows 桌面应用。它把学生表现记录、班级统计、历史查询和数据导出放在一个轻量的本地应用中：点选学生即可记录表扬或批评，按时间段归档，随时回看与统计；所有班级数据默认保存在本机，不依赖账号、云服务或网络。

项目使用 Flutter 与 Material 3 构建，面向 Windows 10/11，采用本地加密存储、原子写入与自动备份，适合在教室电脑、办公室电脑或随身笔记本上使用。

> 想先看界面，可以打开 [HTML 演示版](https://github.com/WXBDHDMZL/ClassManagementSystem/releases/tag/v0.0.0)。演示数据为合成名单，仅用于预览界面与交互。

## 特点

- **本地优先**：班级记录、名单、设置与日志保存在本机，不需要注册账号，也不会上传到云端。
- **低操作成本**：学生卡片一点即记，原因一键多选，时段按当前时间自动预选。
- **可追溯**：支持按日期查询、跨日期补齐、修改与删除撤销，重要操作写入运行日志。
- **可统计**：按周、月或自选区间查看概览、排行、趋势与学生明细，并导出 Excel 报表。
- **可控**：管理密码、操作身份、自动备份、加密存储与恢复出厂共同保护数据。
- **桌面友好**：支持系统托盘、窗口关闭策略与置顶悬浮球，适合常驻教室电脑。

## 功能

### 记录与查询

- 学生卡片记录表扬/批评，支持原因多选、备注、批量记录与事后追加。
- 按当前时刻自动预选就餐、早读、上课、午休、晚修等时段，时段名称与时间范围可自定义。
- 新增、修改或删除成功后可在提示中撤销最近一次变更，减少误操作。
- 主页支持按姓名实时搜索，学生较多时也能快速定位。
- 历史记录支持多日期查询、跨日期补齐与按学生筛选。

### 统计与导出

- 统计看板提供概览、排行榜、每日趋势与学生明细。
- 趋势图按区间长度自动按天、周或月聚合。
- 提供表扬/批评分类型汇总、明细、每日统计、对比与关注等报表。
- 支持导出今日记录、按日期导出、合并导出、分别导出与排名表。

### 数据与安全

- 主数据、自动备份、运行日志与密码锁定状态均使用本地加密格式保存。
- 保存采用原子写入，每次保存前保留上一份 `.bak`，主文件损坏时可从备份恢复。
- 支持自动备份、备份保留份数、备份位置设置与日志快照。
- 管理密码用于保护敏感操作；操作身份可为记录写入创建人快照。
- 恢复出厂前自动备份，并可在确认时选择同时清除备份与日志。

### 桌面体验

- 浅色、深色与跟随系统三种主题。
- 系统托盘常驻，关闭窗口可选择询问、退出、最小化到托盘或收进悬浮球。
- 悬浮球支持拖动、锁定位置、透明度调整与右键快捷菜单。
- 单实例保护，重复启动只会唤起已运行的窗口。

## 快速开始

### 下载安装

1. 打开 [Releases](https://github.com/WXBDHDMZL/ClassManagementSystem/releases/latest)。
2. 下载最新的 `ClassManagementSystem_Setup_*.exe`。
3. 运行安装程序并按提示完成安装。
4. 首次启动为空名单，请在「设置 → 记录与名单 → 名单与原因库」中添加学生，或导入名单。

系统要求：Windows 10/11 x64。安装包已包含运行所需组件；如系统缺少 Visual C++ 运行库，安装程序会提示。

### 从源码运行

```bash
flutter pub get
flutter run -d windows
```

开发环境：

- Flutter 3.44（stable）
- Visual Studio 2026，含 C++ 桌面工作负载
- Inno Setup 6/7（仅制作安装包时需要）

## 数据与隐私

程序内部文件集中在：

```text
文档\班级管理系统\
  class_management_data.enc          主数据（加密）
  class_management_data.enc.bak      上一份自动备份
  class_management_auth_guard.json   密码锁定状态（内容加密）
  备份\                              自动备份与日志快照
  日志\                              运行日志（单文件、内容加密）
```

- 数据只保存在本机，程序不上传班级记录、名单或日志。
- 天气功能会向 Open-Meteo / Photon 发送所选地区名称或坐标，不包含学生信息。
- 在「关于」中获取正式版本时，只访问 GitHub 官方域名，发送程序版本号与常规网络请求信息。
- 数据加密用于防误读、防误改与防损坏，密钥内置于程序，不等同于口令加密；请把数据文件视为本机私有文件。
- 运行日志解密后可能包含学生姓名，请勿把日志或导出的明文数据转发给无关人员，也不要上传到公开平台。
- 换电脑时请使用「设置 → 数据管理 → 导出与导入」的数据包，或「备份与恢复」的备份流程。

## 技术架构

| 层 | 技术 |
| --- | --- |
| UI | Flutter、Material 3、fl_chart |
| 状态管理 | provider / ChangeNotifier |
| 本地存储 | 自定义 LRX2 加密、原子写入、HMAC 完整性校验 |
| 导入导出 | excel、file_picker、CSV |
| 桌面集成 | window_manager、tray_manager、screen_retriever |
| 平台 | Windows 10/11 x64 |

主要目录：

```text
lib/
├── main.dart                 应用入口与主页布局
├── constants/                主题、时段与内置原因
├── models/                   数据模型与设置
├── providers/                全局状态与业务操作
├── services/                 存储、加密、统计、导入导出、日志、版本检查
├── utils/                    日期、文本与通用工具
└── widgets/                  主界面、对话框与设置页
```

## 开发与质量

```bash
python tools/quick_check.py          # analyze + 本次改动相关测试
python tools/quick_check.py --full   # analyze + 全量测试
python tools/check_rules.py          # 规则门禁
python tools/check_version.py        # 版本落点一致性
```

提交前请确保：

- `flutter analyze` 无问题；
- 相关测试通过，发版前跑全量测试；
- 界面文案只描述当前功能与操作，不写变更历史或设计说明；
- 不提交真实班级数据、日志、备份或含姓名的截图。

## 构建

```bat
build.bat
```

构建前请确认：

- Visual Studio 的 C++ 桌面工作负载已安装；
- 项目路径为纯英文/ASCII（Flutter 的 AOT 混淆工具链不支持中文路径）；
- 产物位于 `build\windows\x64\runner\`。

制作安装包：

```bat
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\installer.iss
```

安装包输出到 `installer\output\`，文件名形如 `班级管理系统_安装包_v<版本>.exe`。安装包只包含程序文件，不包含任何班级数据。

## 参与贡献

欢迎通过 [Issues](https://github.com/WXBDHDMZL/ClassManagementSystem/issues) 反馈问题或提出建议。提交代码前请先说明改动目的与影响范围，并确保不包含真实学生信息、本机路径或个人数据。

## 许可证

本项目以 **GNU Affero General Public License version 3 only（AGPL-3.0-only）** 发布。

- 许可证全文：[LICENSE.txt](LICENSE.txt)
- 你可以自由使用、研究、修改和再分发本程序，商业使用同样允许。
- 分发修改版或通过网络提供修改版时，需按 AGPL 提供对应源代码。
- 本程序按“现状”提供，不提供任何明示或默示担保；责任限制以 AGPL 第 15、16 条为准。
- 第三方组件许可见应用内「关于 → 开源组件许可」。

## 致谢

感谢 Flutter、provider、excel、fl_chart、window_manager、tray_manager 等开源项目，以及所有提交问题和建议的使用者。
