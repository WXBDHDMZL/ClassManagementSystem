// 本轮"集中修复"的回归测试。
//
// 每条用例都对应一个已确认的缺陷，**修复前应当失败**（关键几条已用"临时回退"确认过
// 用例确实会变红），修复后必须通过。用内存数据 + 临时目录，绝不触碰真实数据文件。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/encrypted_text_file.dart';
import 'package:class_management_system/services/error_log_service.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/widgets/record_list.dart';
import 'package:class_management_system/widgets/statistics_dialog.dart';

import 'test_helpers.dart';
import 'package:class_management_system/utils/app_clock.dart';

String _today() => StatisticsService.todayString(AppClock.now());

Widget _statsWrap(AppDataProvider provider) => ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Center(child: StatisticsDialog())),
      ),
    );

void main() {
  group('统计看板缓存指纹（F-1）', () {
    late Directory temp;
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      temp = Directory.systemTemp.createTempSync('cms_stats_cache');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? temp.path
            : null,
      );
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      // N-1：异步写盘可能仍持有文件句柄，带重试删除，避免 tearDown 偶发失败。
      await deleteDirectoryWithRetry(temp);
    });

    testWidgets('同一天新增记录后，看板数字必须跟着变', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final provider = AppDataProvider();
      // 真实文件 I/O 必须在 runAsync 里进行，否则写盘链在假异步时区里不会完成。
      // 注意：这里只"给时间"，不 await 那条写盘链（否则会死等）。
      await tester.runAsync(() async {
        provider.addRecord('张三', '表扬', const ['认真听讲'], 'class', '');
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });

      await tester.pumpWidget(_statsWrap(provider));
      await tester.pump();
      expect(find.textContaining('表扬 1 次'), findsWidgets);

      // 同一天再记一条：旧实现用"有记录的天数"当缓存版本，天数不变 → 看板不会刷新
      await tester.runAsync(() async {
        provider.addRecord('李四', '表扬', const ['认真听讲'], 'class', '');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('表扬 2 次'),
        findsWidgets,
        reason: '缓存必须随数据失效（缓存指纹缺陷的回归用例）',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('统计"较上期"口径（F-5）', () {
    testWidgets('上一区间无记录时显示"暂无法对比"，与导出报表口径一致', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final provider = AppDataProvider();
      provider.addRecord('张三', '表扬', const ['认真听讲'], 'class', '');
      await tester.pumpWidget(_statsWrap(provider));
      await tester.pump();

      expect(find.textContaining('暂无法对比'), findsOneWidget);
      expect(
        find.textContaining('表扬 +'),
        findsNothing,
        reason: '上一区间没有记录时不应按 0 基准算差值',
      );
    });
  });

  group('单条写入与批量写入行为一致', () {
    test('isImported / 空时段键 / 考勤同步三项必须一致', () {
      final today = _today();
      final single = AppDataProvider()
        ..setAttendanceSyncMap(const {'迟到': '迟到'});
      single.addRecord('张三', '批评', const ['迟到'], '', '');

      final batch = AppDataProvider()
        ..setAttendanceSyncMap(const {'迟到': '迟到'});
      batch.addRecordsBatch(const [
        (
          studentName: '张三',
          operationType: '批评',
          reasons: <String>['迟到'],
          periodKey: '',
          remark: '',
          date: null,
        ),
      ]);

      final a = single.getTodayRecords().single;
      final b = batch.getTodayRecords().single;
      expect(b.periodKey, a.periodKey, reason: '两条路径的时段键处理必须一致');
      expect(b.periodKey, 'all_day', reason: '空时段键要规整为 all_day');
      expect(b.isImported, isFalse, reason: '批量写入不是"导入"');
      expect(b.isImported, a.isImported);
      expect(single.getAttendanceForDate(today), hasLength(1));
      expect(
        batch.getAttendanceForDate(today),
        hasLength(1),
        reason: '批量写入同样要登记考勤',
      );
    });

    test('批量写入日期非法时整条跳过', () {
      final provider = AppDataProvider();
      final added = provider.addRecordsBatch(const [
        (
          studentName: '张三',
          operationType: '批评',
          reasons: <String>['迟到'],
          periodKey: 'class',
          remark: '',
          date: '2026-99-99',
        ),
        (
          studentName: '张三',
          operationType: '批评',
          reasons: <String>['迟到'],
          periodKey: 'class',
          remark: '',
          date: null,
        ),
      ]);
      expect(added, 1);
      expect(provider.appData.recordsByDate.containsKey('2026-99-99'), isFalse);
    });
  });

  group('历史多日期列表（P-2）', () {
    testWidgets('多日期视图用 builder 渲染，大量记录不抛异常且可滚动', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final records = <StudentRecord>[
        for (var i = 0; i < 300; i++)
          StudentRecord(
            id: 'r$i',
            studentName: '学生${i % 50}',
            operationType: i.isEven ? '表扬' : '批评',
            reasons: '认真听讲',
            periodKey: 'class',
            periodName: '上课',
            remark: '',
            timestamp: '08:${(i % 60).toString().padLeft(2, '0')}:00',
            date: '2026-09-${(i % 28 + 1).toString().padLeft(2, '0')}',
          ),
      ];
      final dates = records.map((record) => record.date!).toSet().toList()
        ..sort();

      final provider = AppDataProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: RecordList(records: records, selectedDates: dates),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '多日期列表不应溢出或抛异常');
      expect(find.textContaining('学生'), findsWidgets);

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '滚动到底部也应正常（builder 按需构建）');
    });
  });

  group('错误日志通道（E-1）', () {
    test('被吞掉的错误会写进错误日志，便于排查', () async {
      final temp = Directory.systemTemp.createTempSync('cms_errlog');
      final storageRoot = Directory('${temp.path}/班级管理系统')
        ..createSync(recursive: true);
      addTearDown(() async {
        await deleteDirectoryWithRetry(temp);
      });
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? temp.path
            : null,
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
      });

      appendErrorLog('回归用例', '模拟被吞掉的错误', null);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // G-36：错误日志改为按月分文件（班级管理系统_错误日志_YYYY-MM.txt）。
      final log = File('${storageRoot.path}/日志/$errorLogFileName');
      expect(log.existsSync(), isTrue, reason: '错误日志文件应被创建');
      expect(
        await EncryptedTextFile.readAllText(log),
        contains('回归用例'),
      );
    });
  });

  // ===== 长度上限与权限裁剪一致性（V2.27.1 的 N-2 / N-3 / §3-5）=====

  group('长度上限全路径一致（N-2）', () {
    late Directory temp;
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      temp = Directory.systemTemp.createTempSync('cms_len_unify');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? temp.path
            : null,
      );
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      // N-1：异步写盘可能仍持有文件句柄，带重试删除，避免 tearDown 偶发失败。
      await deleteDirectoryWithRetry(temp);
    });

    test('新增 / 编辑 / 导入 三条路径的截断规则完全一致', () {
      final provider = AppDataProvider();
      final longRemark = 'R' * 250;
      final longName = 'X' * 40;

      // 新增
      provider.addRecord('新同学', '表扬', const ['A'], 'all_day', longRemark);
      final added = provider.appData.recordsByDate.values
          .expand((e) => e)
          .lastWhere((r) => r.studentName == '新同学');
      expect(added.remark.length, AppDataProvider.maxRemarkLength);
      final addedId = added.id;

      // 编辑
      provider.updateRecord(addedId, '表扬', const ['A'], 'all_day', longRemark);
      final edited = provider.appData.recordsByDate.values
          .expand((e) => e)
          .firstWhere((r) => r.id == addedId);
      expect(edited.remark.length, AppDataProvider.maxRemarkLength,
          reason: '编辑路径必须与新增同规则（此前编辑不截断）');

      // 导入
      provider.importRecords([
        StudentRecord(
          id: 'imp-len',
          studentName: longName,
          operationType: '表扬',
          reasons: 'A',
          periodKey: 'all_day',
          periodName: '全天',
          remark: longRemark,
          timestamp: '09:00:00',
          isImported: true,
          date: '2026-10-02',
        ),
      ]);
      final imported = provider.appData.recordsByDate.values
          .expand((e) => e)
          .firstWhere((r) => r.id == 'imp-len');
      expect(imported.studentName.length, AppDataProvider.maxNameLength,
          reason: '导入路径必须与新增同规则（此前导入完全不截断）');
      expect(imported.remark.length, AppDataProvider.maxRemarkLength);
    });

    test('导入保留原始时段名（不为规整而洗掉老师填的标签）', () {
      final provider = AppDataProvider();
      provider.importRecords([
        StudentRecord(
          id: 'imp-period',
          studentName: '张三',
          operationType: '表扬',
          reasons: '作业优秀',
          periodKey: '', // 外部表格时段无法识别
          periodName: '上午上课',
          remark: '',
          timestamp: '08:00:00',
          isImported: true,
          date: '2026-10-02',
        ),
      ]);
      final record = provider.appData.recordsByDate.values
          .expand((e) => e)
          .firstWhere((r) => r.id == 'imp-period');
      expect(record.periodName, '上午上课',
          reason: '时段键无法识别时必须保留原始时段名');
      expect(record.periodKey, isEmpty,
          reason: '空键是"无法识别"的有效信号，界面靠它退回显示原始名');
    });

    test('数据层不存在手写的 StudentRecord 构造（除唯一入口外）', () {
      // 去掉注释行再统计：文档注释里也会出现 `StudentRecord(...)` 字样。
      final source = File('lib/providers/app_data_provider.dart')
          .readAsStringSync()
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      final occurrences = RegExp(r'StudentRecord\(').allMatches(source).length;
      // 只允许 _buildRecord 里那一处 `return StudentRecord(`。
      expect(
        occurrences,
        1,
        reason: '记录构造必须收口到 _buildRecord；出现多处就是又漂移了（N-2 根因）',
      );
    });
  });

  group('名单与记录长度一致（N-3）', () {
    late Directory temp;
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      temp = Directory.systemTemp.createTempSync('cms_roster_len');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? temp.path
            : null,
      );
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      // N-1：异步写盘可能仍持有文件句柄，带重试删除，避免 tearDown 偶发失败。
      await deleteDirectoryWithRetry(temp);
    });

    test('超长姓名进不了名单，且给出可读原因', () {
      final provider = AppDataProvider();
      final tooLong = 'Y' * (AppDataProvider.maxNameLength + 1);
      expect(provider.addStudent(tooLong), isFalse,
          reason: '名单必须与记录侧同一上限，否则记录姓名被截断后与名单不等');
      expect(provider.appData.students.contains(tooLong), isFalse);

      final reason = AppDataProvider.validateStudentName(tooLong);
      expect(reason, isNotNull);
      expect(reason, contains('${AppDataProvider.maxNameLength}'));

      // 正常长度仍然可以加入
      expect(provider.addStudent('张三'), isTrue);
      expect(provider.renameStudent('张三', tooLong), isFalse,
          reason: '改名也不能绕过长度上限');
    });
  });

  group('R-1：旧数据 date 为空时不得被写成"今天"', () {
    // 构造"旧数据"：date 字段为 null（字段是后加的，老数据文件里就是空）。
    Map<String, dynamic> legacyJson({String? date}) => <String, dynamic>{
          'recordsByDate': <String, dynamic>{
            '2025-09-21': <Object?>[
              <String, Object?>{
                'id': 'dup-1',
                'studentName': '张三',
                'operationType': '表扬',
                'reasons': '认真听讲',
                'periodKey': 'all_day',
                'periodName': '全天',
                'remark': '',
                'timestamp': '08:00:00',
                'isAppended': false,
                'isImported': false,
                'date': date, // ← 旧数据这里缺失/为 null
              },
            ],
          },
          'students': <String>['张三'],
          'reasons': <String, dynamic>{},
          'settings': <String, dynamic>{},
          'attendanceByDate': <String, dynamic>{},
        };

    test('加载时用桶键回填 date（导出/编辑/删除三条路径同时变正确）', () {
      final data = AppData.fromJson(legacyJson());
      final record = data.recordsByDate['2025-09-21']!.single;
      expect(
        record.date,
        '2025-09-21',
        reason: '归属日期本来就是桶键；不回填会让导出日期空白、编辑与删除失效',
      );
    });

    test('date 已有值时保持原样（不覆盖，也不做无谓改动）', () {
      final data = AppData.fromJson(legacyJson(date: '2025-09-20'));
      expect(data.recordsByDate['2025-09-21']!.single.date, '2025-09-20');
    });

    test('id 重复触发修复后，date 仍等于桶键（不是今天）', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      // 同一桶里放两条 id 相同的记录 → 启动时 _repairDuplicateIds 会重建它们。
      final json = legacyJson();
      (json['recordsByDate']['2025-09-21'] as List)
          .add((json['recordsByDate']['2025-09-21'] as List).first);
      final data = AppData.fromJson(json);
      final provider = AppDataProvider();
      provider.loadForTest(data);
      final records = provider.appData.recordsByDate['2025-09-21']!;
      expect(records.length, 2);
      for (final record in records) {
        expect(
          record.date,
          '2025-09-21',
          reason: 'id 修复是"搬运既有数据"，日期必须回落到桶键而不是"今天"',
        );
        expect(record.date, isNot(_today()));
      }
    });

    test('id 修复的兜底独立有效：绕过 fromJson 直接喂空 date 也不写错', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      // 这条专门隔离 **_repairDuplicateIds 里的桶键兜底**（不经过 fromJson 的回填）：
      // 如果只有 fromJson 那一层防护，把 provider 里的兜底改回 `?? _getTodayString()`
      // 这条就会变红（已用临时回退确认）。
      final provider = AppDataProvider();
      StudentRecord legacy(String id, String name) =>
          StudentRecord.fromJson(<String, dynamic>{
            'id': id,
            'studentName': name,
            'operationType': '表扬',
            'reasons': '认真听讲',
            'periodKey': 'all_day',
            'periodName': '全天',
            'remark': '',
            'timestamp': '08:00:00',
            'isAppended': false,
            'isImported': false,
            'date': null,
          });
      // 两条同一 id → 触发重建。
      provider.loadForTest(
        AppData.fromJson(<String, dynamic>{'recordsByDate': <String, dynamic>{}})
          ..recordsByDate['2025-09-21'] = <StudentRecord>[
            legacy('same-id', '张三'),
            legacy('same-id', '李四'),
          ],
      );
      final records = provider.appData.recordsByDate['2025-09-21']!;
      expect(records.length, 2);
      // 判定口径：**被重建过的那条**（id 已不再是 same-id）日期必须是桶键。
      // 第一条 id 唯一、无需重建，保持原样（date 为 null），这里不管它——
      // 实际启动路径会先经 fromJson 回填，所以线上不会留下 null。
      final rebuilt = records.where((r) => r.id != 'same-id').toList();
      expect(rebuilt, hasLength(1), reason: '重复 id 的第二条应已被重新分配 id');
      expect(
        rebuilt.single.date,
        '2025-09-21',
        reason: 'id 修复重建记录时，日期兜底必须是桶键（今天会写坏历史数据）',
      );
    });

    test('改名后，date 仍等于桶键（不是今天）', () {
      final provider = AppDataProvider();
      // 用 fromJson 构造一条 date 真为 null 的记录（copyWith 的 `??` 清不掉 date）。
      final legacy = StudentRecord.fromJson(<String, dynamic>{
        'id': 'legacy-rename',
        'studentName': '张三',
        'operationType': '表扬',
        'reasons': '认真听讲',
        'periodKey': 'all_day',
        'periodName': '全天',
        'remark': '',
        'timestamp': '08:00:00',
        'isAppended': false,
        'isImported': false,
        'date': null,
      });
      expect(legacy.date, isNull);
      provider.appData.recordsByDate['2025-09-21'] = <StudentRecord>[legacy];
      // G-2：名单改为只读视图，测试同样必须走官方变更入口（不能再 ..clear()）。
      provider.appData.setStudents(<String>['张三']);

      expect(provider.renameStudent('张三', '张三丰'), isTrue);
      expect(
        provider.appData.recordsByDate['2025-09-21']!.single.date,
        '2025-09-21',
        reason: '改名迭代的是桶，日期兜底必须用桶键——用"今天"会把历史记录写错',
      );
    });
  });

  group('R-2：原因长度上限只作用于"新录入"，搬运既有数据保持原样', () {
    test('新录入的超长原因被裁剪到上限', () {
      final provider = AppDataProvider();
      final longReason = '很长的原因' * 30; // 远超 50 字
      provider.addRecord('张三', '表扬', <String>[longReason], 'all_day', '');
      final stored = provider.appData.recordsByDate.values.single.single.reasons;
      expect(
        stored.length,
        lessThanOrEqualTo(AppDataProvider.maxReasonLength),
        reason: '新录入的原因必须受 maxReasonLength 限制',
      );
    });

    test('导入的既有记录原因不被静默改写（搬运数据保持原样）', () {
      final provider = AppDataProvider();
      final longReason = '从外部导入的原始原因' * 20;
      final legacy = StudentRecord(
        id: 'legacy-1',
        studentName: '张三',
        operationType: '表扬',
        reasons: longReason,
        periodKey: 'all_day',
        periodName: '全天',
        remark: '',
        timestamp: '08:00:00',
        date: _today(),
      );
      provider.importRecords(<StudentRecord>[legacy]);
      final stored = provider.appData.recordsByDate.values
          .expand((list) => list)
          .single
          .reasons;
      expect(
        stored,
        longReason,
        reason: '导入是对既有数据的搬运，静默截断会改掉老师当初录入的内容',
      );
    });
  });
}
