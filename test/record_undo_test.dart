import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/models/undo_result.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/storage_service.dart';
import 'package:class_management_system/widgets/record_dialog.dart';
import 'package:class_management_system/widgets/record_list.dart';

import 'test_helpers.dart';

const _date = '2026-10-18';

/// UI 流程测试用的 provider：撤销现在要等落盘结果（审计 A-18b），
/// 而 widget 测试里没有真实数据文件，保存一定失败；这里把"落盘"裁掉，
/// 只测 UI 语义（落盘成败的语义由 provider 级用例覆盖）。
class _NoDiskProvider extends AppDataProvider {
  @override
  Future<bool> saveNow() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('最近一次记录变更撤销', () {
    test('撤销单条新增记录', () async {
      final provider = AppDataProvider();
      final record = provider.addRecord(
        '张三',
        '表扬',
        const ['认真'],
        'class',
        '',
        date: _date,
      );

      expect(record, isNotNull);
      expect(provider.getRecordsForDate(_date), hasLength(1));

      expect((await provider.undoLastRecordChange()).changed, 1);
      expect(provider.getRecordsForDate(_date), isEmpty);
      expect((await provider.undoLastRecordChange()).changed, 0);
    });

    test('撤销批量新增记录时整批一起删除', () async {
      final provider = AppDataProvider();
      final added = provider.addRecordsForStudents(
        const ['张三', '李四', '  '],
        '批评',
        const ['迟到'],
        'class',
        '',
        date: _date,
      );

      expect(added, 2);
      expect(provider.getRecordsForDate(_date), hasLength(2));

      expect((await provider.undoLastRecordChange()).changed, 2);
      expect(provider.getRecordsForDate(_date), isEmpty);
    });

    test('撤销批量导入新增记录', () async {
      final provider = AppDataProvider();
      final added = provider.addRecordsBatch([
        (
          studentName: '张三',
          operationType: '表扬',
          reasons: const ['认真'],
          periodKey: 'class',
          remark: '',
          date: _date,
        ),
        (
          studentName: '李四',
          operationType: '批评',
          reasons: const ['迟到'],
          periodKey: 'class',
          remark: '',
          date: _date,
        ),
      ]);

      expect(added, 2);
      expect((await provider.undoLastRecordChange()).changed, 2);
      expect(provider.getRecordsForDate(_date), isEmpty);
    });

    test('只撤销最近一次新增，更早的记录保留', () async {
      final provider = AppDataProvider();
      provider.addRecord(
        '张三',
        '表扬',
        const ['认真'],
        'class',
        '',
        date: _date,
      );
      provider.addRecord(
        '李四',
        '批评',
        const ['迟到'],
        'class',
        '',
        date: _date,
      );

      expect((await provider.undoLastRecordChange()).changed, 1);
      final records = provider.getRecordsForDate(_date);
      expect(records, hasLength(1));
      expect(records.single.studentName, '张三');
    });

    test('撤销修改记录会恢复修改前内容', () async {
      final provider = AppDataProvider();
      final record = provider.addRecord(
        '张三',
        '表扬',
        const ['认真'],
        'class',
        '原备注',
        date: _date,
      );
      expect(record, isNotNull);

      expect(
        provider.updateRecord(
          record!.id,
          '批评',
          const ['迟到'],
          'class',
          '新备注',
          date: _date,
        ),
        isTrue,
      );
      expect(provider.getRecordsForDate(_date).single.operationType, '批评');

      var notifications = 0;
      provider.addListener(() => notifications++);
      expect((await provider.undoLastRecordChange()).changed, 1);
      final restored = provider.getRecordsForDate(_date).single;
      expect(restored.operationType, '表扬');
      expect(restored.reasons, '认真');
      expect(restored.remark, '原备注');
      expect(notifications, greaterThan(0), reason: '撤销修改必须通知界面刷新');
      expect((await provider.undoLastRecordChange()).changed, 0);
    });

    test('修改记录时撤销快照先于界面通知就绪，监听者立即撤销不会误删原记录', () async {
      final provider = AppDataProvider();
      final record = provider.addRecord(
        '张三',
        '表扬',
        const ['认真'],
        'class',
        '',
        date: _date,
      );
      expect(record, isNotNull);

      UndoResult? undoResult;
      void listener() {
        if (undoResult != null) return;
        final records = provider.getRecordsForDate(_date);
        if (records.length == 1 && records.single.operationType == '批评') {
          // 撤销本身是异步的（要等落盘），但内存回滚在第一个 await 之前就
          // 完成了，所以监听回调里调用仍然必须回滚到"本次操作前"的状态。
          unawaited(
            provider.undoLastRecordChange().then((value) => undoResult = value),
          );
        }
      }

      provider.addListener(listener);
      addTearDown(() => provider.removeListener(listener));
      expect(
        provider.updateRecord(
          record!.id,
          '批评',
          const ['迟到'],
          'class',
          '',
          date: _date,
        ),
        isTrue,
      );
      provider.removeListener(listener);

      await flushWrites(provider);
      expect(undoResult?.changed, 1);
      final restored = provider.getRecordsForDate(_date);
      expect(restored, hasLength(1));
      expect(restored.single.operationType, '表扬');
      expect(restored.single.reasons, '认真');
    });

    test('撤销删除记录会恢复原记录及位置', () async {
      final provider = AppDataProvider();
      final first = provider.addRecord(
        '张三',
        '表扬',
        const ['认真'],
        'class',
        '',
        date: _date,
      );
      provider.addRecord(
        '李四',
        '批评',
        const ['迟到'],
        'class',
        '',
        date: _date,
      );
      expect(first, isNotNull);

      expect(provider.deleteRecord(first!.id, date: _date), isTrue);
      expect(provider.getRecordsForDate(_date), hasLength(1));

      var notifications = 0;
      provider.addListener(() => notifications++);
      expect((await provider.undoLastRecordChange()).changed, 1);
      final records = provider.getRecordsForDate(_date);
      expect(records, hasLength(2));
      expect(records.first.id, first.id);
      expect(records.first.studentName, '张三');
      expect(notifications, greaterThan(0), reason: '撤销删除必须通知界面刷新');
      expect((await provider.undoLastRecordChange()).changed, 0);
    });

    test('编辑后撤销的是修改，不会误删原新增记录', () async {
      final provider = AppDataProvider();
      final record = provider.addRecord(
        '张三',
        '表扬',
        const ['认真'],
        'class',
        '',
        date: _date,
      );
      expect(record, isNotNull);
      provider.updateRecord(
        record!.id,
        '批评',
        const ['迟到'],
        'class',
        '',
        date: _date,
      );

      expect((await provider.undoLastRecordChange()).changed, 1);
      expect(provider.getRecordsForDate(_date), hasLength(1));
      expect(provider.getRecordsForDate(_date).single.operationType, '表扬');
    });

    test('删除后撤销的是删除，不会误删原新增记录', () async {
      final provider = AppDataProvider();
      final record = provider.addRecord(
        '张三',
        '表扬',
        const ['认真'],
        'class',
        '',
        date: _date,
      );
      expect(record, isNotNull);
      provider.deleteRecord(record!.id, date: _date);

      expect((await provider.undoLastRecordChange()).changed, 1);
      expect(provider.getRecordsForDate(_date), hasLength(1));
      expect(provider.getRecordsForDate(_date).single.id, record.id);
    });
  });

