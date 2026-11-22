// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/atomic_file.dart';
import 'package:class_management_system/services/storage_service.dart';
import 'package:class_management_system/services/transfer_service.dart';

/// 本机维护工具：从加密主数据/旧备份导出历史考勤（不进入安装包）。
void main() {
  test('导出历史考勤（需通过环境变量指定文件）', () async {
    final input = Platform.environment['CMS_ATTENDANCE_FILE']?.trim() ?? '';
    final output = Platform.environment['CMS_ATTENDANCE_OUTPUT']?.trim() ?? '';
    if (input.isEmpty || output.isEmpty) {
      print(
        '未执行：请设置 CMS_ATTENDANCE_FILE（加密数据/备份路径）与 '
        'CMS_ATTENDANCE_OUTPUT（输出 xlsx 路径）。',
      );
      return;
    }
    final file = File(input);
    if (!await file.exists()) {
      fail('文件不存在：$input');
    }
    final data = await StorageService().decodeForTest(await file.readAsString());
    if (data == null) {
      fail('文件无法解码（可能不是本程序的数据文件/备份）');
    }
    final records = data.attendanceByDate.values
        .expand((list) => list)
        .toList(growable: false);
    if (records.isEmpty) {
      print('该文件没有历史考勤记录。');
      return;
    }
    final bytes = TransferService.buildAttendanceXlsx(
      records,
      data.students.toList(),
      null,
      true,
    );
    await AtomicFile.writeBytes(output, bytes);
    print('导出完成：${records.length} 条考勤 → $output');
  });
}
