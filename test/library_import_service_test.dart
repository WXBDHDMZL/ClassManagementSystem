/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.1
 * 创建日期 (Created): 2026-11-21
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';

import 'package:class_management_system/models/reason_library.dart';
import 'package:class_management_system/services/library_import_service.dart';
import 'package:class_management_system/services/transfer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('原因库文本解析', () {
    test('三列与两列混用：两列归入全时段通用', () {
      final preview = LibraryImportService.parseReasonsText(
        '表扬\t08:00-12:30、14:00-16:40 上课\t认真听课\n'
        '批评,早读,追逐打闹\n'
        '表扬,主动帮忙\n',
      );

      expect(preview.rows.length, 3);
      expect(preview.praiseCount, 2);
      expect(preview.criticismCount, 1);
      expect(preview.skipped, 0);
      expect(preview.rows[0].operationType, '表扬');
      expect(preview.rows[0].reason, '认真听课');
      expect(preview.rows[1].operationType, '批评');
      expect(preview.rows[2].periodKey, '_common');
    });

    test('无效类型与空原因计入跳过', () {
      final preview = LibraryImportService.parseReasonsText(
        '表扬\t08:00-12:30、14:00-16:40 上课\t认真听课\n'
        '其它\t08:00-12:30、14:00-16:40 上课\t无效类型\n'
        '批评\t08:00-12:30、14:00-16:40 上课\t\n',
      );

      expect(preview.rows.length, 1);
      expect(preview.skipped, 2);
    });

    test('两列空格写法也能识别', () {
      final preview = LibraryImportService.parseReasonsText('批评 上课讲话');
      expect(preview.rows.length, 1);
      expect(preview.rows.single.operationType, '批评');
      expect(preview.rows.single.reason, '上课讲话');
    });
  });

  group('原因库文件解析', () {
    test('CSV 文件按类型/时段/原因读取', () async {
      final bytes = utf8.encode(
        '类型,时段,原因\n表扬,上课,认真听课\n批评,早读,追逐打闹\n',
      );
      final preview = await LibraryImportService.parseReasonsFile(
        bytes: bytes,
        fileName: 'reasons.csv',
      );

      expect(preview.rows.length, 2);
      expect(preview.skipped, 0);
    });

    test('XLSX 导出文件可原样读回', () async {
      final library = ReasonLibrary(
        praise: {
          '_common': ['认真听课'],
          'class': ['积极发言'],
        },
        criticism: const {},
      );
      final bytes = TransferService.buildReasonsXlsx(library);
      final preview = await LibraryImportService.parseReasonsFile(
        bytes: bytes,
        fileName: 'reasons.xlsx',
      );

      expect(preview.rows.length, 2);
      expect(preview.praiseCount, 2);
    });

    test('不支持的扩展名给出明确提示', () async {
      expect(
        () => LibraryImportService.parseReasonsFile(
          bytes: const [1, 2, 3],
          fileName: 'reasons.docx',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('时段文本解析', () {
    test('key + 标签与只写标签混用', () {
      final preview = LibraryImportService.parsePeriodsText(
        'morning_reading\t07:00-08:00 早读\n'
        '08:00-12:30、14:00-16:40 上课\n',
      );

      expect(preview.periods.length, 2);
      expect(preview.periods[0]['key'], 'morning_reading');
      expect(preview.periods[0]['label'], '07:00-08:00 早读');
      expect(preview.periods[1]['label'], '08:00-12:30、14:00-16:40 上课');
      expect(preview.periods[1]['key'], 'class');
      expect(preview.skipped, 0);
    });

    test('空标签计入跳过', () {
      final preview = LibraryImportService.parsePeriodsText(
        'morning_reading\t\n'
        'class\t08:00-12:30、14:00-16:40 上课\n',
      );

      expect(preview.periods.length, 1);
      expect(preview.skipped, 1);
    });
  });

  group('时段文件解析', () {
    test('XLSX 导出文件可原样读回并保留顺序', () async {
      final source = [
        {'key': 'class', 'label': '08:00-12:30、14:00-16:40 上课'},
        {'key': 'custom_x', 'label': '19:00-21:30 晚自习'},
      ];
      final bytes = TransferService.buildPeriodsXlsx(source);
      final preview = await LibraryImportService.parsePeriodsFile(
        bytes: bytes,
        fileName: 'periods.xlsx',
      );

      expect(preview.periods.length, 2);
      expect(preview.periods[0]['key'], 'class');
      expect(preview.periods[1]['key'], 'custom_x');
      expect(preview.periods[1]['label'], '19:00-21:30 晚自习');
    });
  });
}
