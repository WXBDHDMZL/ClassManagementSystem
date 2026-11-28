/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.2
 * 创建日期 (Created): 2026-10-05 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/foundation.dart' show Listenable;

import '../models/app_data.dart';
import '../models/app_settings.dart' show CloseActionType;
import '../models/attendance_record.dart';
import '../models/student_record.dart';

/// 桌面服务依赖的"应用数据"抽象契约（外部审查报告 H5）。
///
/// 背景：`services/desktop_service.dart` 此前直接
/// `import '../providers/app_data_provider.dart'`，与
/// "providers → services"（provider 使用 transfer_service 等）构成
/// **services ↔ providers 双向依赖**，服务层还被绑定在一个 1400+ 行的具体类上。
///
/// 现在服务层只依赖本接口：
///  - 无 Flutter 绑定的环境可用"只实现本接口的测试替身"驱动服务逻辑；
///  - provider 重构成员不再牵动服务层，反之亦然（编译期约束，而非注释约定）。
///
/// [AppDataProvider] 实现本接口（`implements AppDataReader`）。
/// 接口只声明这两个服务**实际用到**的成员——新增读取需求时请先往这里加，
/// 不要图省事重新 import 具体 provider。
abstract class AppDataReader implements Listenable {
  /// 当前应用数据（模型层聚合，不含任何 provider 逻辑）。
  AppData get appData;

  /// 当前“今日”归属日：跨零点时段凌晨仍取前一天，与记录入库口径一致。
  String get todayAttributionDate;

  /// 数据内容指纹：派生结果缓存的键。由数据内容计算、任何变更后自动改变
  /// （设计说明见 `AppDataProvider.dataFingerprint`）。
  String get dataFingerprint;

  /// 指定日期的全部记录（按日期升序展开）。
  List<StudentRecord> getRecordsForDates(List<String> dates);

  /// 区间内的考勤记录。
  List<AttendanceRecord> getAttendanceForDates(Iterable<String> dates);

  /// 保存"关闭窗口行为"（关闭询问框勾选"记住"后调用）。
  void setCloseAction(CloseActionType action);

  /// 记录退出时的窗口位置与尺寸（供下次启动还原）。
  void setWindowBounds(
    int x,
    int y,
    int width,
    int height, {
    required bool maximized,
  });

  /// 记录悬浮球位置（原生窗口拖拽后回传）。
  void setBallPosition(int x, int y);

  /// 记录悬浮球不透明度（右键菜单选择后回传）。
  void setBallOpacity(double opacity);

  /// 锁定/解锁悬浮球位置（右键菜单切换后回传）。
  void setBallPositionLocked(bool locked);

  /// 立即执行一次备份（"每次退出备份"频率下由退出流程调用）。
  /// 返回 null 表示成功；非 null 为可直接写入错误日志的失败原因。
  /// 用 `String?` 而不是 provider 的 `BackupResult`，避免 services → providers
  /// 的反向类型依赖。
  Future<String?> performExitBackup();

  /// 等待已排队的写盘任务全部完成（退出前调用，确保数据已落盘）。
  Future<void> flushPendingSaves();
}