  testWidgets('撤销删除后记录立即重新出现在列表中', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = _NoDiskProvider();
    provider.addRecord(
      '张三',
      '表扬',
      const ['认真'],
      'class',
      '',
      date: _date,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppDataProvider>.value(
        value: provider,
        child: testApp(
          theme: AppTheme.light(),
          home: Consumer<AppDataProvider>(
            builder: (context, current, _) => Scaffold(
              body: RecordList(
                records: current.getRecordsForDate(_date),
                targetDate: _date,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('张三'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pump();
    expect(find.text('暂无记录'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pump();
    // 撤销是异步的（要等落盘结果才提示），多推一帧让 Future 完成。
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('张三'), findsOneWidget);
    expect(find.text('已撤销本次记录'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('记录对话框提交后显示撤销按钮，点击可删除刚新增的记录', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = _NoDiskProvider();
    provider.setRecordDefaults(defaultType: 0, autoSelectPeriod: false);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppDataProvider>.value(
        value: provider,
        child: testApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: RecordDialog(studentName: '张三')),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, '助人为乐'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(provider.getTodayRecords(), hasLength(1));
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(provider.getTodayRecords(), isEmpty);
    expect(find.text('已撤销本次记录'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
  });

  // 审计 A-06：删除记录时派生考勤会被撤销/解绑，撤销必须重新接管考勤，
  // 而不是把记录写回去让考勤永久失联。
  test('撤销删除会重新接管被解绑的考勤（A-06）', () async {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    final record = provider.addRecord(
      '张三',
      '批评',
      const ['迟到'],
      'class',
      '',
      date: _date,
    );
    expect(record, isNotNull);
    expect(
      provider
          .getAttendanceForDate(_date)
          .firstWhere((a) => a.studentName == '张三')
          .syncedRecordId,
      record!.id,
    );

    provider.deleteRecord(record.id, date: _date);
    // 删除后老师手工登记了一次别的状态（手工行，不再关联记录）。
    expect(
      provider.setAttendance('张三', '请假', date: _date, periodKey: 'class'),
      isTrue,
    );
    expect(
      provider
          .getAttendanceForDate(_date)
          .firstWhere((a) => a.studentName == '张三')
          .syncedRecordId,
      isEmpty,
    );

    final result = await provider.undoLastRecordChange();
    expect(result.changed, 1);
    final restored = provider
        .getAttendanceForDate(_date)
        .firstWhere((a) => a.studentName == '张三');
    expect(restored.syncedRecordId, record.id,
        reason: '撤销删除必须让考勤重新由这条批评记录接管');
  });

  // 审计 A-05：导入记录之后，撤销键不能还停在导入之前的旧操作上。
  test('导入记录后不再能撤销导入之前的操作（A-05）', () async {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    // 不指定 date：撤销快照按"今天"记录，这样若不清快照，撤销会真的删掉张三。
    provider.addRecord('张三', '表扬', const ['认真'], 'class', '');

    final imported = provider.importRecords([
      StudentRecord(
        id: '',
        studentName: '李四',
        operationType: '表扬',
        reasons: '主动',
        periodKey: 'class',
        periodName: '',
        remark: '',
        timestamp: '08:00:00',
        date: _date,
      ),
    ]);
    expect(imported, 1);

    final result = await provider.undoLastRecordChange();
    expect(result.changed, 0, reason: '导入后旧撤销快照必须失效');
  });

  // 审计 A-18b：撤销必须等落盘结果，并把"没写进去"如实报给界面。
  // 这里用真实临时数据目录验证 saved 的真假语义（不是桩）。
  group('撤销的落盘结果', () {
    late Directory tempDir;

    setUp(() {
      tempDir = createStorageTestRoot('cms_undo_persist');
      StorageService.debugDataKeyOverride =
          Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
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
      StorageService.debugResetKey();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      await deleteStorageTestRoot(tempDir);
    });

    test('保存成功时 saved 为 true，磁盘上确实恢复了被删记录', () async {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      await provider.initialize();
      expect(provider.storageWriteBlocked, isFalse);

      final record = provider.addRecord(
        '张三',
        '表扬',
        const ['认真'],
        'class',
        '',
        date: _date,
      );
      expect(record, isNotNull);
      await flushWrites(provider);
      provider.deleteRecord(record!.id, date: _date);
      await flushWrites(provider);

      final result = await provider.undoLastRecordChange();
      expect(result.changed, 1);
      expect(result.saved, isTrue, reason: '落盘成功必须如实报告');

      final reloaded = await StorageService().loadData();
      final records = reloaded.data.recordsByDate[_date] ?? const [];
      expect(records.map((r) => r.id), contains(record.id),
          reason: '撤销结果必须已经写进磁盘，而不是只在内存里');
    });

    test('保存失败时 saved 为 false，不会谎报成功', () async {
      // 未 initialize 的 provider 没有可用存储，saveNow 必然失败。
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      final record = provider.addRecord(
        '张三',
        '表扬',
        const ['认真'],
        'class',
        '',
        date: _date,
      );
      provider.deleteRecord(record!.id, date: _date);

      final result = await provider.undoLastRecordChange();
      expect(result.changed, 1, reason: '内存里已经撤销');
      expect(result.saved, isFalse, reason: '磁盘没写成必须报告失败');
    });
  });
}
