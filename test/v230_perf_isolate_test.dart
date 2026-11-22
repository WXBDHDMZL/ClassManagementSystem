// 性能批（H4）回归测试：Excel 解析与导出编码的 Isolate 版本。
// 覆盖三件事：① 与同步版结果完全一致；② 异常（FormatException）能跨 isolate
// 原样透传给界面兜底；③ 跨 isolate 传递性守卫（Workbook / ImportPreview /
// StudentRecord 的发送性一旦被升级破坏，这里会第一时间失败）。

import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as excel;
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/services/excel_export.dart';
import 'package:class_management_system/services/import_service.dart';
import 'package:class_management_system/services/transfer_service.dart';

import 'test_helpers.dart';

StudentRecord _record({
  String id = 'r1',
  String name = '张三',
  String type = '表扬',
  String reason = '认真听讲',
  String periodKey = 'class',
  String timestamp = '12:00:00',
  String remark = '',
  String date = '2026-09-20',
}) =>
    StudentRecord(
      id: id,
      studentName: name,
      operationType: type,
      reasons: reason,
      periodKey: periodKey,
      periodName: '',
      remark: remark,
      timestamp: timestamp,
      isAppended: false,
      isImported: true,
      date: date,
    );

excel.Excel _recordWorkbook() {
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
    excel.TextCellValue('上课'),
    excel.TextCellValue('12:00:00'),
    excel.TextCellValue(''),
  ]);
  return book;
}

/// 解码 xlsx 字节为"工作表名 → 各行文本"，用于内容等价断言。
Map<String, List<String>> _sheetTextOf(List<int> bytes) {
  final book = excel.Excel.decodeBytes(bytes);
  return {
    for (final name in book.tables.keys)
      name: [
        for (final row in book.tables[name]!.rows)
          row.map((cell) => cell?.value?.toString() ?? '').join('|'),
      ],
  };
}

