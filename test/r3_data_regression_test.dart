import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/import_service.dart';

void main() {
  group('R3 数据层回归', () {
    test('Excel 日期序列号按 1900 日期系统换算（P2-30）', () {
      const csv =
          '日期,学生姓名,操作项目,原因,备注\n'
          '46357,张三,表扬,认真,\n';
      final preview = ImportService.parseCsvText(csv, existing: const []);
      expect(preview.records, hasLength(1));
      expect(preview.records.single.date, '2026-12-01');
    });

    test('超出 Excel 日期序列号范围的数字不被当成日期', () {
      const csv =
          '日期,学生姓名,操作项目,原因,备注\n'
          '99999,张三,表扬,认真,\n';
      final preview = ImportService.parseCsvText(csv, existing: const []);
      expect(preview.records, isEmpty);
    });
  });
}
