// 时段快照跨 isolate 回归（性能批 H4 的 P0 后续）。
//
// 为什么需要这个文件：v230_perf_isolate_test.dart 的对拍断言**恰好掩盖**了
// "Isolate.run 丢失时段全局态"这个 bug —— 测试进程里从未调用过
// applyCustomPeriods，主 isolate 与后台 isolate 两侧都是出厂值，
// "同步 == 异步"自然成立，而真实用户用的是自定义时段。
//
// 这里反过来做：先装入**非出厂**时段，再对拍，并断言**具体期望值**
// （而不是只断言两侧一致），因此任何一侧丢态都会立刻失败。

import 'dart:convert';

import 'package:excel/excel.dart' as excel;
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/models/reason_library.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/services/excel_export.dart';
import 'package:class_management_system/services/import_service.dart';
import 'package:class_management_system/services/transfer_service.dart';

/// 非出厂时段：key 与出厂完全不同，标签也不在任何出厂表里，
/// 因此"退回出厂值"必然表现为可辨识的差异（而不是碰巧一致）。
const String kCustomKey = 'custom_a';
const String kCustomLabel = '08:00-09:00 自定义第一节';

/// 装入自定义时段。sanitizePeriods 只做校验/去重，不会吞掉这条合法标签。
void _installCustomPeriods() {
  applyCustomPeriods([
    {'key': kCustomKey, 'label': kCustomLabel},
  ]);
}

/// 解码 xlsx 为"工作表名 → 各行以 | 拼接的文本"，用于内容级断言。
Map<String, List<String>> _sheetTextOf(List<int> bytes) {
  final book = excel.Excel.decodeBytes(bytes);
  return {
    for (final name in book.tables.keys)
      name: [
        for (final row in book.tables[name]!.rows)
          row.map((c) => c?.value?.toString() ?? '').join('|'),
      ],
  };
}

StudentRecord _record({
  String id = 'r1',
  String name = '张三',
  String type = '表扬',
  String reason = '认真听讲',
  String periodKey = kCustomKey,
  String timestamp = '12:00:00',
  String date = '2026-09-20',
}) =>
    StudentRecord(
      id: id,
      studentName: name,
      operationType: type,
      reasons: reason,
      periodKey: periodKey,
      // 存空的显示名：强制导出侧必须靠时段表解析出名称，
      // 一旦isolate 丢了全局态就会回退成裸 key（custom_a）。
      periodName: '',
      remark: '',
      timestamp: timestamp,
      isAppended: false,
      isImported: true,
      date: date,
    );

excel.Excel _recordWorkbook(String periodCell) {
  final book = ExcelExport.newWorkbook();
  final sheet = book['Sheet1'];
  sheet.appendRow([
    excel.TextCellValue('日期'),
    excel.TextCellValue('学生姓名'),
    excel.TextCellValue('操作项目'),
    excel.TextCellValue('原因'),
    excel.TextCellValue('时间段'),
    excel.TextCellValue('时间'),
    excel.TextCellValue('备注'),
  ]);
  sheet.appendRow([
    excel.TextCellValue('2026-09-20'),
    excel.TextCellValue('张三'),
    excel.TextCellValue('表扬'),
    excel.TextCellValue('认真听讲'),
    excel.TextCellValue(periodCell),
    excel.TextCellValue('12:00:00'),
    excel.TextCellValue(''),
  ]);
  return book;
}

