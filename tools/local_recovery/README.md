# 本机离线恢复工具（密码找回方案 B）

> 不进入安装包，不在程序内运行，不提供运行时“万能密码”。只建议在本机维护/作者应急时使用。

## 适用场景

- 管理密码、恢复码全部丢失；
- 程序完全退出、能访问本机数据文件。

## 使用步骤

1. **完全退出程序**（托盘右键退出，确认任务管理器里没有 `班级管理系统.exe`）。
2. 找到数据文件（通常在 `C:\Users\<你>\Documents\班级管理系统\class_management_data.enc`，也可能是 OneDrive 文档或自定义位置）。
3. 在项目根目录（`ClassManagementSystem`）打开终端，设置环境变量：

   ```bat
   set CMS_RECOVERY_FILE=C:\Users\你\Documents\班级管理系统\class_management_data.enc
   set CMS_RECOVERY_PASSWORD=新密码123
   flutter test tools/local_recovery/recover_password_test.dart
   ```

4. 看到“恢复完成”后，用新密码打开正式版。工具会：
   - 备份原数据为 `<原文件>.recovery_backup_<时间>`；
   - 备份并删除 `class_management_auth_guard.json`（解除锁定）；
   - 重置管理密码为新密码；
   - 清空恢复码（恢复码一次性）；
   - 写入前复核可重新解码，失败则不改文件。

5. 登录后建议：设置 → 系统与安全 → 安全与密码 → 生成新的恢复码。

## 安全边界

- 需要本机文件访问权限与程序完全退出；不联网；
- 会改写正式数据文件，**务必保留自动备份**；
- 不要把这个工具复制进安装包或分发给最终用户；
- 如果只需要“看数据/导出”，不要用本工具，直接备份数据文件后另行处理。

## 演练（不写入）

```bat
set CMS_RECOVERY_DRY_RUN=1
flutter test tools/local_recovery/recover_password_test.dart
```

演练只验证“能解码、能重新编码”，不会写文件。