void main() {
  group('readRowsAsync（H4：导入解码放后台）', () {
    test('xlsx：与同步版结果一致，且表头关键词选表逻辑相同', () async {
      final book = ExcelExport.newWorkbook();
      book['说明页'].appendRow([excel.TextCellValue('本文件为导出说明')]);
      final data = book['数据'];
      data.appendRow([
        excel.TextCellValue('日期'),
        excel.TextCellValue('学生姓名'),
      ]);
      data.appendRow([
        excel.TextCellValue('2026-09-20'),
        excel.TextCellValue('张三'),
      ]);
      final bytes = ExcelExport.encodeWorkbook(book);

      final sync = TransferService.readRows(
        bytes,
        isCsv: false,
        headerKeywords: const {'学生姓名'},
      );
      final asyncRows = await TransferService.readRowsAsync(
        bytes,
        isCsv: false,
        headerKeywords: const {'学生姓名'},
      );

      expect(asyncRows, sync, reason: '异步版必须与同步版逐格一致');
      expect(asyncRows.first, ['日期', '学生姓名'], reason: '应按关键词选中"数据"表');
    });

    test('csv：与同步版结果一致（含引号与换行字段）', () async {
      final bytes = utf8.encode('姓名,备注\r\n张三,"含,逗号"\r\n李四,普通\r\n');

      expect(
        await TransferService.readRowsAsync(bytes, isCsv: true),
        TransferService.readRows(bytes, isCsv: true),
      );
    });

    test('非 UTF-8 CSV 的 FormatException 跨 isolate 透传且保留引导文案', () async {
      // "张三" 的 GBK 字节：utf8.decode 必然失败（模拟 Excel 默认另存的 ANSI CSV）。
      final gbkBytes = <int>[0xD5, 0xC5, 0xC8, 0xFD, 0x2C, 0x41];

      try {
        await TransferService.readRowsAsync(gbkBytes, isCsv: true);
        fail('非 UTF-8 CSV 应当抛出 FormatException');
      } on FormatException catch (e) {
        expect(
          e.message,
          contains('CSV UTF-8'),
          reason: '界面依赖该文案给出"另存为 CSV UTF-8"的指引，跨 isolate 后必须保留',
        );
      }
    });
  });

  group('parseExcelBytesAsync / parseCsvTextAsync（H4：记录导入解析放后台）', () {
    test('xlsx：新记录解析结果与同步版一致（ImportPreview 可跨 isolate 返回）', () async {
      final bytes = ExcelExport.encodeWorkbook(_recordWorkbook());

      final sync = ImportService.parseExcelBytes(bytes, existing: const []);
      final asyncPreview = await ImportService.parseExcelBytesAsync(
        bytes,
        existing: const [],
      );

      expect(asyncPreview.hasError, sync.hasError);
      expect(asyncPreview.records.length, sync.records.length);
      final record = asyncPreview.records.single;
      expect(record.studentName, '张三');
      expect(record.operationType, '表扬');
      expect(record.date, '2026-09-20');
      expect(record.periodKey, 'class');
      expect(record.isImported, isTrue);
    });

    test('xlsx：判重同样生效（existing 记录可跨 isolate 传入）', () async {
      final bytes = ExcelExport.encodeWorkbook(_recordWorkbook());
      final existing = [_record()];

      final preview = await ImportService.parseExcelBytesAsync(
        bytes,
        existing: existing,
      );

      expect(preview.records, isEmpty, reason: '与现有记录重复，不应新增');
      expect(preview.duplicates, hasLength(1));
      expect(preview.duplicateImports, hasLength(1));
    });

    test('csv：与同步版结果一致', () async {
      const csv = '日期,学生姓名,操作项目,原因,时间段,时间,备注\n'
          '2026-09-20,张三,表扬,认真听讲,上课,12:00:00,\n';
      final existing = [_record(timestamp: '09:00:00')];

      final sync = ImportService.parseCsvText(csv, existing: existing);
      final asyncPreview = await ImportService.parseCsvTextAsync(
        csv,
        existing: existing,
      );

      expect(asyncPreview.records.length, sync.records.length);
      expect(asyncPreview.records.single.studentName, '张三');
    });
  });

  group('encodeWorkbookAsync（H4：导出编码放后台）', () {
    test('编码结果可解码且内容与同步版一致（Workbook 发送性守卫）', () async {
      final book = _recordWorkbook();

      final bytes = await ExcelExport.encodeWorkbookAsync(book);
      final decoded = excel.Excel.decodeBytes(bytes);

      expect(decoded.tables.keys, contains('Sheet1'));
      final header = decoded.tables['Sheet1']!.rows.first
          .map((cell) => cell?.value?.toString() ?? '')
          .toList();
      expect(header, ['日期', '学生姓名', '操作项目', '原因', '时间段', '时间', '备注']);
      expect(_sheetTextOf(bytes), _sheetTextOf(ExcelExport.encodeWorkbook(book)));
    });

    test('saveWorkbook 端到端：编码隔离后仍能正确落盘', () async {
      final dir = Directory.systemTemp.createTempSync('cms_perf_iso');
      addTearDown(() => deleteDirectoryWithRetry(dir));

      final book = _recordWorkbook();
      final path = await ExcelExport.saveWorkbook(
        book,
        baseName: '性能测试导出',
        exportPath: dir.path,
      );

      expect(path, isNotNull);
      final file = File(path!);
      expect(file.existsSync(), isTrue);
      final decoded = excel.Excel.decodeBytes(file.readAsBytesSync());
      expect(decoded.tables.keys, contains('Sheet1'));
    });
  });

  group('buildRecordsXlsxAsync / buildAttendanceXlsxAsync（H4：自动导出与考勤导出）', () {
    test('全部记录：异步产出与同步版内容一致', () async {
      final records = [
        _record(id: 'r1'),
        _record(
          id: 'r2',
          name: '李四',
          type: '批评',
          reason: '迟到',
          periodKey: 'morning_reading',
          date: '2026-09-21',
        ),
      ];

      final asyncBytes = await TransferService.buildRecordsXlsxAsync(records);

      expect(
        _sheetTextOf(asyncBytes),
        _sheetTextOf(TransferService.buildRecordsXlsx(records)),
      );
    });

    test('考勤：异步产出可解码且行数与记录数一致', () async {
      final records = [
        const AttendanceRecord(
          id: '',
          studentName: '张三',
          status: '请假',
          date: '2026-09-20',
          periodKey: 'all_day',
          timestamp: '08:00:00',
        ),
        const AttendanceRecord(
          id: '',
          studentName: '李四',
          status: '迟到',
          date: '2026-09-20',
          periodKey: 'all_day',
          timestamp: '08:05:00',
        ),
      ];

      final bytes = await TransferService.buildAttendanceXlsxAsync(records, const [
        '张三',
        '李四',
      ]);

      final sheet = excel.Excel.decodeBytes(bytes).tables['Sheet1']!;
      expect(sheet.rows.length, records.length + 1, reason: '表头 + 每条考勤一行');
      expect(
        sheet.rows[1].map((cell) => cell?.value?.toString() ?? '').join('|'),
        contains('张三'),
      );
    });
  });

  group('buildStudentsXlsxAsync（H4 收口）', () {
    // 该小表不依赖时段全局态，纯内容级断言即可；时段敏感的
    // 原因库/时间段两个导出在 v230_period_isolate_test.dart 里另有判别式守卫。
    test('名单：异步产出含序号与姓名', () async {
      final bytes =
          await TransferService.buildStudentsXlsxAsync(['张三', '李四']);

      final lines = _sheetTextOf(bytes)['Sheet1']!;
      expect(lines.first, '序号|姓名');
      expect(lines[1], '1|张三');
      expect(lines[2], '2|李四');
    });
  });
}
