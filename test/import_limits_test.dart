/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-11-28
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/import_limits.dart';
import 'package:class_management_system/services/import_service.dart';
import 'package:class_management_system/services/student_import_service.dart';
import 'package:class_management_system/services/transfer_service.dart';
import 'package:class_management_system/services/xlsx_reader.dart';

/// 审计 A-08：导入体积/解压量/行数上限。
///
/// 真实阈值（20 MB 文件、80 MB 解压、5000 条目、20000 行）造不出对应体量的
/// 样本，所以用 [ImportLimits.debugLowerLimits] 把阈值临时调低，验证"超限必须
/// 抛错而不是静默截断"，并顺带验证默认阈值本身的数值与边界（等于上限放行、
/// 多 1 字节拒绝）。
void main() {
  Uint8List buildZip(Map<String, List<int>> files) {
    final archive = Archive();
    files.forEach((name, data) {
      archive.addFile(ArchiveFile(name, data.length, data));
    });
    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded ?? const <int>[]);
  }

  tearDown(ImportLimits.debugResetLimits);

  group('阈值常量与边界', () {
    test('默认阈值是文档化的整数值', () {
      expect(ImportLimits.maxFileBytes, 20 * 1024 * 1024);
      expect(ImportLimits.maxZipUncompressedBytes, 80 * 1024 * 1024);
      expect(ImportLimits.maxZipEntries, 5000);
      expect(ImportLimits.maxRows, 20000);
    });

    test('等于上限放行，多 1 字节拒绝', () {
      expect(() => ImportLimits.ensureFileBytes(ImportLimits.maxFileBytes),
          returnsNormally);
      expect(
        () => ImportLimits.ensureFileBytes(ImportLimits.maxFileBytes + 1),
        throwsA(isA<ImportLimitException>()),
      );
      expect(() => ImportLimits.ensureRowCount(ImportLimits.maxRows),
          returnsNormally);
      expect(() => ImportLimits.ensureRowCount(ImportLimits.maxRows + 1),
          throwsA(isA<ImportLimitException>()));
    });

    test('ImportLimitException 是 FormatException，错误文案可读', () {
      ImportLimits.debugLowerLimits(fileBytes: 8);
      expect(
        () => ImportLimits.ensureFileBytes(9, what: '数据包'),
        throwsA(
          isA<ImportLimitException>().having(
            (e) => e.message,
            'message',
            allOf(contains('数据包'), contains('上限'), contains('MB')),
          ),
        ),
      );
    });
  });

  group('zip 容器放大拦截', () {
    test('条目数超限被拒绝', () {
      ImportLimits.debugLowerLimits(zipEntries: 2);
      final bytes = buildZip({
        'a.txt': [1],
        'b.txt': [2],
        'c.txt': [3],
      });
      expect(
        () => ImportLimits.ensureZipPayload(bytes),
        throwsA(isA<ImportLimitException>()),
      );
    });

    test('解压后总字节超限被拒绝（压缩炸弹）', () {
      ImportLimits.debugLowerLimits(zipUncompressedBytes: 64);
      final bytes = buildZip({
        'big.bin': Uint8List(4096),
      });
      expect(
        () => ImportLimits.ensureZipPayload(bytes),
        throwsA(isA<ImportLimitException>()),
      );
    });

    test('非 zip 字节不在这里报错（交给调用方报格式问题）', () {
      ImportLimits.debugLowerLimits(zipUncompressedBytes: 1);
      expect(
        () => ImportLimits.ensureZipPayload(Uint8List.fromList([1, 2, 3])),
        returnsNormally,
      );
    });
  });

  group('调用点已接线', () {
    test('CSV 行数超限时返回可读错误，不静默截断', () {
      ImportLimits.debugLowerLimits(rows: 3);
      final lines = <String>['学生姓名,操作项目,日期'];
      for (var i = 0; i < 10; i++) {
        lines.add('张三,批评,2026-10-${i + 1}');
      }
      final preview = ImportService.parseCsvText(
        lines.join('\n'),
        existing: const [],
      );
      expect(preview.error, contains('行数过多'));
      expect(preview.records, isEmpty);
    });

    test('Excel 读取入口拦截解压炸弹', () {
      ImportLimits.debugLowerLimits(zipUncompressedBytes: 32);
      final bytes = buildZip({
        'xl/workbook.xml': Uint8List(1024),
      });
      expect(
        () => XlsxReader.readRows(bytes),
        throwsA(isA<ImportLimitException>()),
      );
    });

    test('名单导入文件超字节上限时给出可读错误', () async {
      ImportLimits.debugLowerLimits(fileBytes: 4);
      final preview = await StudentImportService.parseFile(
        bytes: Uint8List(16),
        fileName: '名单.txt',
      );
      expect(preview.hasError, isTrue);
      expect(preview.error, contains('上限'));
    });

    test('数据包导入超字节上限时抛出可拦截的异常', () {
      ImportLimits.debugLowerLimits(fileBytes: 4);
      expect(
        () => TransferService.parsePackageBytes(Uint8List(8)),
        throwsA(isA<ImportLimitException>()),
      );
    });
  });
}
