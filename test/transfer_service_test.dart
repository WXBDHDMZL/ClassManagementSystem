// 分类导入导出测试：名单 / 原因库 / 时间段 / 数据包 的序列化与解析往返。

import 'dart:convert';

import 'package:excel/excel.dart' as excel;
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/models/reason_library.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/services/transfer_service.dart';

void main() {
  tearDown(() => applyCustomPeriodLabels({}));

  test('名单导出后可原样解析回来', () {
    final bytes = TransferService.buildStudentsXlsx(['张三', '李四', '王五']);
    final names = TransferService.parseStudentsRows(
      TransferService.readRows(bytes, isCsv: false),
    );

    expect(names, ['张三', '李四', '王五']);
  });

  test('名单解析：没有表头时取第一列，忽略空行与重复', () {
    final rows = [
      ['张三'],
      [''],
      ['李四'],
      ['张三'],
    ];

    expect(TransferService.parseStudentsRows(rows), ['张三', '李四']);
  });

  test('原因库导出后可原样解析回来（含全时段通用）', () {
    final library = ReasonLibrary(
      praise: {
        'class': ['认真听讲'],
        '_common': ['主动帮助同学'],
      },
      criticism: {
        'class': ['迟到'],
      },
    );

    final bytes = TransferService.buildReasonsXlsx(library);
    final rows = TransferService.readRows(bytes, isCsv: false);
    final parsed = TransferService.parseReasonsRows(rows);

    expect(parsed.length, 3);
    expect(
      parsed.any(
        (row) =>
            row.operationType == '表扬' &&
            row.periodKey == 'class' &&
            row.reason == '认真听讲',
      ),
      isTrue,
    );
    expect(
      parsed.any(
        (row) =>
            row.operationType == '表扬' &&
            row.periodKey == '_common' &&
            row.reason == '主动帮助同学',
      ),
      isTrue,
    );
    expect(
      parsed.any(
        (row) =>
            row.operationType == '批评' &&
            row.periodKey == 'class' &&
            row.reason == '迟到',
      ),
      isTrue,
    );
  });

  test('原因库可组装回库（替换导入用）', () {
    final rows = [
      const ReasonImportRow(
        operationType: '表扬',
        periodKey: 'class',
        reason: '认真听讲',
      ),
      const ReasonImportRow(
        operationType: '批评',
        periodKey: 'noon_rest',
        reason: '午休说话',
      ),
    ];

    final library = TransferService.libraryFromRows(rows);

    expect(library.praise['class'], ['认真听讲']);
    expect(library.criticism['noon_rest'], ['午休说话']);
  });

  test('时间段导出后可原样解析，自定义标签优先', () {
    applyCustomPeriodLabels({'class': '08:10-12:00 第一课堂'});

    final bytes = TransferService.buildPeriodsXlsx();
    final periods = TransferService.parsePeriodsRows(
      TransferService.readRows(bytes, isCsv: false),
    );
    final byKey = {for (final item in periods) item['key']!: item['label']!};

    expect(byKey['class'], '08:10-12:00 第一课堂');
    expect(byKey['morning_reading'], getTimePeriodName('morning_reading'));
    // 出厂 9 段应全部解析出来，且顺序与导出一致。
    expect(periods.length, timePeriods.length);
    expect(periods.map((item) => item['key']).toList(), timePeriods.keys.toList());
  });

  test('时间段导出→导入能完整还原自定义新增的时段（闭环）', () {
    applyCustomPeriods(const [
      {'key': 'morning_reading', 'label': '07:00-08:00 早读'},
      {'key': 'custom_1', 'label': '19:00-19:30 晚点名'},
    ]);

    final bytes = TransferService.buildPeriodsXlsx();
    final periods = TransferService.parsePeriodsRows(
      TransferService.readRows(bytes, isCsv: false),
    );

    expect(periods.length, 2);
    expect(periods[1]['key'], 'custom_1');
    expect(periods[1]['label'], '19:00-19:30 晚点名');
  });

  test('数据包导出后可完整解析回来（含记录与名单，不含密码）', () {
    final record = StudentRecord(
      id: 'r1',
      studentName: '张三',
      operationType: '表扬',
      reasons: '认真听讲',
      periodKey: 'class',
      periodName: '上课',
      remark: '',
      timestamp: '08:30:00',
      isAppended: false,
      date: '2026-09-01',
    );
    final data = AppData(
      recordsByDate: {
        '2026-09-01': [record],
      },
      settings: AppSettings(
        themeMode: ThemeModeType.light,
        periodLabels: const {'class': '08:10-12:00 第一课堂'},
        passwordHash: 'should-not-export',
      ),
      students: ['张三', '李四'],
      reasons: ReasonLibrary(
        praise: {
          'class': ['认真听讲'],
        },
        criticism: {},
      ),
    );

    final text = TransferService.buildPackage(data, exportedAt: '2026-09-26 01:00');
    expect(text.contains('should-not-export'), isFalse);

    final parsed = TransferService.parsePackage(text);
    expect(parsed, isNotNull);
    expect(parsed!.records.length, 1);
    expect(parsed.records.first.studentName, '张三');
    expect(parsed.records.first.date, '2026-09-01');
    expect(parsed.students, ['张三', '李四']);
    expect(parsed.periodLabels['class'], '08:10-12:00 第一课堂');
    expect(parsed.reasons.praise['class'], ['认真听讲']);
    // 原因库可展开回导入行（合并导入用）
    final rows = TransferService.rowsOfLibrary(parsed.reasons);
    expect(rows.length, 1);
    expect(rows.first.reason, '认真听讲');
  });

  test('数据包解析：非本程序的文件返回 null，损坏记录被跳过', () {
    expect(TransferService.parsePackage('{"foo":1}'), isNull);
    expect(TransferService.parsePackage('not json'), isNull);

    final broken = jsonEncode({
      'format': TransferService.packageFormat,
      'version': 1,
      'students': ['张三'],
      'records': [
        {'id': 'r1'},
      ],
    });
    final parsed = TransferService.parsePackage(broken);
    expect(parsed, isNotNull);
    expect(parsed!.records, isEmpty);
    expect(parsed.students, ['张三']);
  });

  test('CSV 表格也能读取（复用记录导入的分隔解析）', () {
    const csv = '序号,姓名\n1,张三\n2,李四\n';
    final rows = TransferService.readRows(utf8.encode(csv), isCsv: true);

    expect(TransferService.parseStudentsRows(rows), ['张三', '李四']);
  });

  test('静态表头常量存在，避免与解析函数失配', () {
    // 时间段导出表头参与解析判断，做一次显式断言保护。
    final bytes = TransferService.buildPeriodsXlsx();
    final sheet = excel.Excel.decodeBytes(bytes).tables.values.first;
    expect(sheet.rows.first.first?.value.toString(), '时段');
  });

  test('CSV 解码：非 UTF-8 必须报错并给出"另存为 CSV UTF-8"的指引', () {
    // GBK 编码的"张三"（D5 C5 C8 FD）不是合法 UTF-8，之前用 allowMalformed
    // 会被静默解成乱码，用户只看到"没找到表头"，拿不到正确指引。
    expect(
      () => TransferService.decodeCsv(const [0xD5, 0xC5, 0xC8, 0xFD]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('UTF-8'), contains('另存为')),
        ),
      ),
    );
    // 带 BOM 的 UTF-8 应当正常解码并去掉 BOM。
    expect(TransferService.decodeCsv(const [0xEF, 0xBB, 0xBF, 0xE5, 0xBC, 0xA0, 0xE4, 0xB8, 0x89]), '张三');
  });

  test('考勤导入：列顺序被调整后仍按表头正确识别', () {
    final rows = [
      ['考勤状态', '日期', '学生姓名', '登记时间', '时间段'],
      ['请假', '2026-09-01', '张三', '08:00:00', '全天'],
      ['迟到', '2026-09-01', '李四', '08:05:00', '早读'],
    ];

    final records = TransferService.parseAttendanceRows(rows).records;

    expect(records.length, 2);
    expect(records.first.studentName, '张三');
    expect(records.first.date, '2026-09-01');
    expect(records.first.status, '请假');
    expect(records.first.periodKey, AttendanceRecord.allDayKey);
    expect(records[1].studentName, '李四');
    expect(records[1].periodKey, 'morning_reading');
  });

  test('考勤导入：没有表头时仍按旧固定列序兼容', () {
    final rows = [
      ['2026-09-01', '张三', '缺勤'],
    ];

    final records = TransferService.parseAttendanceRows(rows).records;

    expect(records.length, 1);
    expect(records.first.periodKey, AttendanceRecord.allDayKey);
    expect(records.first.status, '缺勤');
  });
}
