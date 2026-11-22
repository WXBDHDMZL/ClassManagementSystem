import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/services/transfer_service.dart';

void main() {
  Map<String, dynamic> validPackage() {
    final text = TransferService.buildPackage(
      AppData.empty(),
      exportedAt: '2026-11-22 12:00',
    );
    return jsonDecode(text) as Map<String, dynamic>;
  }

  test('V5 数据包完整往返', () {
    final parsed = TransferService.parsePackage(
      TransferService.buildPackage(
        AppData.empty(),
        exportedAt: '2026-11-22 12:00',
      ),
    );

    expect(parsed, isNotNull);
    expect(parsed!.exportedAt, '2026-11-22 12:00');
    expect(parsed.attendance, isEmpty);
    expect(parsed.periods, isNotNull);
    expect(parsed.attendanceStatuses, isNotEmpty);
  });

  test('旧 v1 包直接拒绝', () {
    final json = validPackage()..['version'] = 1;
    expect(TransferService.parsePackage(jsonEncode(json)), isNull);
  });

  test('缺任一必填字段直接拒绝', () {
    const required = [
      'format',
      'version',
      'exportedAt',
      'students',
      'periods',
      'weekStart',
      'attendanceEnabled',
      'attendanceSyncMap',
      'reasons',
      'attendanceStatuses',
      'attendanceAbsentStatuses',
      'records',
      'attendance',
    ];
    for (final key in required) {
      final json = validPackage()..remove(key);
      expect(
        TransferService.parsePackage(jsonEncode(json)),
        isNull,
        reason: '缺 $key 时必须拒绝整包',
      );
    }
  });

  test('字段类型错误直接拒绝', () {
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (json) => json['weekStart'] = '1',
      (json) => json['attendanceEnabled'] = 'true',
      (json) => json['attendanceStatuses'] = '出勤',
      (json) => json['records'] = 'x',
      (json) => json['exportedAt'] = '',
    ]) {
      final json = validPackage();
      mutation(json);
      expect(TransferService.parsePackage(jsonEncode(json)), isNull);
    }
  });

  test('只有旧 periodLabels 的包被拒绝', () {
    final json = validPackage()
      ..remove('periods')
      ..['periodLabels'] = {'class': '08:00-08:40 晨读'};
    expect(TransferService.parsePackage(jsonEncode(json)), isNull);
  });
}
