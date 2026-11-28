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

  test('审计 P2-19：缺 attendance 视为"未提供"，解析为 null 而非拒绝整包', () {
    final json = validPackage()..remove('attendance');
    final parsed = TransferService.parsePackage(jsonEncode(json));
    expect(parsed, isNotNull, reason: '缺 attendance 不能整包拒绝');
    expect(parsed!.attendance, isNull, reason: 'null 表示包内未提供考勤，还原时保留本机');

    // 显式空数组是"包内确实没有考勤"，语义与缺失不同。
    final explicitEmpty = validPackage()..['attendance'] = <Object>[];
    final parsedEmpty = TransferService.parsePackage(jsonEncode(explicitEmpty));
    expect(parsedEmpty, isNotNull);
    expect(parsedEmpty!.attendance, isEmpty);
  });

  test('attendance 类型错误仍然拒绝整包', () {
    final json = validPackage()..['attendance'] = 'x';
    expect(TransferService.parsePackage(jsonEncode(json)), isNull);
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
