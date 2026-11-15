// 日常使用全流程回归（第 2 部分：批量导出 + 产物内容逐项校验）。
// 模拟老师一天结束后"一口气把该导的都导出来"：今日/单日/合并/全部记录、统计报表、
// 排名、个人汇总单、考勤表、名单、原因库、时间段、完整数据包。
// 每个产物都打开核对表头与关键单元格，并把导出的名单/原因库再解析回去验证闭环。
// 全程写在临时目录，绝不触碰用户真实数据文件。

import 'dart:io';

import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/services/transfer_service.dart';
import 'package:class_management_system/widgets/attendance_dialog.dart';
import 'package:class_management_system/widgets/history_dialog.dart';
import 'package:class_management_system/widgets/record_list.dart';
import 'package:class_management_system/widgets/settings_pages.dart';
import 'package:class_management_system/widgets/statistics_dialog.dart';
import 'package:class_management_system/widgets/student_picker_dialog.dart';

import 'test_helpers.dart';
import 'package:class_management_system/utils/app_clock.dart';

late Directory tempDir;
late AppDataProvider provider;

String get today => StatisticsService.todayString(AppClock.now());

/// 考勤对话框默认日期 = 归属日（X-12：跨零点时段的凌晨部分归属前一天）。
/// "考勤表"由对话框导出，用的是对话框默认日期，用例必须与生产同口径。
String get attendanceDate {
  final now = AppClock.now();
  return StatisticsService.dateString(
    attributionDay(now, matchPeriodByMinutes(now.hour * 60 + now.minute)),
  );
}

/// 统计看板当前区间（默认"本周"）。
String get rangeStart => StatisticsService.startOfWeek(
  AppClock.now(),
  weekStartDay: provider.appData.settings.weekStart,
);

Widget _wrap(Widget child) => ChangeNotifierProvider.value(
  value: provider,
  child: testApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SafeArea(child: child)),
  ),
);

/// 与 _wrap 相同，但补上真实设置面板里存在的**滚动容器**：
/// 数据页内容高于固定视口，
/// 真实界面靠设置面板的 SingleChildScrollView 承载；长内容用例用这个包裹，
/// 避免把"内容变长"误判成布局溢出。
Widget _wrapScrollable(Widget child) => ChangeNotifierProvider.value(
  value: provider,
  child: testApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: SafeArea(child: SingleChildScrollView(child: child)),
    ),
  ),
);

