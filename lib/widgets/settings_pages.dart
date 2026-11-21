/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.1
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
/// 设置面板各子页面（library 主文件）。
///
/// 本文件原先是一个 3282 行的巨型文件，已在 V2.27.5 按功能拆分到
/// `settings/` 目录下的多个 `part` 文件。这里保留全部 import 与
/// `part` 声明，外部（settings_panel.dart 及测试）继续
/// `import 'settings_pages.dart'` 即可拿到全部页面类，调用方零改动。
///
/// 之所以用 part 而不是拆成多个独立库：原文件里 21 个 `_` 前缀顶层函数
/// （导入导出、备份恢复、出厂重置等）被**多个设置页跨类共用**，独立库会
/// 切断私有可见性、逼着改 100+ 处调用点；part 让它们在同一 library 内
/// 保持可见，做到只搬家、不改语义。
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'student_import_dialog.dart';
import '../constants/app_version.dart';
import '../constants/app_theme.dart';
import '../constants/attendance_feature.dart';
import '../constants/time_periods.dart';
import '../models/app_settings.dart';
import '../models/attendance_record.dart';
import '../models/password_policy.dart';
import '../models/identity.dart';
import '../models/student_record.dart';
import '../providers/app_data_provider.dart';
import '../services/atomic_file.dart';
import '../services/auth_service.dart';
import '../services/desktop_service.dart';
import '../services/error_log_service.dart';
import '../services/github_update_service.dart';
import '../services/import_service.dart';
import '../services/local_storage_paths.dart';
import '../services/log_file_service.dart';
import '../services/operation_log_service.dart';
import '../services/security_service.dart';
import '../services/statistics_service.dart';
import '../services/update_check_service.dart';
import '../utils/file_names.dart';
import 'confirm_destructive.dart';
import 'password_action_guard.dart';
import 'password_prompt_dialog.dart';
import 'text_prompt_dialog.dart';
import 'update_available_dialog.dart';
import 'weather_city_dialog.dart';
import '../services/transfer_service.dart';
import 'change_password_dialog.dart';
import 'identity_guard.dart';
import 'list_library_dialogs.dart';
import 'import_records_dialog.dart';
import 'operation_log_dialog.dart';
import 'record_list.dart';
import 'settings_widgets.dart';
import 'terms_of_service.dart';
import '../utils/app_clock.dart';

/// part 清单（18 个 part，新增文件请同步此表）：
///  - appearance_settings_page        主题与显示设置页
///  - appearance_window_settings_page 外观、窗口、主页搜索与天气设置页
///  - statistics_settings_page        统计口径设置页
///  - attendance_settings_page        考勤设置页
///  - window_settings_page            窗口与启动设置页
///  - period_settings_page            时间段设置页
///  - about_update_section            关于页的更新区域
///  - data_settings_page             表格与数据包设置页
///  - maintenance_settings_page       日志与维护页
///  - backup_settings_page            备份与恢复设置页
///  - list_library_settings_page      名单与原因库设置页
///  - security_settings_page          安全设置页（管理密码与恢复码）
///  - identity_settings_page          操作身份设置页
///  - about_settings_page             关于页
///  - table_io_actions                表格导入导出动作（记录/名单）
///  - package_io_actions              数据包导入导出动作
///  - backup_restore_actions          备份、从备份恢复与恢复出厂动作
///  - shared_actions                  共享助手（保存文件/选文件/密码校验/通用确认）
part 'settings/appearance_settings_page.dart';
part 'settings/appearance_window_settings_page.dart';
part 'settings/statistics_settings_page.dart';
part 'settings/attendance_settings_page.dart';
part 'settings/window_settings_page.dart';
part 'settings/period_settings_page.dart';
part 'settings/about_update_section.dart';
part 'settings/data_settings_page.dart';
part 'settings/maintenance_settings_page.dart';
part 'settings/backup_settings_page.dart';
part 'settings/list_library_settings_page.dart';
part 'settings/security_settings_page.dart';
part 'settings/identity_settings_page.dart';
part 'settings/about_settings_page.dart';
part 'settings/table_io_actions.dart';
part 'settings/package_io_actions.dart';
part 'settings/backup_restore_actions.dart';
part 'settings/shared_actions.dart';
