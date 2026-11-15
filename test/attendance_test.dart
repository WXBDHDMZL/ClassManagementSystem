// 考勤测试：记录模型、设置项兼容、"默认出勤只记例外"的数据层语义、
// 重命名同步、密码开关与表格/数据包往返。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/services/transfer_service.dart';

import 'test_helpers.dart';

void main() {
  group('考勤记录模型', () {
    test('JSON 往返保持全部字段', () {
      const record = AttendanceRecord(
        id: 'a1',
        studentName: '张三',
        status: '迟到',
        date: '2026-09-26',
        timestamp: '08:15:00',
        recordedBy: '班长 · 王五',
      );

      final restored = AttendanceRecord.fromJson(record.toJson());

      expect(restored.id, 'a1');
      expect(restored.studentName, '张三');
      expect(restored.status, '迟到');
      expect(restored.date, '2026-09-26');
      expect(restored.timestamp, '08:15:00');
      expect(restored.recordedBy, '班长 · 王五');
    });

    test('字段缺失时回退为空字符串，不抛异常', () {
      final restored = AttendanceRecord.fromJson({});

      expect(restored.id, '');
      expect(restored.studentName, '');
      expect(restored.status, '');
      expect(restored.date, '');
      expect(restored.timestamp, '');
      expect(restored.recordedBy, '');
    });

    test('考勤记录人参与复制与相等性，写盘兼容旧数据', () {
      const record = AttendanceRecord(
        id: 'a1',
        studentName: '张三',
        status: '迟到',
        date: '2026-09-26',
        timestamp: '08:15:00',
        recordedBy: '纪律委员 · 李四',
      );
      expect(record.copyWith(status: '请假').recordedBy, '纪律委员 · 李四');
      expect(
        record ==
            const AttendanceRecord(
              id: 'a1',
              studentName: '张三',
              status: '迟到',
              date: '2026-09-26',
              timestamp: '08:15:00',
              recordedBy: '纪律委员 · 李四',
            ),
        isTrue,
      );
      expect(record.toJson()['recordedBy'], '纪律委员 · 李四');
    });

    test('"出勤"是保留词：不能作为状态项，但不影响正常名称', () {
      expect(AttendanceRecord.presentStatus, '出勤');
      expect(AttendanceRecord.validateStatus('出勤'), isNotNull);
      expect(AttendanceRecord.validateStatus('  出勤 '), isNotNull);
      expect(AttendanceRecord.validateStatus(''), isNotNull);
      expect(AttendanceRecord.validateStatus('请假'), isNull);
    });
  });

  group('考勤记录人', () {
    test('启用身份后手工登记写入当前记录人，并同步到派生批评记录', () {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      provider.mergeStudents(['张三']);
      provider.setIdentityFeatureEnabled(true);
      provider.setIdentityIdleMinutes(0);
      provider.setActiveIdentity('class_monitor');
      provider.setAttendanceSyncMap({'迟到': '迟到'});

      provider.setAttendance('张三', '迟到', date: '2026-10-04');

      final attendance = provider.getAttendanceOf('张三', '2026-10-04');
      expect(attendance?.recordedBy, '班长');
      final record = provider.getRecordsForDate('2026-10-04').single;
      expect(record.recordedBy, '班长');
    });

    test('记录派生的考勤沿用源记录人，身份切换后已有记录不被改写', () {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      provider.mergeStudents(['张三']);
      provider.setIdentityFeatureEnabled(true);
      provider.setIdentityIdleMinutes(0);
      provider.setActiveIdentity('class_monitor');
      provider.addRecord(
        '张三',
        '批评',
        ['讲话'],
        'class',
        '',
        date: '2026-10-04',
      );
      final source = provider.getRecordsForDate('2026-10-04').single;
      expect(source.recordedBy, '班长');

      // 换人把原因改成会同步考勤的原因：派生考勤应沿用原记录人。
      provider.setActiveIdentity('discipline_committee');
      provider.setAttendanceSyncMap({'迟到': '迟到'});
      final updated = provider.updateRecord(
        source.id,
        '批评',
        ['迟到'],
        'class',
        '',
        date: '2026-10-04',
      );
      expect(updated, isTrue);

      final attendance = provider.getAttendanceOf(
        '张三',
        '2026-10-04',
        periodKey: 'class',
      );
      expect(attendance?.recordedBy, '班长');
      expect(
        provider.getRecordsForDate('2026-10-04').single.recordedBy,
        '班长',
        reason: '编辑记录应保留原记录人快照',
      );
    });

    test('考勤导入保留记录人；文件没带记录人时不擦除已有值', () {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      provider.mergeStudents(['张三']);

      AttendanceRecord imported(String status, String recordedBy) {
        return AttendanceRecord(
          id: '',
          studentName: '张三',
          status: status,
          date: '2026-10-04',
          timestamp: '08:00:00',
          recordedBy: recordedBy,
        );
      }

      provider.importAttendance([imported('迟到', '班长 · 王五')]);
      expect(
        provider.getAttendanceOf('张三', '2026-10-04')?.recordedBy,
        '班长 · 王五',
      );

      // 文件不带记录人：状态未变时保留原值。
      provider.importAttendance([imported('迟到', '')]);
      expect(
        provider.getAttendanceOf('张三', '2026-10-04')?.recordedBy,
        '班长 · 王五',
      );

      // 文件显式带记录人：按文件更新。
      provider.importAttendance([imported('迟到', '纪律委员 · 李四')]);
      expect(
        provider.getAttendanceOf('张三', '2026-10-04')?.recordedBy,
        '纪律委员 · 李四',
      );

      // 状态变化但文件不带记录人：状态更新，记录人保留。
      provider.importAttendance([imported('请假', '')]);
      final record = provider.getAttendanceOf('张三', '2026-10-04');
      expect(record?.status, '请假');
      expect(record?.recordedBy, '纪律委员 · 李四');
    });
  });

  group('考勤设置项', () {
    test('开关与状态项可完整往返', () {
      final settings = AppSettings(
        themeMode: ThemeModeType.system,
        attendanceEnabled: true,
        attendanceStatuses: const ['迟到', '请假', '事假'],
      );

      final restored = AppSettings.fromJson(settings.toJson());

      expect(restored.attendanceEnabled, isTrue);
      expect(restored.attendanceStatuses, ['迟到', '请假', '事假']);
    });

    test('旧数据缺字段时回退为关闭 + 出厂状态项', () {
      final restored = AppSettings.fromJson({'themeMode': 0});

      expect(restored.attendanceEnabled, isFalse);
      expect(restored.attendanceStatuses, AppSettings.defaultAttendanceStatuses);
      expect(restored.attendanceStatuses, ['迟到', '早退', '请假', '缺勤']);
    });

    test('状态项非法时回退：空列表/全非法值用出厂，重复、空白与"出勤"被清理', () {
      expect(
        AppSettings.fromJson({'attendanceStatuses': <String>[]})
            .attendanceStatuses,
        AppSettings.defaultAttendanceStatuses,
      );
      expect(
        AppSettings.fromJson({
          'attendanceStatuses': [1, '', '  '],
        }).attendanceStatuses,
        AppSettings.defaultAttendanceStatuses,
      );
      expect(
        AppSettings.fromJson({
          'attendanceStatuses': ['迟到', ' 迟到 ', '', '请假'],
        }).attendanceStatuses,
        ['迟到', '请假'],
      );
      // "出勤"是保留词：旧数据里若存了它，读取时丢弃（空则回退出厂）
      expect(
        AppSettings.fromJson({
          'attendanceStatuses': ['出勤', '请假'],
        }).attendanceStatuses,
        ['请假'],
      );
      expect(
        AppSettings.fromJson({
          'attendanceStatuses': ['出勤'],
        }).attendanceStatuses,
        AppSettings.defaultAttendanceStatuses,
      );
    });
  });

  group('考勤数据聚合', () {
    test('AppData 往返保留考勤分组', () {
      final data = AppData(
        recordsByDate: {},
        settings: AppSettings(themeMode: ThemeModeType.system),
        attendanceByDate: {
          '2026-09-26': [
            const AttendanceRecord(
              id: 'a1',
              studentName: '张三',
              status: '迟到',
              date: '2026-09-26',
              timestamp: '08:15:00',
            ),
          ],
        },
      );

      final restored = AppData.fromJson(
        jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
      );

      expect(restored.attendanceByDate.keys, ['2026-09-26']);
      expect(restored.attendanceByDate['2026-09-26']!.single.studentName, '张三');
    });

    test('旧数据没有考勤字段时按空表处理', () {
      final restored = AppData.fromJson({
        'recordsByDate': <String, dynamic>{},
        'settings': <String, dynamic>{},
      });

      expect(restored.attendanceByDate, isEmpty);
    });
  });

  group('考勤数据层', () {
    test('登记：同一学生同一天只保留一个状态，重复登记不产生新记录', () {
      final provider = AppDataProvider();

      expect(provider.setAttendance('张三', '迟到', date: '2026-09-26'), isTrue);
      expect(provider.getAttendanceForDate('2026-09-26').length, 1);
      expect(provider.getAttendanceOf('张三', '2026-09-26')!.status, '迟到');

      expect(provider.setAttendance('张三', '请假', date: '2026-09-26'), isTrue);
      final record = provider.getAttendanceOf('张三', '2026-09-26')!;
      expect(record.status, '请假');
      expect(provider.getAttendanceForDate('2026-09-26').length, 1);

      // 状态没有变化时不写数据
      expect(provider.setAttendance('张三', '请假', date: '2026-09-26'), isFalse);
    });

    test('撤销：传空状态删除该生当天记录（恢复为出勤），日期下无记录时整日移除', () {
      final provider = AppDataProvider();
      provider.setAttendance('李四', '早退', date: '2026-09-26');

      expect(provider.setAttendance('李四', '', date: '2026-09-26'), isTrue);
      expect(provider.getAttendanceForDate('2026-09-26'), isEmpty);
      expect(provider.getAttendanceDates(), isEmpty);
      // 已无记录时再撤销返回 false
      expect(provider.setAttendance('李四', '', date: '2026-09-26'), isFalse);
    });

    test('批量登记：返回实际变化条数，状态未变的不计数', () {
      final provider = AppDataProvider();
      provider.setAttendance('张三', '迟到', date: '2026-09-26');

      final changed = provider.setAttendanceForStudents(
        ['张三', '李四', '王五'],
        '请假',
        date: '2026-09-26',
      );

      expect(changed, 3);
      expect(provider.getAttendanceOf('张三', '2026-09-26')!.status, '请假');
      expect(provider.getAttendanceOf('李四', '2026-09-26')!.status, '请假');
      expect(provider.getAttendanceOf('王五', '2026-09-26')!.status, '请假');
      expect(provider.getAttendanceForDate('2026-09-26').length, 3);

      // 再次登记同一状态：无变化
      expect(
        provider.setAttendanceForStudents(
          ['李四'],
          '请假',
          date: '2026-09-26',
        ),
        0,
      );

      // 批量恢复为出勤
      expect(
        provider.setAttendanceForStudents(
          ['李四', '王五'],
          '',
          date: '2026-09-26',
        ),
        2,
      );
      expect(provider.getAttendanceForDate('2026-09-26').length, 1);
    });

    test('批量登记：空名单与空白姓名被忽略', () {
      final provider = AppDataProvider();
      expect(
        provider.setAttendanceForStudents([], '请假', date: '2026-09-26'),
        0,
      );
      expect(
        provider.setAttendanceForStudents(['  '], '请假', date: '2026-09-26'),
        0,
      );
      expect(provider.getAttendanceForDate('2026-09-26'), isEmpty);
    });

    test('统计：应到为名单人数，实到只扣"计为未到"的状态（迟到不减实到）', () {
      final provider = AppDataProvider();
      final total = provider.appData.students.length;
      provider.addStudent('测试同学A');
      provider.addStudent('测试同学B');
      provider.setAttendance('测试同学A', '迟到', date: '2026-09-26');
      provider.setAttendance('测试同学B', '请假', date: '2026-09-26');

      final stats = provider.attendanceStats('2026-09-26');

      expect(stats.total, total + 2);
      expect(stats.byStatus.keys.toList(), ['迟到', '早退', '请假', '缺勤']);
      expect(stats.byStatus['迟到'], 1);
      expect(stats.byStatus['请假'], 1);
      expect(stats.byStatus['早退'], 0);
      // 异常两人（迟到 + 请假），但只有"请假"算未到 → 实到只少 1 人
      expect(stats.abnormalStudents, 2);
      expect(stats.absentStudents, 1);
      expect(stats.recordCount, 2);
      expect(stats.presentCount, total + 1);
      expect(stats.offRosterCount, 0);
    });

    test('"计为未到"的状态可按需调整（含自定义状态项的默认推断）', () {
      final provider = providerWithStudents(syntheticStudents(5));
      final total = provider.appData.students.length;

      // 默认：请假/缺勤计为未到，迟到/早退不计
      expect(
        provider.appData.settings.attendanceAbsentStatuses,
        ['请假', '缺勤'],
      );

      // 新增自定义状态"事假"：按名称含"假"自动计为未到
      provider.setAttendanceStatuses([
        ...provider.appData.settings.attendanceStatuses,
        '事假',
      ]);
      expect(
        provider.appData.settings.attendanceAbsentStatuses,
        contains('事假'),
      );

      // 手动把"迟到"也计为未到 → 实到随之变化（用名单内的学生，否则只算名单外记录）
      final student = provider.appData.students.first;
      provider.setAttendance(student, '迟到', date: '2026-09-26');
      expect(provider.attendanceStats('2026-09-26').presentCount, total);
      provider.setAttendanceAbsentStatuses(['请假', '缺勤', '迟到']);
      expect(provider.attendanceStats('2026-09-26').presentCount, total - 1);

      // 状态改名时"计为未到"名单同步
      provider.renameAttendanceStatus('迟到', '迟到（早读）');
      expect(
        provider.appData.settings.attendanceAbsentStatuses,
        contains('迟到（早读）'),
      );

      // 删除状态项时从"计为未到"名单移除
      provider.setAttendanceStatuses(['请假', '缺勤']);
      expect(
        provider.appData.settings.attendanceAbsentStatuses,
        ['请假', '缺勤'],
      );
    });

    test('统计：名单外学生的记录计入状态人数并单独计条数，不影响应到/实到', () {
      final provider = AppDataProvider();
      final total = provider.appData.students.length;
      provider.setAttendance('已移除的学生', '缺勤', date: '2026-09-26');

      final stats = provider.attendanceStats('2026-09-26');

      expect(stats.total, total);
      expect(stats.byStatus['缺勤'], 1);
      expect(stats.offRosterCount, 1);
      expect(stats.abnormalStudents, 0);
      expect(stats.presentCount, total);
    });

    test('异常记录按时间段分组：全天在前、组内按名单顺序排列', () {
      final provider = providerWithStudents(syntheticStudents(5));
      final students = provider.appData.students;
      final periods = attendancePeriodOptions();
      final morning = periods[1]['key']!;
      final classKey = periods[2]['key']!;
      // 名单中靠后的学生先登记，验证输出顺序仍按名单排列
      provider.setAttendance(students[3], '请假', date: '2026-09-26');
      provider.setAttendance(students[1], '请假', date: '2026-09-26');
      provider.setAttendance(
        students[2],
        '缺勤',
        date: '2026-09-26',
        periodKey: morning,
      );
      provider.setAttendance(
        students[0],
        '迟到',
        date: '2026-09-26',
        periodKey: classKey,
      );

      final groups = provider.attendanceByPeriod('2026-09-26');

      expect(
        groups.keys.toList(),
        [AttendanceRecord.allDayKey, morning, classKey],
      );
      expect(
        groups[AttendanceRecord.allDayKey]!
            .map((record) => record.studentName)
            .toList(),
        [students[1], students[3]],
      );
      expect(groups[morning]!.single.studentName, students[2]);
      expect(groups[classKey]!.single.status, '迟到');
    });

    test('清空本日返回删除条数，其它日期不受影响', () {
      final provider = AppDataProvider();
      provider.setAttendance('张三', '迟到', date: '2026-09-26');
      provider.setAttendance('李四', '请假', date: '2026-09-26');
      provider.setAttendance('张三', '缺勤', date: '2026-09-25');

      expect(provider.clearAttendance('2026-09-26'), 2);
      expect(provider.getAttendanceForDate('2026-09-26'), isEmpty);
      expect(provider.getAttendanceForDate('2026-09-25').length, 1);
      expect(provider.clearAttendance('2026-09-26'), 0);
    });

    test('状态改名同步更新历史考勤记录', () {
      final provider = AppDataProvider();
      provider.setAttendance('张三', '早退', date: '2026-09-26');
      provider.setAttendance('李四', '迟到', date: '2026-09-26');

      provider.renameAttendanceStatus('早退', '提前离校');

      expect(
        provider.appData.settings.attendanceStatuses,
        ['迟到', '提前离校', '请假', '缺勤'],
      );
      expect(provider.getAttendanceOf('张三', '2026-09-26')!.status, '提前离校');
      expect(provider.getAttendanceOf('李四', '2026-09-26')!.status, '迟到');
      expect(provider.countAttendanceWithStatus('提前离校'), 1);
      expect(provider.countAttendanceWithStatus('早退'), 0);
    });

    test('状态改名拒绝空名、重名与不存在的状态', () {
      final provider = AppDataProvider();
      provider.setAttendance('张三', '早退', date: '2026-09-26');

      provider.renameAttendanceStatus('早退', '  ');
      provider.renameAttendanceStatus('早退', '迟到');
      provider.renameAttendanceStatus('不存在', '临时');

      expect(
        provider.appData.settings.attendanceStatuses,
        ['迟到', '早退', '请假', '缺勤'],
      );
      expect(provider.getAttendanceOf('张三', '2026-09-26')!.status, '早退');
    });

    test('学生改名同步考勤记录，改名后仍能按新名查到', () {
      final provider = AppDataProvider();
      provider.addStudent('测试同学');
      provider.setAttendance('测试同学', '请假', date: '2026-09-26');

      expect(provider.renameStudent('测试同学', '测试同学改名'), isTrue);

      expect(provider.getAttendanceOf('测试同学', '2026-09-26'), isNull);
      expect(
        provider.getAttendanceOf('测试同学改名', '2026-09-26')!.status,
        '请假',
      );
    });

    test('批量导入：id 为空时分配 id，同一天同一学生以导入为准并跳过无变化项', () {
      final provider = AppDataProvider();
      provider.setAttendance('张三', '迟到', date: '2026-09-26');

      final imported = provider.importAttendance([
        const AttendanceRecord(
          id: '',
          studentName: '张三',
          status: '请假',
          date: '2026-09-26',
          timestamp: '09:00:00',
        ),
        const AttendanceRecord(
          id: '',
          studentName: '李四',
          status: '缺勤',
          date: '2026-09-26',
          timestamp: '',
        ),
        // 姓名或日期缺失的条目被跳过
        const AttendanceRecord(
          id: '',
          studentName: '',
          status: '请假',
          date: '2026-09-26',
          timestamp: '',
        ),
      ]);

      expect(imported, 2);
      expect(provider.getAttendanceOf('张三', '2026-09-26')!.status, '请假');
      final li = provider.getAttendanceOf('李四', '2026-09-26')!;
      expect(li.status, '缺勤');
      expect(li.id.isNotEmpty, isTrue);

      // 再次导入完全相同的数据不写入
      expect(
        provider.importAttendance([
          const AttendanceRecord(
            id: '',
            studentName: '李四',
            status: '缺勤',
            date: '2026-09-26',
            timestamp: '',
          ),
        ]),
        0,
      );
    });

    test('状态项合并只追加缺失项', () {
      final provider = AppDataProvider();

      final added = provider.mergeAttendanceStatuses(['迟到', '事假', ' 病假 ']);

      expect(added, 2);
      expect(
        provider.appData.settings.attendanceStatuses,
        ['迟到', '早退', '请假', '缺勤', '事假', '病假'],
      );
    });

    test('恢复出厂清空考勤数据', () {
      final provider = AppDataProvider();
      provider.setAttendance('张三', '迟到', date: '2026-09-26');

      provider.factoryReset();

      expect(provider.getAllAttendance(), isEmpty);
      expect(provider.getAttendanceDates(), isEmpty);
      expect(
        provider.appData.settings.attendanceStatuses,
        AppSettings.defaultAttendanceStatuses,
      );
    });
  });

  group('考勤时间段', () {
    test('同一学生同一天不同时间段可各记一条，同一时间段重复登记只更新', () {
      final provider = AppDataProvider();
      final periods = attendancePeriodOptions();
      final morning = periods[1]['key']!;
      final classKey = periods[2]['key']!;

      provider.setAttendance(
        '张三',
        '迟到',
        date: '2026-09-26',
        periodKey: morning,
      );
      provider.setAttendance(
        '张三',
        '请假',
        date: '2026-09-26',
        periodKey: classKey,
      );
      expect(provider.getAttendanceForDate('2026-09-26').length, 2);

      // 同一时间段再登记：只更新这一条
      provider.setAttendance(
        '张三',
        '缺勤',
        date: '2026-09-26',
        periodKey: classKey,
      );
      final classRecord = provider.getAttendanceOf(
        '张三',
        '2026-09-26',
        periodKey: classKey,
      )!;
      expect(classRecord.status, '缺勤');
      expect(provider.getAttendanceForDate('2026-09-26').length, 2);
    });

    test('时间段可选全天（默认），导入时保留时间段', () {
      final provider = AppDataProvider();
      provider.setAttendance('张三', '请假', date: '2026-09-26');
      expect(
        provider.getAttendanceOf('张三', '2026-09-26')!.periodKey,
        AttendanceRecord.allDayKey,
      );

      final imported = provider.importAttendance([
        const AttendanceRecord(
          id: '',
          studentName: '李四',
          status: '迟到',
          date: '2026-09-26',
          periodKey: 'morning_reading',
          timestamp: '07:30:00',
        ),
      ]);
      expect(imported, 1);
      expect(
        provider
            .getAttendanceOf('李四', '2026-09-26', periodKey: 'morning_reading')!
            .status,
        '迟到',
      );
    });
  });

  group('考勤与批评记录同步', () {
    test('正向：登记迟到会生成一条批评记录并建立关联', () {
      final provider = AppDataProvider();

      provider.setAttendance('张三', '迟到', date: '2026-09-26');

      final records = provider.getRecordsForDate('2026-09-26');
      expect(records.length, 1);
      expect(records.first.operationType, '批评');
      expect(records.first.reasons, '迟到');
      expect(records.first.remark, AppDataProvider.attendanceSyncMarker);
      expect(
        provider.getAttendanceOf('张三', '2026-09-26')!.syncedRecordId,
        records.first.id,
      );
    });

    test('正向：状态改成不同步的状态（请假）时删除已生成的批评记录', () {
      final provider = AppDataProvider();
      provider.setAttendance('张三', '迟到', date: '2026-09-26');
      expect(provider.getRecordsForDate('2026-09-26').length, 1);

      provider.setAttendance('张三', '请假', date: '2026-09-26');

      expect(provider.getRecordsForDate('2026-09-26'), isEmpty);
      expect(
        provider.getAttendanceOf('张三', '2026-09-26')!.syncedRecordId,
        '',
      );
    });

    test('正向：状态改为另一个同步状态时更新原因而不是新增记录', () {
      final provider = AppDataProvider();
      provider.setAttendance('张三', '迟到', date: '2026-09-26');
      final firstId = provider.getRecordsForDate('2026-09-26').single.id;

      provider.setAttendance('张三', '缺勤', date: '2026-09-26');

      final records = provider.getRecordsForDate('2026-09-26');
      expect(records.length, 1);
      expect(records.single.id, firstId);
      expect(records.single.reasons, '旷课');
    });

    test('正向：撤销考勤会删除同步生成的批评记录', () {
      final provider = AppDataProvider();
      provider.setAttendance('张三', '迟到', date: '2026-09-26');

      provider.setAttendance('张三', '', date: '2026-09-26');

      expect(provider.getRecordsForDate('2026-09-26'), isEmpty);
    });

    test('反向：记录里选"迟到"原因会自动登记考勤，且不会重复生成记录', () {
      final provider = AppDataProvider();

      provider.addRecord('李四', '批评', ['迟到'], 'morning_reading', '');

      final records = provider.getTodayRecords();
      expect(records.length, 1);
      final attendance = provider.getAttendanceOf(
        '李四',
        records.single.date!,
        periodKey: 'morning_reading',
      )!;
      expect(attendance.status, '迟到');
      expect(attendance.syncedRecordId, records.single.id);
    });

    test('反向：记录里选"旷课"对应考勤的"缺勤"', () {
      final provider = AppDataProvider();

      provider.addRecord('王五', '批评', ['旷课'], 'class', '');

      expect(
        provider
            .getAttendanceOf(
              '王五',
              provider.getTodayRecords().single.date!,
              periodKey: 'class',
            )!
            .status,
        '缺勤',
      );
    });

    test('反向：表扬记录不会同步考勤', () {
      final provider = AppDataProvider();

      provider.addRecord('赵六', '表扬', ['迟到'], 'class', '');

      expect(
        provider.getAttendanceOf(
          '赵六',
          provider.getTodayRecords().single.date!,
          periodKey: 'class',
        ),
        isNull,
      );
    });

    test('编辑记录：原因不再同步时撤销考勤', () {
      final provider = AppDataProvider();
      provider.addRecord('李四', '批评', ['迟到'], 'class', '');
      final record = provider.getTodayRecords().single;

      provider.updateRecord(record.id, '批评', ['上课讲话'], 'class', '');

      expect(
        provider.getAttendanceOf('李四', record.date!, periodKey: 'class'),
        isNull,
      );
    });

    test('删除手工考勤派生的记录：手工考勤保留（S-1）', () {
      final provider = AppDataProvider();
      provider.setAttendance('张三', '迟到', date: '2026-09-26');
      final record = provider.getRecordsForDate('2026-09-26').single;

      provider.deleteRecord(record.id, date: '2026-09-26');

      // S-1：删派生批评记录不再误删老师手工登记的考勤。
      expect(provider.getAttendanceForDate('2026-09-26'), isNotEmpty);
      expect(provider.getAttendanceOf('张三', '2026-09-26')!.status, '迟到');
    });

    test('清空全部时段会一并删除同步生成的批评记录', () {
      final provider = AppDataProvider();
      provider.setAttendance('张三', '迟到', date: '2026-09-26');
      provider.setAttendance('李四', '请假', date: '2026-09-26');

      final cleared = provider.clearAttendance('2026-09-26');

      expect(cleared, 2);
      expect(provider.getRecordsForDate('2026-09-26'), isEmpty);
    });

    test('同步映射可配置：自定义映射生效并把原因补进批评原因库', () {
      final provider = AppDataProvider();
      provider.setAttendanceSyncMap({'事假': '无故缺课'});

      provider.setAttendance('张三', '事假', date: '2026-09-26');

      final record = provider.getRecordsForDate('2026-09-26').single;
      expect(record.reasons, '无故缺课');
      expect(
        provider.appData.reasons.criticism['_common'],
        contains('无故缺课'),
      );
      // 原映射被替换：迟到不再生成记录
      provider.setAttendance('李四', '迟到', date: '2026-09-26');
      expect(provider.getRecordsForDate('2026-09-26').length, 1);
    });

    test('删除状态项会同时移除它的同步映射', () {
      final provider = AppDataProvider();

      provider.setAttendanceStatuses(['迟到', '请假']);

      expect(provider.attendanceSyncReasonFor('迟到'), '迟到');
      expect(provider.attendanceSyncReasonFor('早退'), isEmpty);
    });

    test('状态改名会同步映射的键', () {
      final provider = AppDataProvider();

      provider.renameAttendanceStatus('迟到', '迟到（早读）');

      expect(provider.attendanceSyncReasonFor('迟到（早读）'), '迟到');
      expect(provider.attendanceSyncReasonFor('迟到'), isEmpty);
    });
  });

  group('统计周期', () {
    test('每周起始日可往返，非法值回退', () {
      final settings = AppSettings(
        themeMode: ThemeModeType.system,
        weekStart: 7,
      );

      final restored = AppSettings.fromJson(settings.toJson());

      expect(restored.weekStart, 7);
      expect(AppSettings.fromJson({'weekStart': 9}).weekStart, 1);
    });
  });

  group('考勤表格与数据包', () {
    test('考勤表格导出后可原样解析（按日期从新到旧、同日按名单顺序）', () {
      final records = [
        const AttendanceRecord(
          id: 'a1',
          studentName: '张三',
          status: '迟到',
          date: '2026-09-25',
          timestamp: '08:00:00',
        ),
        const AttendanceRecord(
          id: 'a2',
          studentName: '李四',
          status: '请假',
          date: '2026-09-26',
          timestamp: '09:00:00',
        ),
        const AttendanceRecord(
          id: 'a3',
          studentName: '张三',
          status: '缺勤',
          date: '2026-09-26',
          timestamp: '10:00:00',
        ),
      ];

      final bytes = TransferService.buildAttendanceXlsx(records, ['张三', '李四']);
      final rows = TransferService.readRows(bytes, isCsv: false);
      final parsed = TransferService.parseAttendanceRows(rows).records;

      expect(parsed.length, 3);
      expect(parsed[0].date, '2026-09-26');
      expect(parsed[0].studentName, '张三');
      expect(parsed[1].studentName, '李四');
      expect(parsed[2].date, '2026-09-25');
      expect(parsed[0].status, '缺勤');
      expect(parsed[0].timestamp, '10:00:00');
      // 表格导入的记录没有 id，由数据层分配
      expect(parsed.every((record) => record.id.isEmpty), isTrue);
    });

    test('考勤表格导出导入保留记录人，“未记录”回导为空', () {
      final records = [
        const AttendanceRecord(
          id: 'a1',
          studentName: '张三',
          status: '迟到',
          date: '2026-09-26',
          timestamp: '08:00:00',
          recordedBy: '班长 · 王五',
        ),
        const AttendanceRecord(
          id: 'a2',
          studentName: '李四',
          status: '请假',
          date: '2026-09-26',
          timestamp: '09:00:00',
        ),
      ];

      final bytes = TransferService.buildAttendanceXlsx(records, ['张三', '李四']);
      final rows = TransferService.readRows(bytes, isCsv: false);
      expect(rows.first.contains('记录人'), isTrue);

      final parsed = TransferService.parseAttendanceRows(rows).records;
      final byName = {for (final record in parsed) record.studentName: record};
      expect(byName['张三']!.recordedBy, '班长 · 王五');
      expect(
        byName['李四']!.recordedBy,
        isEmpty,
        reason: '导出时的“未记录”回导后不能变成真实记录人',
      );
    });

    test('考勤表格解析：忽略表头、缺列与非法日期', () {
      final parsed = TransferService.parseAttendanceRows([
        ['日期', '学生姓名', '考勤状态', '登记时间'],
        ['2026-09-26', '张三', '迟到', '08:00:00'],
        ['2026-09-26', '', '迟到', ''],
        ['2026-09-26', '李四', '', ''],
        ['26/09/2026', '王五', '请假', ''],
        ['2026-09-26', '赵六', '缺勤', ''],
      ]).records;

      expect(parsed.length, 2);
      expect(parsed[0].studentName, '张三');
      expect(parsed[1].studentName, '赵六');
    });

    test('数据包包含考勤与状态项，可完整解析回来', () {
      final data = AppData(
        recordsByDate: {},
        settings: AppSettings(
          themeMode: ThemeModeType.dark,
          attendanceEnabled: true,
          attendanceStatuses: const ['迟到', '事假'],
        ),
        attendanceByDate: {
          '2026-09-26': [
            const AttendanceRecord(
              id: 'a1',
              studentName: '张三',
              status: '事假',
              date: '2026-09-26',
              timestamp: '08:30:00',
              recordedBy: '班长 · 王五',
            ),
          ],
        },
      );

      final parsed = TransferService.parsePackage(
        TransferService.buildPackage(data, exportedAt: '2026-09-26 10:00'),
      );

      expect(parsed, isNotNull);
      expect(parsed!.attendance.length, 1);
      expect(parsed.attendance.first.status, '事假');
      expect(parsed.attendance.first.recordedBy, '班长 · 王五');
      expect(parsed.attendanceStatuses, ['迟到', '事假']);
    });

    test('旧数据包没有考勤字段时：考勤为空、状态类字段为 null（保持本机）', () {
      final parsed = TransferService.parsePackage(
        jsonEncode({
          'format': TransferService.packageFormat,
          'version': TransferService.packageVersion,
          'students': ['张三'],
          'records': [],
        }),
      );

      expect(parsed, isNotNull);
      expect(parsed!.attendance, isEmpty);
      // 修复（审计 P2-33）：缺失字段解析为 null —— 导入时保持本机现值
      //（空列表/空映射才是"显式清空"，见 v230_audit_p2c_test）。
      expect(parsed.attendanceStatuses, isNull);
      expect(parsed.attendanceAbsentStatuses, isNull);
      expect(parsed.attendanceSyncMap, isNull);
    });
  });

  group('考勤状态配置导入导出', () {
    test('导出→解析往返：状态名/未到口径/同步原因', () async {
      final bytes = TransferService.buildAttendanceStatusesXlsx(
        ['迟到', '请假', '早退'],
        {'请假'},
        {'请假': '事假'},
      );
      final rows = await TransferService.readRowsAsync(
        bytes,
        isCsv: false,
        headerKeywords: const {'状态名称'},
      );
      final parsed = TransferService.parseAttendanceStatusRows(rows);
      expect(parsed.map((row) => row.name).toList(), ['迟到', '请假', '早退']);
      expect(parsed[1].absent, isTrue);
      expect(parsed[1].syncReason, '事假');
      expect(parsed[0].absent, isFalse);
    });

    test('非法状态名与重复行被跳过', () {
      final parsed = TransferService.parseAttendanceStatusRows([
        ['状态名称', '是否计为未到', '同步批评原因'],
        ['出勤', '是', ''],
        ['', '否', ''],
        ['迟到', '否', ''],
        ['迟到', '是', '迟到'],
      ]);
      expect(parsed, hasLength(1));
      expect(parsed.single.name, '迟到');
      expect(parsed.single.absent, isFalse);
    });
  });
}
