import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/widgets/record_dialog.dart';
import 'package:class_management_system/widgets/record_list.dart';

import 'test_helpers.dart';

const _date = '2026-10-18';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('最近一次记录变更撤销', () {
    test('撤销单条新增记录', () {
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

      expect(provider.undoLastRecordChange(), 1);
      expect(provider.getRecordsForDate(_date), isEmpty);
      expect(provider.undoLastRecordChange(), 0);
    });

    test('撤销批量新增记录时整批一起删除', () {
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

      expect(provider.undoLastRecordChange(), 2);
      expect(provider.getRecordsForDate(_date), isEmpty);
    });

    test('撤销批量导入新增记录', () {
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
      expect(provider.undoLastRecordChange(), 2);
      expect(provider.getRecordsForDate(_date), isEmpty);
    });

    test('只撤销最近一次新增，更早的记录保留', () {
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

      expect(provider.undoLastRecordChange(), 1);
      final records = provider.getRecordsForDate(_date);
      expect(records, hasLength(1));
      expect(records.single.studentName, '张三');
    });

    test('撤销修改记录会恢复修改前内容', () {
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
      expect(provider.undoLastRecordChange(), 1);
      final restored = provider.getRecordsForDate(_date).single;
      expect(restored.operationType, '表扬');
      expect(restored.reasons, '认真');
      expect(restored.remark, '原备注');
      expect(notifications, greaterThan(0), reason: '撤销修改必须通知界面刷新');
      expect(provider.undoLastRecordChange(), 0);
    });

    test('修改记录时撤销快照先于界面通知就绪，监听者立即撤销不会误删原记录', () {
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

      var undoCount = 0;
      void listener() {
        if (undoCount != 0) return;
        final records = provider.getRecordsForDate(_date);
        if (records.length == 1 && records.single.operationType == '批评') {
          undoCount = provider.undoLastRecordChange();
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

      expect(undoCount, 1);
      final restored = provider.getRecordsForDate(_date);
      expect(restored, hasLength(1));
      expect(restored.single.operationType, '表扬');
      expect(restored.single.reasons, '认真');
    });

    test('撤销删除记录会恢复原记录及位置', () {
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
      expect(provider.undoLastRecordChange(), 1);
      final records = provider.getRecordsForDate(_date);
      expect(records, hasLength(2));
      expect(records.first.id, first.id);
      expect(records.first.studentName, '张三');
      expect(notifications, greaterThan(0), reason: '撤销删除必须通知界面刷新');
      expect(provider.undoLastRecordChange(), 0);
    });

    test('编辑后撤销的是修改，不会误删原新增记录', () {
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

      expect(provider.undoLastRecordChange(), 1);
      expect(provider.getRecordsForDate(_date), hasLength(1));
      expect(provider.getRecordsForDate(_date).single.operationType, '表扬');
    });

    test('删除后撤销的是删除，不会误删原新增记录', () {
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

      expect(provider.undoLastRecordChange(), 1);
      expect(provider.getRecordsForDate(_date), hasLength(1));
      expect(provider.getRecordsForDate(_date).single.id, record.id);
    });
  });

  testWidgets('撤销删除后记录立即重新出现在列表中', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = AppDataProvider();
    provider.addRecord(
      '张三',
      '表扬',
      const ['认真'],
      'class',
      '',
      date: _date,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
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
    expect(find.text('张三'), findsOneWidget);
    expect(find.text('已撤销本次记录'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('记录对话框提交后显示撤销按钮，点击可删除刚新增的记录', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = AppDataProvider();
    provider.setRecordDefaults(defaultType: 0, autoSelectPeriod: false);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
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
    expect(provider.getTodayRecords(), isEmpty);
    expect(find.text('已撤销本次记录'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
  });
}
