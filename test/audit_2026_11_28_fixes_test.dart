// 审计 2026-11-28 修复回归测试：
// 覆盖 P1-1（损坏备份保护）、P1-2（删除时段后编辑保留快照）、P1-3（原因改名
// 按分组隔离）、P1-4（全天时段反查）、P1-6（CSV 裸引号）、P1-7（名单标题行）、
// P2-12（原因库列数）、P2-13（合并单元格）、P2-19（数据包考勤缺失语义）、
// P2-24（多资产 checksum）以及若干 P3 工具函数。
//
// 全部在 mock 的临时文档目录里跑，绝不触碰真实数据文件。

import 'dart:convert';
import 'dart:ui' show Tristate;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/github_update_service.dart';
import 'package:class_management_system/services/import_service.dart';
import 'package:class_management_system/services/student_import_service.dart';
import 'package:class_management_system/services/storage_service.dart';
import 'package:class_management_system/services/storage_crypto.dart';
import 'package:class_management_system/services/storage_key_id.dart';
import 'package:class_management_system/services/transfer_service.dart';
import 'package:class_management_system/services/xlsx_merge.dart';
import 'package:class_management_system/utils/file_names.dart';
import 'package:class_management_system/utils/record_text.dart';
import 'package:class_management_system/widgets/app_notification.dart';
import 'package:class_management_system/widgets/student_card.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    resetPeriodsForTest();
  });

  group('P1-4 全天时段反查', () {
    test('matchTimePeriodKey("全天") 必须反查为 all_day', () {
      expect(matchTimePeriodKey('全天'), allDayPeriodKey);
      expect(matchTimePeriodKey(' 全天 '), allDayPeriodKey);
    });

    test('periodNameForRecord(all_day) 仍显示“全天”', () {
      expect(periodNameForRecord(allDayPeriodKey, ''), '全天');
    });
  });

  group('P1-2 删除自定义时段后编辑记录', () {
    test('updateRecord 保留删除前的 periodName 快照', () {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);

      expect(
        provider.setPeriods(const [
          {'key': 'night', 'label': '22:00-06:30 就寝'},
        ]),
        isTrue,
      );
      final record = provider.addRecord(
        '张三',
        '批评',
        const ['迟到'],
        'night',
        '',
        date: '2026-10-04',
      );
      expect(record, isNotNull);
      expect(record!.periodName, '22:00-06:30 就寝');

      // 删除该自定义时段（恢复出厂时段）。
      expect(provider.setPeriods(const []), isTrue);

      final edited = provider.updateRecord(
        record.id,
        '批评',
        const ['迟到'],
        'night',
        '补充备注',
        date: '2026-10-04',
      );
      expect(edited, isTrue);
      final loaded = provider.getRecordsForDate('2026-10-04').single;
      expect(loaded.remark, '补充备注');
      expect(loaded.periodKey, 'night');
      expect(
        loaded.periodName,
        '22:00-06:30 就寝',
        reason: '删除时段后编辑记录，不得把历史快照改写成裸 key',
      );
    });
  });

  group('P1-3 原因改名按分组隔离', () {
    test('改 class 组的“睡觉”不影响 morning_reading 组历史记录', () {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);

      final classRecord = provider.addRecord(
        '张三',
        '批评',
        const ['睡觉'],
        'class',
        '',
        date: '2026-10-05',
      );
      final morningRecord = provider.addRecord(
        '李四',
        '批评',
        const ['睡觉'],
        'morning_reading',
        '',
        date: '2026-10-05',
      );
      expect(classRecord, isNotNull);
      expect(morningRecord, isNotNull);

      expect(provider.renameReason('批评', 'class', '睡觉', '上课打瞌睡'), isTrue);

      final records = provider.getRecordsForDate('2026-10-05');
      expect(
        records.firstWhere((r) => r.periodKey == 'class').reasons,
        '上课打瞌睡',
      );
      expect(
        records.firstWhere((r) => r.periodKey == 'morning_reading').reasons,
        '睡觉',
        reason: '同名原因在其它分组里必须保持不变',
      );
    });
  });

  group('P1-6 CSV 状态机', () {
    test('字段中间的裸引号不再吞掉后续行', () {
      final rows = ImportService.parseCsvRows('姓名,原因\n张三"备注,迟到\n李四,早退');
      expect(rows, hasLength(3));
      expect(rows[1][0], '张三"备注');
      expect(rows[2], ['李四', '早退']);
    });

    test('未闭合引号抛 FormatException 而不是静默返回残行', () {
      expect(
        () => ImportService.parseCsvRows('姓名,原因\n"张三,迟到'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('P1-7 名单标题行过滤', () {
    test('表头前的单格标题行不作为姓名导入', () {
      final preview = StudentImportService.parseText('七年级一班名单\n张三\n李四');
      expect(preview.names, ['张三', '李四']);
    });
  });

  group('P2-12 原因库列数判定', () {
    test('两列布局被 excel 补齐到三列后仍能整库导入', () {
      final rows = <List<String>>[
        ['表扬', '认真读书', ''],
        ['批评', '迟到', ''],
      ];
      final parsed = TransferService.parseReasonsRows(rows);
      expect(parsed, hasLength(2));
      expect(parsed[0].reason, '认真读书');
      expect(parsed[0].periodKey, '_common');
    });
  });

  group('P2-13 合并单元格填充', () {
    test('纵向合并区把左上角值铺满整个区域', () {
      final rows = <List<String>>[
        ['2026-10-01', '张三', '迟到'],
        ['', '', ''],
        ['', '李四', '早退'],
      ];
      final merged = XlsxMerge.fill(rows, ['A1:A2']);
      expect(merged[0][0], '2026-10-01');
      expect(merged[1][0], '2026-10-01');
      expect(merged[1][1], '');
    });

    test('无合并区时原样返回', () {
      final rows = <List<String>>[
        ['a', 'b'],
      ];
      expect(XlsxMerge.fill(rows, const []), rows);
    });
  });

  group('P2-19 数据包考勤缺失语义', () {
    Map<String, dynamic> basePackage() => {
      'format': 'class_management_system.package',
      'version': 2,
      'exportedAt': '2026-11-28 10:00:00',
      'students': <String>['张三'],
      'periods': <Map<String, String>>[],
      'weekStart': 1,
      'attendanceEnabled': true,
      'attendanceSyncMap': <String, String>{},
      'reasons': <String, dynamic>{},
      'attendanceStatuses': <String>['请假'],
      'attendanceAbsentStatuses': <String>['请假'],
      'records': <dynamic>[],
    };

    test('缺少 attendance 键 → 解析为 null（保留本机考勤）', () {
      final parsed = TransferService.parsePackage(jsonEncode(basePackage()));
      expect(parsed, isNotNull);
      expect(parsed!.attendance, isNull);
    });

    test('attendance 显式空数组 → 空列表（清空）', () {
      final map = basePackage()..['attendance'] = <dynamic>[];
      final parsed = TransferService.parsePackage(jsonEncode(map));
      expect(parsed, isNotNull);
      expect(parsed!.attendance, isNotNull);
      expect(parsed.attendance, isEmpty);
    });

    test('attendance 类型错误仍拒绝整包', () {
      final map = basePackage()..['attendance'] = 'not-a-list';
      expect(TransferService.parsePackage(jsonEncode(map)), isNull);
    });
  });

  group('P2-24 多资产 checksum 解析', () {
    test('按文件名匹配目标资产，而不是永远取第一个摘要', () {
      const text = '''
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  app-1.0.0.exe
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  app-1.0.0.zip
''';
      expect(
        GitHubUpdateService.parseChecksum(text, 'app-1.0.0.zip'),
        'b' * 64,
      );
      expect(
        GitHubUpdateService.parseChecksum(text, 'app-1.0.0.exe'),
        'a' * 64,
      );
      expect(GitHubUpdateService.parseChecksum(text, 'other.exe'), isNull);
    });

    test('单摘要无文件名时仍可作为兜底', () {
      final digest = 'c' * 64;
      expect(GitHubUpdateService.parseChecksum(digest, 'any.exe'), digest);
    });
  });

  group('P3 工具函数', () {
    test('clipName 不切断 emoji 代理对', () {
      final clipped = RecordText.clipName('😀' * 20);
      expect(clipped.runes.length, lessThanOrEqualTo(RecordText.maxNameLength));
      expect(clipped.contains('\uFFFD'), isFalse);
      // 每一位都应是完整 emoji。
      expect(clipped.runes.every((r) => r == 0x1F600), isTrue);
    });

    test('sanitizeFileName 超长时保留扩展名并截断主体', () {
      final name = '${'a' * 300}.xlsx';
      final safe = sanitizeFileName(name);
      expect(safe.length, lessThanOrEqualTo(120));
      expect(safe.endsWith('.xlsx'), isTrue);
    });
  });

  group('P1-1 主文件缺失且备份不可读时阻断', () {
    late Directory tempDir;
    setUp(() {
      tempDir = createStorageTestRoot('cms_audit_p1_1');
      StorageService.debugDataKeyOverride = Uint8List.fromList(
        List<int>.generate(32, (i) => i + 1),
      );
      StorageService.debugResetKey();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? tempDir.parent.path
                : null,
          );
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      StorageService.debugResetKey();
      await deleteStorageTestRoot(tempDir);
    });

    test('loadData 返回 backupUnreadable 且两次保存都不覆盖 .bak', () async {
      final bak = File('${tempDir.path}/class_management_data.enc.bak');
      await bak.writeAsString('损坏的备份!!!');
      final storage = StorageService();
      final result = await storage.loadData();
      expect(result.backupUnreadable, isTrue);
      expect(result.resetToEmpty, isFalse);
      expect(result.keyMismatch, isFalse);
      expect(result.loadFailed, isFalse);

      expect(await storage.saveData(AppData.empty()), isFalse);
      expect(await storage.saveData(AppData.empty()), isFalse);
      expect(await bak.readAsString(), '损坏的备份!!!', reason: '阻断态下不得覆盖唯一备份');
    });
  });

  group('P2-1 阻断态删除记录返回 false', () {
    test('_blockedByStartup 时 deleteRecord 不返回成功', () async {
      final tempDir = createStorageTestRoot('cms_audit_p2_1');
      StorageService.debugDataKeyOverride = Uint8List.fromList(
        List<int>.generate(32, (i) => i + 1),
      );
      StorageService.debugResetKey();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? tempDir.parent.path
                : null,
          );
      try {
        await File(
          '${tempDir.path}/class_management_data.enc',
        ).writeAsString('损坏内容!!!');
        final provider = AppDataProvider();
        await provider.initialize();
        expect(provider.storageWriteBlocked, isTrue);
        expect(provider.deleteRecord('not-exist', date: '2026-10-01'), isFalse);
        provider.dispose();
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
        StorageService.debugResetKey();
        await deleteStorageTestRoot(tempDir);
      }
    });
  });

  group('P2-8 / P3 批量删除与覆盖重复', () {
    /// 复制一条记录但去掉 date（模拟导入时归属日期丢失的行）。
    StudentRecord withoutDate(StudentRecord record) => StudentRecord(
      id: record.id,
      studentName: record.studentName,
      operationType: record.operationType,
      reasons: record.reasons,
      periodKey: record.periodKey,
      periodName: record.periodName,
      remark: record.remark,
      timestamp: record.timestamp,
      isImported: true,
    );

    test('deleteRecords(keepAttendance: true) 按桶删除，不撤销派生考勤', () {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      final record = provider.addRecord(
        '张三',
        '批评',
        const ['迟到'],
        'class',
        '',
        date: '2026-10-06',
      )!;

      expect(
        provider.deleteRecords([record], keepAttendance: true),
        1,
        reason: '保留考勤模式下也必须真的删掉记录',
      );
      expect(provider.getRecordsForDate('2026-10-06'), isEmpty);
    });

    test('deleteRecords(keepAttendance: true)：date 为 null 时按 id 全表兜底', () {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      final record = provider.addRecord(
        '李四',
        '表扬',
        const ['主动帮助'],
        'class',
        '',
        date: '2026-10-07',
      )!;

      // 旧实现遇到 date == null 直接 continue，记录永远删不掉且没有提示。
      expect(
        provider.deleteRecords([withoutDate(record)], keepAttendance: true),
        1,
      );
      expect(provider.getRecordsForDate('2026-10-07'), isEmpty);
    });

    test('deleteRecords(keepAttendance: false) 撤销派生考勤并写撤销快照', () async {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      final record = provider.addRecord(
        '王五',
        '批评',
        const ['迟到'],
        'class',
        '',
        date: '2026-10-08',
      )!;

      expect(provider.deleteRecords([record]), 1);
      expect(provider.getRecordsForDate('2026-10-08'), isEmpty);
      final undone = await provider.undoLastRecordChange();
      expect(undone.changed, 1, reason: '不保留考勤时必须有撤销快照');
      expect(provider.getRecordsForDate('2026-10-08'), hasLength(1));
    });

    test('replaceDuplicateRecords 一次落盘完成「删除重复 + 重新导入」', () {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      final old = provider.addRecord(
        '赵六',
        '批评',
        const ['迟到'],
        'class',
        '',
        date: '2026-10-09',
      )!;
      final replacement = StudentRecord(
        id: '',
        studentName: '赵六',
        operationType: '批评',
        reasons: '迟到、未交作业',
        periodKey: 'class',
        periodName: '课堂',
        remark: '覆盖导入',
        timestamp: '08:30:00',
        isImported: true,
        date: '2026-10-09',
      );

      final result = provider.replaceDuplicateRecords([old], [replacement]);
      expect(result.overwritten, 1);
      expect(result.imported, 1);
      final records = provider.getRecordsForDate('2026-10-09');
      expect(records, hasLength(1));
      expect(records.single.remark, '覆盖导入');
      expect(records.single.reasons, '迟到、未交作业');
    });
  });

  group('P2-10 衍生：空的密钥占位文件', () {
    late Directory tempDir;

    setUp(() {
      tempDir = createStorageTestRoot('cms_audit_key_placeholder');
      // 本组必须走真实的「生成密钥」分支，所以清掉测试注入的固定密钥。
      StorageService.debugDataKeyOverride = null;
      StorageService.debugResetKey();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? tempDir.parent.path
                : null,
          );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      StorageService.debugDataKeyOverride = Uint8List.fromList(
        List<int>.generate(32, (i) => i + 1),
      );
      StorageService.debugResetKey();
      await deleteStorageTestRoot(tempDir);
    });

    File mainFile() => File('${tempDir.path}/class_management_data.enc');
    File keyFile() => File('${tempDir.path}/class_management_data.enc.key');

    test('无数据文件时，空密钥占位文件会被丢弃并重建', () async {
      await keyFile().writeAsBytes(const <int>[]);
      expect(await keyFile().length(), 0);

      await StorageService.initializeKey();

      expect(await keyFile().length(), greaterThan(0), reason: '必须重新写入可用密钥');
      // 拿到密钥后应能正常编码/解码，证明新密钥自洽。
      final storage = StorageService();
      final encoded = await storage.encodeForTest(AppData.empty());
      expect(await storage.decodeForTest(encoded), isNotNull);
    });

    test('存在数据文件时，空密钥占位文件不得被静默重建', () async {
      await mainFile().writeAsString('some-ciphertext');
      await keyFile().writeAsBytes(const <int>[]);

      await expectLater(
        StorageService.initializeKey(),
        throwsA(isA<DataKeyUnavailableException>()),
      );
      expect(
        await mainFile().readAsString(),
        'some-ciphertext',
        reason: '拒绝新钥的同时不得改动数据文件',
      );
    });
  });

  group('P1-5 恢复已写盘但读取校验失败', () {
    late Directory tempDir;

    setUp(() {
      tempDir = createStorageTestRoot('cms_audit_restore_verify');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? tempDir.parent.path
                : null,
          );
    });

    tearDown(() async {
      StorageService.debugLoadOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await deleteStorageTestRoot(tempDir);
    });

    test('恢复写盘后 loadData 校验失败：阻断写入，且不用旧内存覆盖刚恢复的文件', () async {
      final storage = StorageService();
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      await provider.initialize();

      // 旧内存（恢复前的数据）与备份内容故意不同，用来判断是否被回写。
      provider.appData.setStudents(const ['旧内存学生']);
      expect(await provider.saveNow(), isTrue);
      final mainFile = File(await storage.dataFilePath);
      final beforeRestore = await mainFile.readAsString();
      expect(beforeRestore, isNotEmpty, reason: '恢复前主文件应当是旧数据');

      final backupText = await storage.encodeForTest(
        AppData(
          recordsByDate: const {},
          settings: AppSettings.defaultSettings(),
          students: const ['备份学生'],
        ),
      );
      final backup = File('${tempDir.path}/audit_restore_backup.enc');
      await backup.writeAsString(backupText);

      // 故障注入：备份已经写盘，但紧随其后的 loadData 校验失败；
      // 同时模拟恢复窗口期内排队的一次保存（旧实现在 finally 里会把它写回去）。
      var injected = 0;
      StorageService.debugLoadOverride = () {
        injected++;
        // 这里只借用它的内存副作用制造"窗口期改动"，返回值（是否落盘）无关。
        provider.setExportOptions(filePrefix: '窗口期改动');
        return DataLoadResult(data: AppData.empty(), loadFailed: true);
      };

      final error = await provider.restoreBackupFrom(backup.path);
      StorageService.debugLoadOverride = null;

      expect(injected, 1, reason: '必须真的走到「恢复后的读取校验」分支');
      expect(error, isNotNull);
      expect(error, contains('恢复后数据读取校验失败'));

      // 核心断言：主文件必须仍是刚恢复的备份内容，不能被旧内存/窗口期改动覆盖。
      expect(
        await mainFile.readAsString(),
        backupText,
        reason: '恢复失败后不得把旧内存回写到刚被替换的主文件',
      );

      // 写入已被阻断：后续保存失败，文件内容不再变化。
      expect(await provider.saveNow(), isFalse);
      expect(
        await mainFile.readAsString(),
        backupText,
        reason: '阻断态下任何保存都不能改动主文件',
      );
    });
  });

  // 审计补强：此前这两条 P3 修复只有代码、没有断言覆盖（抽检发现的缺口）。
  group('P3 无障碍与通知契约', () {
    test('P3 通知结束时会回调已注册的监听器（旧实现直接清空，回调恒为 0）', () {
      final controller = AppNoticeController();
      addTearDown(controller.dispose);

      final handle = controller.show(
        '保存失败',
        duration: const Duration(seconds: 30),
      );
      var called = 0;
      handle.addListener(() => called++);
      expect(called, 0, reason: '通知还没结束时不应回调');

      handle.dismiss();

      expect(handle.isDone, isTrue);
      expect(called, 1, reason: '结束时应恰好回调一次监听器');
    });

    testWidgets('P3 学生卡片暴露按钮语义与选中状态', (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        testApp(
          home: Scaffold(
            body: StudentCard(name: '张三', isSelected: false, onTap: () {}),
          ),
        ),
      );

      final node = tester.getSemantics(find.byType(StudentCard));
      expect(node.label, contains('张三'));
      expect(node.label, contains('未选中'));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isSelected, Tristate.isFalse);

      await tester.pumpWidget(
        testApp(
          home: Scaffold(
            body: StudentCard(name: '张三', isSelected: true, onTap: () {}),
          ),
        ),
      );

      final selected = tester.getSemantics(find.byType(StudentCard));
      expect(selected.label, contains('已选中'));
      expect(selected.flagsCollection.isSelected, Tristate.isTrue);

      // SemanticsHandle 必须在用例体内释放（框架在 tearDown 之前校验）。
      semantics.dispose();
    });
  });

  group('B-34 指纹缺失时的降级：先试 .bak，再判密钥不可用', () {
    late Directory tempDir;
    final keyA = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final keyB = Uint8List.fromList(List<int>.generate(32, (i) => (i + 1) * 7));

    setUp(() {
      tempDir = createStorageTestRoot('cms_audit_b34');
      StorageService.debugDataKeyOverride = Uint8List.fromList(keyA);
      StorageService.debugResetKey();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? tempDir.parent.path
                : null,
          );
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      StorageService.debugResetKey();
      await deleteStorageTestRoot(tempDir);
    });

    File mainFile() => File('${tempDir.path}/class_management_data.enc');
    File backupFile() => File('${tempDir.path}/class_management_data.enc.bak');
    List<File> corruptFiles() => tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.enc.corrupt_'))
        .toList();

    test('正例：.bak 可用当前密钥解密 → 自动恢复、数据可读、不产生 .corrupt', () async {
      // 主文件用"别的密钥"加密（模拟换机/换用户后的残留），且没有 .keyid。
      await mainFile().writeAsString(
        StorageCrypto.encodeV3('{"students":["外机学生"]}', keyB),
      );
      await backupFile().writeAsString(
        StorageCrypto.encodeV3('{"students":["备份学生"]}', keyA),
      );
      expect(
        File('${mainFile().path}${StorageKeyId.fileSuffix}').existsSync(),
        isFalse,
        reason: '前提：没有指纹文件（旧数据）',
      );

      final storage = StorageService();
      final result = await storage.loadData();

      expect(result.restoredFromBackup, isTrue);
      expect(result.keyUnavailable, isFalse);
      expect(result.keyMismatch, isFalse);
      expect(result.resetToEmpty, isFalse);
      expect(result.data.students, contains('备份学生'));
      expect(corruptFiles(), isEmpty, reason: '备份可解时不得隔离主文件');
      expect(
        await mainFile().readAsString(),
        await backupFile().readAsString(),
        reason: '自动恢复应把可解的备份写回主文件',
      );
    });

    test('反例：.bak 也不可解 → 隔离 *.corrupt_* 并判密钥不可用，绝不用新密钥覆盖', () async {
      final sealedMain = StorageCrypto.encodeV3('{"students":["外机学生"]}', keyB);
      await mainFile().writeAsString(sealedMain);
      await backupFile().writeAsString(
        StorageCrypto.encodeV3('{"students":["外机备份"]}', keyB),
      );
      final keyFile = File('${mainFile().path}.key');
      final keyExistedBefore = await keyFile.exists();
      final keyBytesBefore = keyExistedBefore
          ? await keyFile.readAsBytes()
          : const <int>[];

      final storage = StorageService();
      final result = await storage.loadData();

      expect(result.keyUnavailable, isTrue);
      expect(result.resetToEmpty, isFalse, reason: '密钥问题不得被当成"内容损坏重置"');
      expect(result.keyMismatch, isFalse);
      expect(result.loadFailed, isFalse);
      expect(corruptFiles(), hasLength(1));
      expect(
        await corruptFiles().single.readAsString(),
        sealedMain,
        reason: '隔离文件必须是原文件逐字节副本',
      );
      expect(mainFile().existsSync(), isFalse, reason: '原主文件应已被改名隔离');

      // 阻断态：既不能写空库，也不能重建密钥。
      expect(await storage.saveData(AppData.empty()), isFalse);
      expect(mainFile().existsSync(), isFalse, reason: '阻断态下不得写出新的主文件');
      expect(
        await keyFile.exists(),
        keyExistedBefore,
        reason: '绝不能用新密钥重建/替换原密钥文件',
      );
      if (keyExistedBefore) {
        expect(
          await keyFile.readAsBytes(),
          keyBytesBefore,
          reason: '原密钥文件必须逐字节保留',
        );
      }
    });
  });

  group('B-35 setExportOptions 拒绝空列', () {
    test('空列表返回 false 且状态不变；非空返回 true 且生效', () {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);

      expect(
        provider.setExportOptions(recordColumns: const ['name', 'recordedBy']),
        isTrue,
      );
      final before = provider.appData.settings.recordExportColumns;
      expect(before, isNotNull);
      expect(before, contains('recordedBy'));

      expect(
        provider.setExportOptions(recordColumns: const []),
        isFalse,
        reason: '空列表不得静默回退默认列',
      );
      expect(
        provider.appData.settings.recordExportColumns,
        before,
        reason: '被拒绝时选项必须保持原值',
      );

      // 全部是未知列键（过滤后为空）同样拒绝，且不改状态。
      expect(
        provider.setExportOptions(recordColumns: const ['不存在的列']),
        isFalse,
      );
      expect(provider.appData.settings.recordExportColumns, before);

      expect(provider.setExportOptions(recordColumns: const ['name']), isTrue);
      expect(provider.appData.settings.recordExportColumns, const ['name']);
    });
  });
}
