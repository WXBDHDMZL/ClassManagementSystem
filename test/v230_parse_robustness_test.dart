// 解析健壮性专项回归（V2.30.21，第 2 轮：X-3 / X-4 / G-13 / X-18）。
//
// 目的：把"外部/损坏数据不会拖垮整库解析"钉住。
//   X-3  顶层 recordsByDate / settings 类型错时不得抛错判整文件损坏；
//   G-13 记录桶键必须是合法日期；桶键非法时用记录自带合法日期抢救；
//   X-4  考勤解析与记录侧对称（校验桶键、回填 date、记数写日志）；
//   X-18 整包还原时考勤三类跳过原因分别计数（此前混报成"日期非法"）。
//
// 模式沿用 v230_save_robustness / data_recovery：test() + mock path_provider。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/models/reason_library.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/utils/error_sink.dart';
import 'package:class_management_system/services/encrypted_text_file.dart';
import 'package:class_management_system/services/operation_log_service.dart';
import 'package:class_management_system/services/transfer_service.dart';
import 'package:class_management_system/utils/app_date.dart';

import 'test_helpers.dart';

Map<String, dynamic> recJson({
  String id = 'r1',
  String name = '张三',
  String? date,
  String type = '批评',
}) =>
    {
      'id': id,
      'studentName': name,
      'operationType': type,
      'reasons': '迟到',
      'periodKey': 'class',
      'periodName': '上课',
      'remark': '',
      'timestamp': '08:00:00',
      'isAppended': false,
      'isImported': false,
      'date': date,
    };

Map<String, dynamic> attJson({
  String id = 'a1',
  String name = '张三',
  String status = '迟到',
  String date = '',
  String periodKey = 'all_day',
  String ts = '08:00:00',
}) =>
    {
      'id': id,
      'studentName': name,
      'status': status,
      'date': date,
      'periodKey': periodKey,
      'timestamp': ts,
      'syncedRecordId': '',
      'syncedFromRecord': false,
    };

