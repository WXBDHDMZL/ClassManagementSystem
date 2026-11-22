// 行为测试：记录 ↔ 考勤双向同步时，老师录入的记录原因不得被考勤侧改写。
//
// 对应 BACKLOG B-01。先红后绿：
//   当前实现下，前 3 个用例会失败（记录原因被静默删改/改写）；
//   第 4 个用例锁定“考勤自动生成记录仍随状态更新”的既有能力，必须保持通过。
//
// 约定：测试不依赖真实名单/真实用户数据；日期固定，避免跨零点抖动。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/providers/app_data_provider.dart';

void main() {
  // provider 的日志/存档通道会用到 Binding；初始化后不再打印无关告警。
  TestWidgetsFlutterBinding.ensureInitialized();
  const date = '2026-10-18';

  AppDataProvider newProvider() {
    final provider = AppDataProvider();
    provider.mergeStudents(const ['张三', '李四']);
    provider.setAttendanceSyncMap(const {'迟到': '迟到', '早退': '早退'});
    return provider;
  }

  group('B-01 记录原因不被考勤同步删改', () {
    test('批评记录含两个映射原因时，原因保持完整', () {
      final provider = newProvider();

      provider.addRecord(
        '张三',
        '批评',
        const ['迟到', '早退'],
        'class',
        '',
        date: date,
      );

      final record = provider.getRecordsForDate(date).single;
      expect(
        record.reasons,
        '迟到、早退',
        reason: '同步只能派生考勤，不能删改老师录入的第二个映射原因',
      );

      final attendance =
          provider.getAttendanceOf('张三', date, periodKey: 'class');
      expect(
        attendance?.status,
        '迟到',
        reason: '记录中第一个命中映射的原因决定考勤状态',
      );
    });

    test('映射原因与普通原因并存时，内容与顺序保持不变', () {
      final provider = newProvider();

      provider.addRecord(
        '张三',
        '批评',
        const ['迟到', '讲话'],
        'class',
        '',
        date: date,
      );

      final record = provider.getRecordsForDate(date).single;
      expect(
        record.reasons,
        '迟到、讲话',
        reason: '不得因同步把普通原因排到前面或丢弃',
      );
    });

    test('老师手工修改考勤状态时，不反向改写老师录入的记录原因', () {
      final provider = newProvider();
      provider.addRecord(
        '张三',
        '批评',
        const ['迟到', '早退'],
        'class',
        '',
        date: date,
      );

      // 老师直接在考勤侧把状态改为另一个映射状态。
      provider.setAttendanceForStudents(
        const ['张三'],
        '早退',
        date: date,
        periodKey: 'class',
      );

      final record = provider.getRecordsForDate(date).single;
      expect(
        record.reasons,
        '迟到、早退',
        reason: '记录是老师录入的源数据，考勤侧改状态不得回写记录原因',
      );
      expect(
        provider.getAttendanceOf('张三', date, periodKey: 'class')?.status,
        '早退',
      );
    });

    test('考勤自动生成的批评记录仍随考勤状态更新原因（既有能力不回退）', () {
      final provider = newProvider();

      // 先登记考勤 → 自动生成派生批评记录。
      provider.setAttendanceForStudents(
        const ['李四'],
        '迟到',
        date: date,
        periodKey: 'class',
      );
      var record = provider.getRecordsForDate(date).single;
      expect(record.remark, AppDataProvider.attendanceSyncMarker);
      expect(record.reasons, '迟到');

      // 状态改为另一个映射状态 → 派生记录原因应跟随更新。
      provider.setAttendanceForStudents(
        const ['李四'],
        '早退',
        date: date,
        periodKey: 'class',
      );
      record = provider.getRecordsForDate(date).single;
      expect(
        record.reasons,
        '早退',
        reason: '自动生成的记录仍应跟随考勤状态（P2-38 能力保留）',
      );
    });
  });
}