void main() {
  // G-19：时段是模块级全局态，用例之间必须显式清理，否则会串态。
  tearDown(resetPeriodsForTest);

  group('记录导入：自定义时段必须跨 isolate 还原（parseCsv/parseExcel）', () {
    test('csv：异步版仍能按自定义时段反查到 key，并写回完整标签', () async {
      _installCustomPeriods();
      const csv = '日期,学生姓名,操作项目,原因,时间段,时间,备注\n'
          '2026-09-20,张三,表扬,认真听讲,$kCustomLabel,12:00:00,\n';

      final preview = await ImportService.parseCsvTextAsync(
        csv,
        existing: const [],
      );

      expect(preview.hasError, isFalse);
      final record = preview.records.single;
      // 断言具体期望值：key 要能反查到自定义 key。
      expect(
        record.periodKey,
        kCustomKey,
        reason: '后台 isolate 丢了时段全局态时，这里会得到空串',
      );
      // periodName 也要是解析出的名称，而不是把原文照抄。
      expect(record.periodName, kCustomLabel);
    });

    test('csv：简称同样能反查（走 getTimePeriodShortName 的同一口径）', () async {
      _installCustomPeriods();
      const csv = '日期,学生姓名,操作项目,原因,时间段,时间,备注\n'
          '2026-09-20,张三,表扬,认真听讲,自定义第一节,12:00:00,\n';

      final preview = await ImportService.parseCsvTextAsync(
        csv,
        existing: const [],
      );

      expect(preview.records.single.periodKey, kCustomKey);
    });

    test('xlsx：异步版与同步版都解析成同一个自定义 key', () async {
      _installCustomPeriods();
      final bytes = ExcelExport.encodeWorkbook(_recordWorkbook(kCustomLabel));

      final sync = ImportService.parseExcelBytes(bytes, existing: const []);
      final asyncPreview = await ImportService.parseExcelBytesAsync(
        bytes,
        existing: const [],
      );

      expect(sync.records.single.periodKey, kCustomKey,
          reason: '前置条件：同步侧必须先解析成功，否则本用例没有判别力');
      expect(asyncPreview.records.single.periodKey, kCustomKey);
      expect(asyncPreview.records.single.periodName, kCustomLabel);
    });

    test('导入→导出闭环：自定义时段经异步导入后再异步导出，key 与名称都不丢', () async {
      _installCustomPeriods();
      const csv = '日期,学生姓名,操作项目,原因,时间段,时间,备注\n'
          '2026-09-20,张三,表扬,认真听讲,$kCustomLabel,12:00:00,\n';

      final preview = await ImportService.parseCsvTextAsync(
        csv,
        existing: const [],
      );
      // 前置断言：闭环用例的有效性完全依赖导入侧先还原出 periodKey。
      // 少了这一步，导入侧丢态会退化成"空key + 原样保留 periodName"，
      // 导出侧照样显示正确名称 —— 用例就变成了假通过（实测已踩过）。
      expect(preview.records.single.periodKey, kCustomKey);

      final bytes = await TransferService.buildRecordsXlsxAsync(
        preview.records,
      );
      final text = _sheetTextOf(bytes)['Sheet1']!;

      expect(
        text.any((line) => line.contains(kCustomLabel)),
        isTrue,
        reason: '导出应显示时段名称；丢态时会导出裸 key $kCustomKey',
      );
      expect(text.any((line) => line.contains(kCustomKey)), isFalse);
    });
  });

  group('导出：自定义时段名必须跨 isolate 解析（buildRecords/buildAttendance）', () {
    test('全部记录导出：时段列是名称而不是裸 key', () async {
      _installCustomPeriods();
      final records = [_record()];

      final bytes = await TransferService.buildRecordsXlsxAsync(records);
      final row = _sheetTextOf(bytes)['Sheet1']![1];

      expect(
        row,
        contains(kCustomLabel),
        reason: 'periodNameForRecord 需在 isolate 内解析出自定义名称',
      );
      expect(row, isNot(contains(kCustomKey)));
    });

    test('考勤导出：时间段列是名称而不是裸 key', () async {
      _installCustomPeriods();
      final records = [
        const AttendanceRecord(
          id: '',
          studentName: '张三',
          status: '请假',
          date: '2026-09-20',
          periodKey: kCustomKey,
          timestamp: '08:00:00',
        ),
      ];

      final bytes = await TransferService.buildAttendanceXlsxAsync(
        records,
        const ['张三'],
      );
      final row = _sheetTextOf(bytes)['Sheet1']![1];

      expect(row, contains(kCustomLabel));
      expect(row, isNot(contains(kCustomKey)));
    });

    test('已删除时段回退到记录里保存的名称（不暴露裸 key）', () async {
      _installCustomPeriods();
      // periodKey 不在当前生效时段里（模拟用户删掉了该时段），
      // 记录自带 periodName —— 验证 P2-32 的回退口径在 isolate 内同样成立。
      final records = [
        StudentRecord(
          id: 'r1',
          studentName: '张三',
          operationType: '表扬',
          reasons: '认真听讲',
          periodKey: 'ghost_key',
          periodName: '历史时段名',
          remark: '',
          timestamp: '12:00:00',
          isAppended: false,
          isImported: true,
          date: '2026-09-20',
        ),
      ];

      final bytes = await TransferService.buildRecordsXlsxAsync(records);
      final row = _sheetTextOf(bytes)['Sheet1']![1];

      expect(row, contains('历史时段名'));
      expect(row, isNot(contains('ghost_key')));
    });
  });

  group('加固：readRowsAsync / encodeWorkbookAsync 明确不依赖时段态', () {
    test('readRowsAsync：自定义时段名原样透传（证明它确实不碰时段表）', () async {
      _installCustomPeriods();
      final csv = utf8.encode('姓名,时间段\r\n张三,$kCustomLabel\r\n');

      final rows = await TransferService.readRowsAsync(csv, isCsv: true);

      // 期望值是"原文透传"，而不是被反查成 key —— 说明 readRows 链路上
      // 没有 matchTimePeriodKey / getTimePeriodName 这类全局态读取。
      expect(rows[1][1], kCustomLabel);
    });

    test('encodeWorkbookAsync：内容与同步版一致（编码层与时段无关）', () async {
      _installCustomPeriods();
      final book = _recordWorkbook(kCustomLabel);

      final bytes = await ExcelExport.encodeWorkbookAsync(book);

      expect(
        _sheetTextOf(bytes),
        _sheetTextOf(ExcelExport.encodeWorkbook(book)),
      );
    });
  });

  group('补收口（H4 残留）：原因库/时间段导出异步化后仍带自定义时段', () {
    // 这两个小表原本一直同步，收口时同样把编码移入 isolate —— 与 records/
    // attendance 一样，时段快照必须在主 isolate 侧取，这里就是那条守卫。
    test('原因库导出：时段列是自定义名称而不是裸 key', () async {
      _installCustomPeriods();
      final library = ReasonLibrary(
        praise: {
          kCustomKey: ['理由甲'],
        },
        criticism: <String, List<String>>{},
      );

      final bytes = await TransferService.buildReasonsXlsxAsync(library);
      final lines = _sheetTextOf(bytes)['Sheet1']!;

      expect(
        lines.any((line) => line.contains(kCustomLabel)),
        isTrue,
        reason: '后台 isolate 丢时段态时，"时段"列会写出裸 key $kCustomKey',
      );
      expect(lines.any((line) => line.contains(kCustomKey)), isFalse);
    });

    test('时间段导出：导出的是自定义时段整体（不是出厂 9 段）', () async {
      _installCustomPeriods();

      final bytes = await TransferService.buildPeriodsXlsxAsync();
      final lines = _sheetTextOf(bytes)['Sheet1']!;

      expect(
        lines.length,
        2,
        reason: '表头 + 仅自定义的一段；丢态时会变成出厂 9 段（10 行）',
      );
      expect(lines[1], contains(kCustomKey));
      expect(lines[1], contains(kCustomLabel));
    });
  });

  group('前置条件守卫：确保本文件真的有判别力', () {
    test('主 isolate 内自定义时段确实生效，且与出厂值不同', () {
      _installCustomPeriods();

      expect(matchTimePeriodKey(kCustomLabel), kCustomKey);
      expect(matchTimePeriodKey('自定义第一节'), kCustomKey);
      // 若这一条失败，说明测试环境本身没装上自定义时段，
      // 下面所有"对拍"用例会退化成两侧都是出厂值而失去意义。
      expect(effectivePeriods().any((p) => p['key'] == kCustomKey), isTrue);
      expect(getTimePeriodName(kCustomKey), kCustomLabel);
    });

    test('resetPeriodsForTest 能把状态清回出厂（防用例串态）', () {
      _installCustomPeriods();
      expect(matchTimePeriodKey(kCustomLabel), kCustomKey);

      resetPeriodsForTest();

      expect(
        matchTimePeriodKey(kCustomLabel),
        '',
        reason: '清理失败会让本文件其它用例带着脏状态跑',
      );
      expect(effectivePeriods().any((p) => p['key'] == kCustomKey), isFalse);
    });

    test('sanitizePeriods 幂等（方案 B 在 isolate 内重建状态的前提）', () {
      final once = sanitizePeriods([
        {'key': kCustomKey, 'label': kCustomLabel},
      ]);
      final twice = sanitizePeriods(once);

      expect(twice, once, reason: '重复过滤不应把合法标签吞掉');
      expect(twice.single['label'], kCustomLabel);
    });
  });
}