void main() {
  late Directory tempDir;
  late List<String> errors;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_parse_robust');
    Directory('${tempDir.path}/日志').createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.parent.path
          : null,
    );
    errors = <String>[];
    setErrorSink((tag, error, stack, {context}) => errors.add('$tag: $error'));
  });

  tearDown(() async {
    setErrorSink((tag, error, stack, {context}) {});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteStorageTestRoot(tempDir);
  });

  group('X-3 顶层类型兜底', () {
    test('recordsByDate 为 List：不抛错，记录为空，其余字段仍解析', () {
      final data = AppData.fromJson(const {
        'recordsByDate': ['不是 map'],
        'students': ['张三'],
      });
      expect(data.recordsByDate, isEmpty);
      expect(data.students, contains('张三'),
          reason: '坏掉的 recordsByDate 不该连累名单等其它字段');
    });

    test('settings 为 List：回退出厂默认设置，不抛错', () {
      final data = AppData.fromJson(const {
        'settings': ['bad'],
      });
      expect(data.settings.themeMode, ThemeModeType.system);
      expect(data.settings.rankingTopN, AppSettings.defaultRankingTopN);
    });
  });

  group('G-13 记录桶键校验', () {
    test('桶键合法 + 记录 date 空：用桶键回填（R-1 回归保护）', () {
      final data = AppData.fromJson({
        'recordsByDate': {
          '2026-10-04': [recJson(date: null)],
        },
      });
      expect(data.recordsByDate['2026-10-04']!.single.date, '2026-10-04');
    });

    test('桶键合法 + 记录 date 已有合法值：保持原样，不擅自改写（既有约定）', () {
      final data = AppData.fromJson({
        'recordsByDate': {
          '2026-10-04': [recJson(date: '2026-01-01')],
        },
      });
      expect(data.recordsByDate['2026-10-04']!.single.date, '2026-01-01');
    });

    test('桶键合法 + 记录 date 非法：用桶键修正，不产生脏日期', () {
      final data = AppData.fromJson({
        'recordsByDate': {
          '2026-10-04': [recJson(date: '2026-99-99')],
        },
      });
      expect(data.recordsByDate['2026-10-04']!.single.date, '2026-10-04');
    });

    test('桶键非法 + 记录自带合法 date：抢救到该日期，不丢数据', () {
      final data = AppData.fromJson({
        'recordsByDate': {
          '2026-13-45': [recJson(date: '2026-03-01')],
        },
      });
      expect(data.recordsByDate.containsKey('2026-13-45'), isFalse);
      expect(data.recordsByDate['2026-03-01'], hasLength(1));
      expect(errors.any((e) => e.contains('日期非法的记录分组')), isTrue);
    });

    test('桶键非法 + 记录 date 也非法：丢弃并写错误日志（不静默）', () {
      final data = AppData.fromJson({
        'recordsByDate': {
          '2026-13-45': [
            recJson(id: 'r1', date: '2026-02-30'),
            recJson(id: 'r2', date: null),
          ],
        },
      });
      expect(data.recordsByDate, isEmpty);
      expect(errors.any((e) => e.contains('损坏记录')), isTrue);
      expect(errors.any((e) => e.contains('日期非法的记录分组')), isTrue);
    });

    test('非法日期不会作为桶键进入结果（isValidYmdDate 口径一致）', () {
      final data = AppData.fromJson({
        'recordsByDate': {
          '2026-2-3': [recJson(date: '2026-02-03')],
        },
      });
      expect(data.recordsByDate.containsKey('2026-2-3'), isFalse,
          reason: '非 yyyy-MM-dd 形态的桶键必须被拦截');
      expect(data.recordsByDate['2026-02-03'], hasLength(1));
    });
  });

  group('X-4 考勤解析对称化', () {
    test('桶键合法 + date 空：用桶键回填', () {
      final data = AppData.fromJson({
        'attendanceByDate': {
          '2026-10-04': [attJson(date: '')],
        },
      });
      expect(data.attendanceByDate['2026-10-04']!.single.date, '2026-10-04');
    });

    test('桶键非法 + 自带合法 date：抢救到该日期', () {
      final data = AppData.fromJson({
        'attendanceByDate': {
          'bad-date': [attJson(date: '2026-05-06')],
        },
      });
      expect(data.attendanceByDate.containsKey('bad-date'), isFalse);
      expect(data.attendanceByDate['2026-05-06'], hasLength(1));
    });

    test('桶键非法 + date 非法：丢弃并写错误日志（此前完全静默）', () {
      final data = AppData.fromJson({
        'attendanceByDate': {
          'bad-date': [attJson(date: '2026-99-99')],
        },
      });
      expect(data.attendanceByDate, isEmpty);
      expect(errors.any((e) => e.contains('考勤数据')), isTrue);
    });
  });

  group('X-18 整包还原跳过原因分类计数', () {
    test('日期非法 / 状态非法 / 重复 分别写进日志', () async {
      final provider = AppDataProvider();
      await provider.restoreFromPackage(
        PackageData(
          records: const [],
          students: const ['张三', '李四'],
          reasons: ReasonLibrary(
            praise: const {},
            criticism: const {
              '_common': ['迟到'],
            },
          ),
          periodLabels: const {},
          attendance: const [
            // ① 日期非法
            AttendanceRecord(
              id: 'a1',
              studentName: '张三',
              status: '迟到',
              date: '2026-13-45',
              timestamp: '08:00:00',
            ),
            // ② 状态非法（保留词"出勤"）
            AttendanceRecord(
              id: 'a2',
              studentName: '张三',
              status: '出勤',
              date: '2026-10-04',
              timestamp: '08:00:00',
            ),
            // ③ 重复（与 a4 同日期同人同时段）
            AttendanceRecord(
              id: 'a3',
              studentName: '李四',
              status: '迟到',
              date: '2026-10-04',
              periodKey: 'class',
              timestamp: '08:00:00',
            ),
            AttendanceRecord(
              id: 'a4',
              studentName: '李四',
              status: '迟到',
              date: '2026-10-04',
              periodKey: 'class',
              timestamp: '09:00:00',
            ),
          ],
        ),
      );

      // 操作日志异步排队写盘：轮询等待落盘（最多 2 秒）。
      String? logText;
      final logFile = File(
        '${tempDir.path}/日志/${OperationLogService.fileName}',
      );
      for (var i = 0; i < 100; i++) {
        if (logFile.existsSync()) {
          final text = await EncryptedTextFile.readAllText(logFile);
          if (text.contains('整包还原')) {
            logText = text;
            break;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(logText, isNotNull, reason: '整包还原必须写入操作日志');
      expect(logText!, contains('日期非法 1 条'));
      expect(logText, contains('状态非法 1 条'));
      expect(logText, contains('重复 1 条'));
      // 三分类都非零时不该再出现旧的"一刀切"写法。
      expect(logText.contains('跳过日期非法 3 条'), isFalse);
    });
  });

  // 保证导入被使用（避免 lint 未使用告警）。
  test('isValidYmdDate 与用例前提一致', () {
    expect(isValidYmdDate('2026-10-04'), isTrue);
    expect(isValidYmdDate('2026-13-45'), isFalse);
  });
}
