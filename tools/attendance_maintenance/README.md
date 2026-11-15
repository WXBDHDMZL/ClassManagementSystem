# 历史考勤维护导出

> 不进入安装包，不在程序内显示；仅供作者/本机维护使用。

考勤功能已从 V3.3.0 主界面隐藏，历史考勤数据仍保存在数据文件和旧备份中。
如果以后 DLC 恢复考勤，或需要单独归档旧数据，可用本工具从加密数据文件导出考勤表。

## 用法

在项目根目录设置：

```bat
set CMS_ATTENDANCE_FILE=C:\Users\你\Documents\班级管理系统\class_management_data.enc
set CMS_ATTENDANCE_OUTPUT=C:\Users\你\Desktop\历史考勤.xlsx
flutter test tools/attendance_maintenance/export_attendance_test.dart
```

也可以指向旧的加密备份文件，例如：

```bat
set CMS_ATTENDANCE_FILE=C:\Users\你\Documents\班级管理系统\备份\班级管理系统_备份_20261031_183758.enc
```

## 安全边界

- 程序须完全退出；
- 只读取输入文件，不修改原始数据；
- 输出为明文 Excel，含学生姓名与考勤状态，请妥善保管；
- 不随安装包分发。