/// 通过 showDialog 打开对话框（对话框是独立路由，pop 不会带走根路由）。
Future<void> _pumpDialog(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: provider,
      child: testApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showDialog<void>(context: context, builder: (_) => dialog),
              child: const Text('打开对话框'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开对话框'));
  await tester.pumpAndSettle();
}

/// 等某个导出文件真正落盘（dart:io 写入是真实异步，pumpAndSettle 等不到）。
/// Windows 上杀软/索引器可能短暂占用刚写出的文件，因此不仅看存在与长度，
/// 还尝试以读方式打开一次，确认句柄已真正释放。
Future<void> _waitFor(WidgetTester tester, String name) async {
  final file = File('${tempDir.path}/$name');
  for (var i = 0; i < 400; i++) {
    if (file.existsSync() && file.lengthSync() > 0) {
      try {
        final handle = file.openSync(mode: FileMode.read);
        handle.closeSync();
        return;
      } on FileSystemException {
        // 刚改名完成但句柄尚未释放/被外部占用，继续等。
      }
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  fail('未生成导出文件：$name');
}

/// 跑掉顶部提示的 2 秒定时器。
Future<void> _drainSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

excel.Excel _readXlsx(String name) => excel.Excel.decodeBytes(
  File('${tempDir.path}/$name').readAsBytesSync(),
);

/// 某行文本（去掉尾部空列）。
List<String> _row(excel.Sheet sheet, int index) {
  if (index >= sheet.rows.length) return const [];
  final cells = sheet.rows[index]
      .map((cell) => cell?.value?.toString() ?? '')
      .toList();
  while (cells.isNotEmpty && cells.last.isEmpty) {
    cells.removeLast();
  }
  return cells;
}

/// 表头所在行的下标（导出表常在表头上方再放两行说明）。
int _headerRow(excel.Sheet sheet, String firstTitle) {
  for (var i = 0; i < sheet.rows.length; i++) {
    if (_row(sheet, i).isNotEmpty && _row(sheet, i).first == firstTitle) return i;
  }
  fail('未找到以「$firstTitle」开头的表头行');
}

void main() {
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cms_daily_export');
    provider = providerWithStudents(syntheticStudents(5));
    provider.setExportPath(tempDir.path);
    provider.setAttendanceEnabled(true);

    // —— 造一天的日常数据 ——
    final students = provider.appData.students;
    // 今天：2 条记录（表扬 + 批评）
    provider.addRecord(students[0], '表扬', const ['助人为乐'], 'class', '');
    provider.addRecord(students[1], '批评', const ['讲话'], 'noon_rest', '午休说话');
    // 两天前：2 条记录
    final past = StatisticsService.dateString(
      AppClock.now().subtract(const Duration(days: 2)),
    );
    provider.addRecord(students[0], '批评', const ['迟到'], 'morning_reading', '', date: past);
    provider.addRecord(students[2], '表扬', const ['认真读书'], 'morning_reading', '', date: past);
    // 考勤：1 条迟到（同时同步生成一条批评记录）
    provider.setAttendance(students[3], '迟到', date: today);
  });

  tearDown(() async {
    // N-1：导出文件的写入句柄可能还没完全释放（dart:io 真实异步写盘），
    // 先把写盘链等干净，再带重试删临时目录；清理失败不再判定为用例失败。
    await flushWrites(provider);
    await deleteDirectoryWithRetry(tempDir);
  });

  testWidgets('① 记录类导出：今日 / 单日 / 合并，表头与内容逐项正确', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // —— 今日记录（右侧面板的"导出今日记录"）——
    await tester.pumpWidget(_wrap(RecordList(records: provider.getTodayRecords())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出今日记录'));
    await tester.pumpAndSettle();
    await _waitFor(tester, '今日记录_$today.xlsx');

    final todaySheet = _readXlsx('今日记录_$today.xlsx').tables.values.first;
    final header = _headerRow(todaySheet, '日期');
    expect(_row(todaySheet, header), [
      '日期',
      '学生姓名',
      '操作项目',
      '原因',
      '时间段',
      '时间',
      '备注',
    ]);
    // 3 条记录（表扬 + 批评 + 考勤同步生成的批评）
    final dataRows = [
      for (var i = header + 1; i < todaySheet.rows.length; i++)
        if (_row(todaySheet, i).length >= 2 &&
            _row(todaySheet, i).first.length == 10)
          _row(todaySheet, i),
    ];
    expect(dataRows, hasLength(3));
    expect(dataRows.map((row) => row[1]), contains(provider.appData.students[3]));
    // 表尾附当天考勤异常
    final texts = [
      for (final row in todaySheet.rows)
        row.map((cell) => cell?.value?.toString() ?? '').join(),
    ];
    expect(texts.any((text) => text.contains('考勤异常')), isTrue);
    await _drainSnackBars(tester);

    // 修改5：关闭考勤功能后，记录导出不再附带考勤异常名单。
    provider.setAttendanceEnabled(false);
    await tester.pumpWidget(
      _wrap(RecordList(records: provider.getTodayRecords())),
    );
    await tester.pumpAndSettle();
    File('${tempDir.path}/今日记录_$today.xlsx').deleteSync();
    await tester.tap(find.text('导出今日记录'));
    await tester.pumpAndSettle();
    await _waitFor(tester, '今日记录_$today.xlsx');
    final noAttendanceSheet = _readXlsx('今日记录_$today.xlsx').tables.values.first;
    final noAttendanceTexts = [
      for (var i = 0; i < noAttendanceSheet.rows.length; i++)
        _row(noAttendanceSheet, i).join(),
    ];
    expect(
      noAttendanceTexts.any((text) => text.contains('考勤异常')),
      isFalse,
      reason: '修改5：未开启考勤功能时，记录导出不应包含考勤异常名单',
    );
    await _drainSnackBars(tester);

    // —— 历史记录：单日导出 + 合并导出 ——
    await _pumpDialog(tester, const HistoryDialog());
    final past = StatisticsService.dateString(
      AppClock.now().subtract(const Duration(days: 2)),
    );
    await tester.tap(find.text(past));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出记录'));
    await tester.pumpAndSettle();
    await _waitFor(tester, '$past.xlsx');

    final singleSheet = _readXlsx('$past.xlsx').tables.values.first;
    final singleHeader = _headerRow(singleSheet, '日期');
    expect(_row(singleSheet, singleHeader).first, '日期');
    final singleRows = [
      for (var i = singleHeader + 1; i < singleSheet.rows.length; i++)
        if (_row(singleSheet, i).length >= 2 &&
            _row(singleSheet, i).first == past)
          _row(singleSheet, i),
    ];
    expect(singleRows, hasLength(2), reason: '两天前的 2 条记录都应导出');
    await _drainSnackBars(tester);
  });

  testWidgets('② 统计类导出：报表（多工作表）/ 排名 / 个人汇总单', (tester) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const StatisticsDialog()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 报表
    await tester.ensureVisible(find.text('导出报表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出报表'));
    await tester.pumpAndSettle();
    await _waitFor(tester, '统计报表_${rangeStart}_至_$today.xlsx');

    final report = _readXlsx('统计报表_${rangeStart}_至_$today.xlsx');
    expect(
      report.tables.keys.toList(),
      containsAll(<String>['表扬汇总', '批评汇总', '明细', '每日统计', '对比与关注']),
    );
    expect(_row(report.tables['表扬汇总']!, 2), ['学生姓名', '表扬次数']);
    expect(_row(report.tables['批评汇总']!, 2), ['学生姓名', '批评次数']);
    expect(_row(report.tables['明细']!, 0), [
      '日期',
      '学生姓名',
      '操作项目',
      '原因',
      '时间段',
      '时间',
      '备注',
    ]);
    expect(_row(report.tables['每日统计']!, 0), ['日期', '表扬次数', '批评次数']);
    expect(_row(report.tables['对比与关注']!, 0), ['项目', '内容']);
    await _drainSnackBars(tester);

    // 排名
    await tester.tap(find.text('导出排名'));
    await tester.pumpAndSettle();
    await _waitFor(tester, '排名_${rangeStart}_至_$today.xlsx');
    final ranking = _readXlsx('排名_${rangeStart}_至_$today.xlsx');
    expect(ranking.tables.keys.toList(), containsAll(<String>['表扬排名', '批评排名']));
    expect(_row(ranking.tables['表扬排名']!, 1), ['排名', '学生姓名', '表扬次数']);
    expect(_row(ranking.tables['批评排名']!, 1), ['排名', '学生姓名', '批评次数']);
    await _drainSnackBars(tester);

    // 个人汇总单（需先选学生）
    await tester.tap(find.text('明细'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择学生'));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(StudentPickerDialog),
            matching: find.text(provider.appData.students[0]),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('个人汇总单'));
    await tester.pumpAndSettle();
    final personalName =
        '个人记录_${provider.appData.students[0]}_${rangeStart}_至_$today.xlsx';
    await _waitFor(tester, personalName);

    final personal = _readXlsx(personalName).tables.values.first;
    expect(
      _row(personal, _headerRow(personal, '日期')),
      ['日期', '时间段', '时间', '操作项目', '原因', '备注'],
    );
    final texts = [
      for (final row in personal.rows)
        row.map((cell) => cell?.value?.toString() ?? '').join(),
    ];
    expect(texts.any((text) => text.contains('合计')), isTrue);
    await _drainSnackBars(tester);
  });

  testWidgets('③ 分类导入收敛与数据包：记录 / 数据包 / 考勤表', (tester) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 对话框默认日期 = 归属日（X-12）。凌晨窗口内它与自然日不同，此时补一条
    // 落在归属日上的考勤，保证"考勤记录/数据包/考勤表"的各处口径一致
    //（正式使用中老师也是在对话框当前日期上登记）；白天两者相同，不会重复登记。
    if (attendanceDate != today) {
      provider.setAttendance(
        provider.appData.students[3],
        '迟到',
        date: attendanceDate,
      );
    }

    // 数据页内容高于固定视口：用带滚动容器的包裹（与真实设置面板一致）。
    await tester.pumpWidget(_wrapScrollable(const DataSettingsPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 分类入口已收敛：记录可导出/导入，名单只保留导入，其余走数据包。
    expect(find.text('原因库'), findsNothing);
    expect(find.text('时间段设置'), findsNothing);
    expect(find.text('考勤记录'), findsNothing);
    Finder categoryButton(String title, String label) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
      matching: find.text(label),
    );
    expect(categoryButton('学生名单', '导出'), findsNothing);
    expect(categoryButton('学生名单', '导入'), findsOneWidget);

    // 导出数据包
    await tester.ensureVisible(find.text('导出数据包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出数据包'));
    await tester.pumpAndSettle();
    // V2.40.0：数据包导出前增加明文/含姓名确认。
    await tester.tap(find.text('继续导出'));
    await tester.pumpAndSettle();
    final packageName = '班级管理系统_数据包_$today.json';
    await _waitFor(tester, packageName);
    await _drainSnackBars(tester);

    // —— 核对数据包内容 ——
    final package = TransferService.parsePackage(
      File('${tempDir.path}/$packageName').readAsStringSync(),
    );
    expect(package, isNotNull, reason: '数据包应能被自己解析回来');
    expect(package!.students.length, provider.appData.students.length);
    expect(package.records.length, provider.getRecordsForDates(provider.getHistoryDates()).length);
    expect(package.attendance.length, provider.getAllAttendance().length);
    expect(package.periods.length, provider.appData.settings.periods.length);
    expect(
      package.attendanceStatuses,
      provider.appData.settings.attendanceStatuses,
    );

    // —— 考勤表（考勤对话框内导出）——
    await _pumpDialog(tester, const AttendanceDialog());
    await tester.tap(find.text('导出考勤表'));
    await tester.pumpAndSettle();
    await _waitFor(tester, '考勤表_$attendanceDate.xlsx');
    final attendanceExport = _readXlsx('考勤表_$attendanceDate.xlsx').tables.values.first;
    expect(_row(attendanceExport, 0).first, contains('考勤日期'));
    expect(_row(attendanceExport, 1).first, contains('应到'));
    expect(_row(attendanceExport, 2).first, contains('异常情况'));
    expect(_row(attendanceExport, 3), [
      '日期',
      '学生姓名',
      '时间段',
      '考勤状态',
      '登记时间',
    ]);
    // 修改1：正常出勤不逐人列出，表尾汇总“其余正常出勤 N 人”。
    final attendanceTexts = [
      for (var i = 0; i < attendanceExport.rows.length; i++)
        _row(attendanceExport, i).join('|'),
    ];
    expect(attendanceTexts.any((text) => text.contains('其余正常出勤')), isTrue);
    final dayStats = provider.attendanceStats(attendanceDate);
    final normalCount = dayStats.total - dayStats.abnormalStudents;
    expect(
      attendanceTexts.any((text) => text.contains('其余正常出勤 $normalCount 人')),
      isTrue,
      reason: '汇总人数应为应到人数减去有异常记录的人数',
    );
    expect(
      attendanceTexts.any((text) => text.contains('|出勤|')),
      isFalse,
      reason: '正常出勤不应再逐人输出明细行',
    );
    // 每条明细都能被考勤导入解析（闭环）；考勤表只含当天，故与当天口径比较
    final reparsed = TransferService.parseAttendanceRows(
      TransferService.readRows(
        File('${tempDir.path}/考勤表_$attendanceDate.xlsx').readAsBytesSync(),
        isCsv: false,
      ),
    ).records;
    expect(reparsed, hasLength(provider.getAttendanceForDate(attendanceDate).length));
    expect(reparsed.first.studentName, isNotEmpty);
    await _drainSnackBars(tester);
  });
}
