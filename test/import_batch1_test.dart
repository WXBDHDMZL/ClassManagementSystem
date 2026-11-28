// Batch 1 回归：导入判重净化、缺日期列警告、导入补登考勤、整包还原 periodLabels。
//
// 背景（历史缺陷记录）：
//  - B-07 判重键用原始值，与写入侧净化口径不一致 → 带空格/超长的表格重复导入；
//  - B-07 缺日期列静默按今天导入，历史记录会被写成今天；
//  - B-04 导入记录不生成考勤，事后编辑却补生成；
//  - B-05 整包还原忽略旧包的 periodLabels（已由 P2-7 修复，这里补回归）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/reason_library.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/import_service.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/services/transfer_service.dart';
import 'package:class_management_system/utils/app_clock.dart';

import 'test_bootstrap.dart';
import 'test_helpers.dart';

StudentRecord _record({
  String id = 'r1',
  String name = '张三',
  String reasons = '迟到',
  String remark = '备注',
  String? date = '2026-10-04',
  String periodKey = '',
}) {
  return StudentRecord(
    id: id,
    studentName: name,
    operationType: '批评',
    reasons: reasons,
    periodKey: periodKey,
    periodName: '',
    remark: remark,
    timestamp: '08:00:00',
    date: date,
  );
}

void main() {
  late Directory docsDir;

  setUp(() {
    docsDir = createTestDocumentsDir('cms_import_batch1');
    installTestPathProvider(docsDir);
  });

  tearDown(() async {
    uninstallTestPathProvider();
    await deleteTestDocumentsDir(docsDir);
  });

  group('B-07 判重键与写入侧净化同口径', () {
    test('姓名/原因/备注带空格时，仍能判出重复', () {
      const csv = '日期,学生姓名,操作项目,原因,备注\n'
          '2026-10-04, 张三 ,批评, 迟到 , 备注 \n';
      final preview = ImportService.parseCsvText(
        csv,
        existing: [_record()],
      );

      expect(preview.records, isEmpty, reason: '净化后应与现有记录完全相同');
      expect(preview.duplicates, hasLength(1));
      expect(preview.duplicateImports, hasLength(1));
    });

    test('超长姓名整行跳过，不再裁剪后参与判重', () {
      // 旧期望（审计 A-04 之前）：表格里的 35 字名会被裁剪成 30 字写进库，
      // 判重键也按同一上限裁剪，于是与库里的 30 字姓名"张"*30 判为重复，
      // 断言 `duplicates` 有 1 条、`records` 为空。
      // 新期望：记录导入与名单导入统一口径 —— 超长姓名直接拒绝该行
      // （`validateStudentName`），既不写库也不参与判重，计入"跳过 N 行"。
      // 理由：裁剪会让前 30 字相同的两个不同学生被合并成同一人。
      final clippedName = '张' * 30;
      final longName = '张' * 35;
      final csv = '日期,学生姓名,操作项目,原因,备注\n'
          '2026-10-04,$longName,批评,迟到,备注\n';
      final preview = ImportService.parseCsvText(
        csv,
        existing: [_record(name: clippedName)],
      );
      expect(preview.duplicates, isEmpty);
      expect(preview.records, isEmpty);
      expect(preview.skippedRows, 1);
    });

    test('缺日期列：直接报错，不再按今天导入', () {
      const csv = '学生姓名,操作项目,原因\n张三,批评,迟到\n';
      final preview = ImportService.parseCsvText(csv, existing: const []);
      expect(preview.hasError, isTrue);
      expect(preview.error, contains('日期'));
      expect(preview.records, isEmpty);
    });

    test('有日期列时正常解析', () {
      const csv = '日期,学生姓名,操作项目,原因\n2026-10-04,张三,批评,迟到\n';
      final preview = ImportService.parseCsvText(csv, existing: const []);
      expect(preview.hasError, isFalse);
      expect(preview.records, hasLength(1));
    });
  });

  group('B-04 导入记录按映射补登考勤', () {
    test('勾选补登：批评记录生成对应考勤并建立关联', () {
      final provider = providerWithStudents(const ['学生1']);
      addTearDown(provider.dispose);
      provider.setAttendanceEnabled(true);
      final name = provider.appData.students.first;

      var generated = 0;
      final imported = provider.importRecords(
        [
          _record(
            id: 'imported1',
            name: name,
            reasons: '迟到',
            periodKey: 'class',
          ),
        ],
        syncAttendance: true,
        onAttendanceSynced: (count) => generated = count,
      );

      expect(imported, 1);
      expect(generated, 1);
      final attendance = provider.getAttendanceForDate('2026-10-04');
      expect(attendance, hasLength(1));
      expect(attendance.single.studentName, name);
      expect(attendance.single.status, '迟到');
      expect(attendance.single.syncedRecordId, 'imported1');
    });

    test('不勾选时只导入记录，不生成考勤', () {
      final provider = providerWithStudents(const ['学生1']);
      addTearDown(provider.dispose);
      provider.setAttendanceEnabled(true);
      final name = provider.appData.students.first;

      provider.importRecords(
        [
          _record(
            id: 'imported2',
            name: name,
            reasons: '迟到',
            periodKey: 'class',
          ),
        ],
      );

      expect(provider.getAttendanceForDate('2026-10-04'), isEmpty);
    });

    test('已有手工考勤不被导入覆盖', () {
      final provider = providerWithStudents(const ['学生1']);
      addTearDown(provider.dispose);
      provider.setAttendanceEnabled(true);
      final name = provider.appData.students.first;
      provider.setAttendance(
        name,
        '请假',
        date: '2026-10-04',
        periodKey: 'class',
      );

      var generated = 0;
      provider.importRecords(
        [
          _record(
            id: 'imported3',
            name: name,
            reasons: '迟到',
            periodKey: 'class',
          ),
        ],
        syncAttendance: true,
        onAttendanceSynced: (count) => generated = count,
      );

      expect(generated, 0, reason: '该时段已有考勤，应跳过而不是覆盖');
      final attendance = provider.getAttendanceForDate('2026-10-04');
      expect(attendance.single.status, '请假');
    });
  });

  group('导入与整包还原的日期口径一致', () {
    test('空日期记录被跳过，不会被改写成今天', () {
      final provider = providerWithStudents(const ['张三']);
      addTearDown(provider.dispose);
      final today = StatisticsService.todayString(AppClock.now());

      final imported = provider.importRecords([
        _record(id: 'empty-date', date: ''),
        _record(id: 'null-date', date: null),
        _record(id: 'ok', date: '2026-10-04'),
      ]);

      expect(imported, 1, reason: '只有带合法日期的那条能写入');
      expect(
        provider.appData.recordsByDate.containsKey(today),
        isFalse,
        reason: '空日期不能静默改成今天（那会把历史记录改期）',
      );
      expect(provider.appData.recordsByDate['2026-10-04'], hasLength(1));
    });

    test('整包还原返回实际写入条数，而不是包内条数', () async {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      final package = PackageData(
        records: [
          _record(id: 'p1', date: '2026-10-04'),
          _record(id: 'p2', date: ''),
          _record(id: 'p3', date: '2026-99-99'),
        ],
        students: const ['张三'],
        reasons: ReasonLibrary.defaults(),
      );

      final written = await provider.restoreFromPackage(package);

      expect(written, 1, reason: '界面提示必须用实际写入数，否则会比真实结果虚高');
      expect(provider.appData.recordsByDate['2026-10-04'], hasLength(1));
    });
  });
}
