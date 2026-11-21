/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.13.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:isolate';

import '../utils/app_date.dart';
import 'package:excel/excel.dart' as excel;

import '../constants/time_periods.dart';
import '../models/app_data.dart';
import '../models/app_settings.dart';
import '../models/attendance_record.dart';
import '../models/reason_library.dart';
import '../models/student_record.dart';
import 'import_service.dart';
import 'excel_export.dart';
import 'xlsx_reader.dart';

/// 考勤状态导入行：状态名称、是否计为未到、同步的批评原因。
class AttendanceStatusImportRow {
  const AttendanceStatusImportRow({
    required this.name,
    required this.absent,
    required this.syncReason,
  });

  final String name;
  final bool absent;
  final String syncReason;
}

/// 原因库导入行：类型（表扬/批评）、时段 key、原因文本。
class ReasonImportRow {
  const ReasonImportRow({
    required this.operationType,
    required this.periodKey,
    required this.reason,
  });

  final String operationType;
  final String periodKey;
  final String reason;
}

/// 数据包内容：换电脑时整包导出/导入用（不含管理密码哈希）。
class PackageData {
  const PackageData({
    required this.records,
    required this.students,
    required this.reasons,
    required this.periodLabels,
    this.attendance = const [],
    this.attendanceStatuses,
    this.attendanceAbsentStatuses,
    this.periods = const [],
    this.weekStart,
    this.attendanceEnabled,
    this.attendanceSyncMap,
    this.exportedAt,
    this.discardedRecordCount = 0,
  });

  final List<StudentRecord> records;
  final List<String> students;
  final ReasonLibrary reasons;
  final Map<String, String> periodLabels;

  /// 自定义时段列表（可增删）；为空表示出厂时段。
  final List<Map<String, String>> periods;

  /// 每周起始日（1=周一 … 7=周日）；**null = 旧数据包未包含该字段**，
  /// 导入时应保持本机现值（早期实现缺键回退 1，会把用户的周日设置悄悄重置）。
  final int? weekStart;

  /// 考勤功能开关；null = 旧数据包未包含该字段，导入时应保持本机现值。
  final bool? attendanceEnabled;

  /// 考勤状态 → 批评原因 的同步映射；
  /// null = 旧数据包未包含（保持本机现值），空映射 = 显式清空（审计 P2-33）。
  final Map<String, String>? attendanceSyncMap;
  final List<AttendanceRecord> attendance;

  /// 考勤状态项；null = 旧数据包未包含（保持本机现值，审计 P2-33）。
  final List<String>? attendanceStatuses;

  /// 哪些考勤状态算"未到"（影响"实到"人数）；换电脑时同样需要带走。
  /// null = 旧数据包未包含（保持本机现值），空列表 = 显式清空（审计 P2-33）。
  final List<String>? attendanceAbsentStatuses;
  final String? exportedAt;

  /// 解析数据包时因姓名/日期缺失被丢弃的记录条数（用于提示用户，避免静默丢失）。
  final int discardedRecordCount;
}

/// 导入导出服务：记录/学生名单表格与全部数据的数据包文件；原因库、时间段、考勤等随数据包维护。
/// 只负责序列化与解析，落盘与合并交给调用方。
class TransferService {
  TransferService._();

  static const String packageFormat = 'class_management_system.package';
  static const int packageVersion = 1;

  /// 读取表格为二维字符串数组（xlsx 选工作表，csv 直接解析）。
  ///
  /// X-17：多工作表时按 [headerKeywords]（该导入类型的表头词，如 名单的"姓名"）
  /// 在前 10 行内挑选**第一张**命中的工作表，与记录导入
  /// （[ImportService.parseExcelBytes]）同口径；此前无条件取第一张，工作表里
  /// 若封面/说明在前就会读错表（"解析不到内容"）。传了关键词却一张都不命中
  ///（如无表头的名单文件）时，退回第一张**非空**表，保持旧行为可用。
  static List<List<String>> readRows(
    List<int> bytes, {
    required bool isCsv,
    Set<String> headerKeywords = const {},
  }) {
    if (isCsv) {
      return ImportService.parseCsvRows(decodeCsv(bytes));
    }
    late List<List<List<String>>> sheets;
    try {
      final workbook = excel.Excel.decodeBytes(bytes);
      if (workbook.tables.isEmpty) return const [];
      sheets = <List<List<String>>>[
        for (final name in workbook.tables.keys)
          [
            for (final row in workbook.tables[name]!.rows)
              [for (final cell in row) ImportService.cellTextOf(cell?.value)],
          ],
      ];
    } on Object {
      final rows = XlsxReader.readRows(bytes);
      if (rows.isEmpty) rethrow;
      sheets = [rows];
    }
    if (headerKeywords.isNotEmpty) {
      for (final rows in sheets) {
        final limit = rows.length < 10 ? rows.length : 10;
        for (var i = 0; i < limit; i++) {
          if (rows[i].any((cell) => headerKeywords.contains(cell.trim()))) {
            return rows;
          }
        }
      }
    }
    for (final rows in sheets) {
      if (rows.any((row) => row.any((cell) => cell.trim().isNotEmpty))) {
        return rows;
      }
    }
    return sheets.first;
  }

  /// [readRows] 的隔离版本（性能批 H4）：xlsx 解码 + 逐格转文本是纯计算，
  /// 大表可达上百毫秒，放后台 isolate 执行避免导入时冻结界面。
  /// 异常语义与同步版一致（FormatException 等可原样重抛给调用方兜底）。
  static Future<List<List<String>>> readRowsAsync(
    List<int> bytes, {
    required bool isCsv,
    Set<String> headerKeywords = const {},
  }) {
    return Isolate.run(
      () => readRows(bytes, isCsv: isCsv, headerKeywords: headerKeywords),
    );
  }

  /// 解码 CSV：必须是 UTF-8（可带 BOM）。
  /// Excel 默认另存的 GBK/ANSI CSV 会解出乱码，这里直接报错让用户另存为 UTF-8，
  /// 避免乱码被写进名单/记录/原因。
  static String decodeCsv(List<int> bytes) {
    try {
      var text = utf8.decode(bytes);
      // 用转义写法而非字面量不可见字符，避免编辑器/复制粘贴时被抹掉。
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      return text;
    } on FormatException {
      throw const FormatException(
        'CSV 文件不是 UTF-8 编码（可能是 GBK/ANSI）：请在 Excel 里'
        '"另存为 → CSV UTF-8(逗号分隔)"，或改用 .xlsx 文件后重试',
      );
    }
  }

  // -------------------- 记录（按日期合并的表格）--------------------

  /// 全部记录导出为一张表（列可选）。
  ///
  /// [periods] 是时段快照，供跨 isolate 调用时传入（见 [buildRecordsXlsxAsync]）。
  static List<int> buildRecordsXlsx(
    List<StudentRecord> records, {
    List<String> columns = AppSettings.defaultRecordExportColumns,
    List<String> studentOrder = const [],
    List<Map<String, String>>? periods,
  }) {
    final file = ExcelExport.newWorkbook();
    final sheet = file['Sheet1'];
    final effectiveColumns = List<String>.from(columns);
    if (!effectiveColumns.contains('recordedBy') &&
        records.any((record) => record.recordedBy.isNotEmpty)) {
      effectiveColumns.add('recordedBy');
    }
    sheet.appendRow([
      for (final key in effectiveColumns)
        excel.TextCellValue(AppSettings.recordExportColumnTitles[key] ?? key),
    ]);
    final order = <String, int>{
      for (var i = 0; i < studentOrder.length; i++) studentOrder[i]: i,
    };
    final sorted = List<StudentRecord>.from(records)
      ..sort((a, b) {
        final byDate = (a.date ?? '').compareTo(b.date ?? '');
        if (byDate != 0) return byDate;
        final rankA = order[a.studentName] ?? studentOrder.length;
        final rankB = order[b.studentName] ?? studentOrder.length;
        if (rankA != rankB) return rankA.compareTo(rankB);
        return a.timestamp.compareTo(b.timestamp);
      });
    for (final record in sorted) {
      sheet.appendRow([
        for (final key in effectiveColumns)
          excel.TextCellValue(switch (key) {
            'date' => record.date ?? '',
            'name' => record.studentName,
            'type' => record.operationType,
            'reason' => record.reasons,
            'period' => periodNameForRecord(
              record.periodKey,
              record.periodName,
              periods,
            ),
            'time' => record.timestamp,
            // 修复（审计 P0-2）：默认导出列含"备注"，此前缺该分支导致备注列恒空；
            // 该文件再导入时按七字段判重会全部判不重、整批重复入库。
            'remark' => record.remark,
            'recordedBy' =>
              record.recordedBy.isEmpty ? '未记录' : record.recordedBy,
            // 修复（审查四 G-27）：未知列此前兜底成备注，会静默错填数据；改为留空。
            _ => '',
          }),
      ]);
    }
    // G-28：删除本地旧慢实现（`text.split('')` 逐字符建列表），改用服务层
    // `ExcelExport.autoFitColumns`（走 code units）——项目唯一实现，避免两份漂移。
    ExcelExport.autoFitColumns(sheet);
    return ExcelExport.encodeWorkbook(file);
  }

  /// [buildRecordsXlsx] 的隔离版本（性能批 H4）：全部记录动辄数千条，
  /// 组装 + 列宽 + 编码加起来可达数百毫秒；导出大表时放后台执行，
  /// 避免卡住界面。
  ///
  /// 修复（2026-10-05 复查 P0）：时段状态**必须在这里（主 isolate）取快照**。
  /// 自定义时段是模块级可变全局，后台 isolate 读到的是出厂值 —— 不传快照时
  /// "时间段"列会写出裸 key（如 `custom_xxx`）而非用户自定义的名称。
  static Future<List<int>> buildRecordsXlsxAsync(
    List<StudentRecord> records, {
    List<String> columns = AppSettings.defaultRecordExportColumns,
    List<String> studentOrder = const [],
  }) {
    final periods = effectivePeriods();
    return Isolate.run(
      () => buildRecordsXlsx(
        records,
        columns: columns,
        studentOrder: studentOrder,
        periods: periods,
      ),
    );
  }

  // -------------------- 名单 --------------------

  /// 导出名单：序号 + 姓名 两列。
  static List<int> buildStudentsXlsx(List<String> students) {
    final file = ExcelExport.newWorkbook();
    final sheet = file['Sheet1'];
    sheet.appendRow([excel.TextCellValue('序号'), excel.TextCellValue('姓名')]);
    for (var i = 0; i < students.length; i++) {
      sheet.appendRow([
        excel.IntCellValue(i + 1),
        excel.TextCellValue(students[i]),
      ]);
    }
    sheet.setColumnWidth(0, 8);
    sheet.setColumnWidth(1, 18);
    return ExcelExport.encodeWorkbook(file);
  }

  /// [buildStudentsXlsx] 的隔离版本（H4 收口）：名单一个班上限几十人，代价极小，
  /// 但仍统一"Excel 编码不占 UI 线程"的口径。不读时段全局态，无需快照。
  static Future<List<int>> buildStudentsXlsxAsync(List<String> students) {
    return Isolate.run(() => buildStudentsXlsx(students));
  }

  /// 解析名单：优先取"姓名/学生姓名"列，没有表头时取第一列。
  static List<String> parseStudentsRows(List<List<String>> rows) {
    final names = <String>[];
    final seenNames = <String>{};
    var nameColumn = 0;
    var dataStart = 0;
    // 修复（审计 P1-14）：与记录导入同口径 —— 在**前 10 行**内定位表头行；
    // 此前只扫第 0 行，带标题行（如"七年级3班名单"）的表格会把标题当姓名导入。
    for (var i = 0; i < rows.length && i < 10; i++) {
      final row = rows[i];
      var found = false;
      for (var c = 0; c < row.length; c++) {
        final title = row[c].trim();
        if (title == '姓名' || title == '学生姓名') {
          nameColumn = c;
          dataStart = i + 1;
          found = true;
          break;
        }
      }
      if (found) break;
    }
    for (var i = dataStart; i < rows.length; i++) {
      final row = rows[i];
      if (nameColumn >= row.length) continue;
      final name = row[nameColumn].trim();
      if (name.isEmpty) continue;
      if (name == '姓名' || name == '学生姓名') continue;
      // 修复（审查 六-7）：用 Set 判重，避免大名单下的 O(n²)。
      if (seenNames.add(name)) names.add(name);
    }
    return names;
  }

  // -------------------- 原因库 --------------------

  /// 导出原因库：类型 + 时段 + 原因 三列（时段用当前名称，便于阅读）。
  ///
  /// [periods] 是时段快照，供跨 isolate 调用时传入（见 [buildReasonsXlsxAsync]）——
  /// "时段"列要走时段表解析，后台 isolate 会丢自定义时段。
  static List<int> buildReasonsXlsx(
    ReasonLibrary library, {
    List<Map<String, String>>? periods,
  }) {
    final file = ExcelExport.newWorkbook();
    final sheet = file['Sheet1'];
    sheet.appendRow([
      excel.TextCellValue('类型'),
      excel.TextCellValue('时段'),
      excel.TextCellValue('原因'),
    ]);
    for (final type in const ['表扬', '批评']) {
      final groups = type == '表扬' ? library.praise : library.criticism;
      // 用当前生效时段（含自定义新增），并补上库里出现过的其它 key，避免漏导出。
      final keys =
          <String>{
            for (final item in periods ?? effectivePeriods()) item['key']!,
            ...groups.keys,
          }.toList()..sort(
            (a, b) => a == '_common'
                ? 1
                : b == '_common'
                ? -1
                : attendancePeriodOrder(a).compareTo(attendancePeriodOrder(b)),
          );
      for (final key in keys) {
        final reasons = groups[key];
        if (reasons == null) continue;
        for (final reason in reasons) {
          sheet.appendRow([
            excel.TextCellValue(type),
            excel.TextCellValue(
              key == '_common' ? '全时段通用' : getTimePeriodName(key, periods),
            ),
            excel.TextCellValue(reason),
          ]);
        }
      }
    }
    sheet.setColumnWidth(0, 8);
    sheet.setColumnWidth(1, 28);
    sheet.setColumnWidth(2, 24);
    return ExcelExport.encodeWorkbook(file);
  }

  /// [buildReasonsXlsx] 的隔离版本（H4 收口）：时段快照**必须在这里（主
  /// isolate）取**——后台 isolate 读不到自定义时段，"时段"列会写出裸 key。
  static Future<List<int>> buildReasonsXlsxAsync(ReasonLibrary library) {
    final periods = effectivePeriods();
    return Isolate.run(() => buildReasonsXlsx(library, periods: periods));
  }

  /// 解析原因库：类型 + 时段 + 原因；时段名称按当前时段与旧名称反查。
  ///
  /// G-29：无法识别的行（类型/原因/时段任一认不出）此前**静默跳过、毫无反馈**。
  /// 现通过 [onSkipped] 回传跳过行数，供界面提示。
  static List<ReasonImportRow> parseReasonsRows(
    List<List<String>> rows, {
    void Function(int skipped)? onSkipped,
  }) {
    final result = <ReasonImportRow>[];
    var skipped = 0;
    var start = 0;
    if (rows.isNotEmpty && rows.first.isNotEmpty) {
      final first = rows.first.map((cell) => cell.trim()).toList();
      if (first.contains('类型') || first.contains('原因')) {
        start = 1;
      }
    }
    for (var i = start; i < rows.length; i++) {
      final row = rows[i];
      String cell(int index) => index < row.length ? row[index].trim() : '';
      final type = cell(0);
      // 修复（1.11，2026-10-03 审查）：两列布局（类型/原因）时，第 1 列是**原因**
      // 而不是时段。
      // 修复（审计 P2-42）：布局改按**列数**判定（此前用"第 3 列是否为空"猜测，
      // `批评|上课|`（三列但原因为空）会被误判成两列、把时段名当原因导入）；
      // 三列行的原因为空时按无法识别跳过并计数。
      final isTwoColumn = row.length < 3;
      final periodText = isTwoColumn ? '' : cell(1);
      final reason = isTwoColumn ? cell(1) : cell(2);
      if (type != '表扬' && type != '批评') {
        skipped++;
        continue;
      }
      if (reason.isEmpty) {
        skipped++;
        continue;
      }
      final periodKey = periodText.isEmpty || periodText == '全时段通用'
          ? '_common'
          : matchTimePeriodKey(periodText);
      if (periodKey.isEmpty) {
        skipped++;
        continue;
      }
      result.add(
        ReasonImportRow(
          operationType: type,
          periodKey: periodKey,
          reason: reason,
        ),
      );
    }
    onSkipped?.call(skipped);
    return result;
  }

  // -------------------- 考勤状态配置 --------------------

  /// 导出考勤状态配置：状态名称 / 是否计为未到 / 同步批评原因。
  static List<int> buildAttendanceStatusesXlsx(
    List<String> statuses,
    Set<String> absentStatuses,
    Map<String, String> syncMap,
  ) {
    final file = ExcelExport.newWorkbook();
    final sheet = file['Sheet1'];
    sheet.appendRow([
      excel.TextCellValue('状态名称'),
      excel.TextCellValue('是否计为未到'),
      excel.TextCellValue('同步批评原因'),
    ]);
    for (final status in statuses) {
      sheet.appendRow([
        excel.TextCellValue(status),
        excel.TextCellValue(absentStatuses.contains(status) ? '是' : '否'),
        excel.TextCellValue(syncMap[status] ?? ''),
      ]);
    }
    sheet.setColumnWidth(0, 18);
    sheet.setColumnWidth(1, 16);
    sheet.setColumnWidth(2, 24);
    return ExcelExport.encodeWorkbook(file);
  }

  static Future<List<int>> buildAttendanceStatusesXlsxAsync(
    List<String> statuses,
    Set<String> absentStatuses,
    Map<String, String> syncMap,
  ) {
    return Isolate.run(
      () => buildAttendanceStatusesXlsx(statuses, absentStatuses, syncMap),
    );
  }

  /// 解析考勤状态配置；非法状态名（空/出勤等保留词）跳过。
  static List<AttendanceStatusImportRow> parseAttendanceStatusRows(
    List<List<String>> rows,
  ) {
    final result = <AttendanceStatusImportRow>[];
    final seen = <String>{};
    var start = 0;
    if (rows.isNotEmpty &&
        rows.first.isNotEmpty &&
        rows.first.first.trim() == '状态名称') {
      start = 1;
    }
    for (var i = start; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;
      final name = row[0].trim();
      if (name.isEmpty || AttendanceRecord.validateStatus(name) != null) {
        continue;
      }
      if (!seen.add(name)) continue;
      final absentText = row.length > 1 ? row[1].trim() : '';
      final absent = absentText == '是' ||
          absentText == '1' ||
          absentText.toLowerCase() == 'true';
      final reason = row.length > 2 ? row[2].trim() : '';
      result.add(
        AttendanceStatusImportRow(
          name: name,
          absent: absent,
          syncReason: reason,
        ),
      );
    }
    return result;
  }

  // -------------------- 时间段 --------------------

  /// 导出时间段：时段 key + 当前标签。
  ///
  /// [periods] 是时段快照，供跨 isolate 调用时传入（见 [buildPeriodsXlsxAsync]）——
  /// 导出内容就是时段表本身，后台 isolate 只会导出出厂 9 段。
  static List<int> buildPeriodsXlsx([List<Map<String, String>>? periods]) {
    final file = ExcelExport.newWorkbook();
    final sheet = file['Sheet1'];
    sheet.appendRow([excel.TextCellValue('时段'), excel.TextCellValue('标签')]);
    // 导出当前生效的时段（含自定义新增），而不是出厂固定列表。
    for (final item in periods ?? effectivePeriods()) {
      sheet.appendRow([
        excel.TextCellValue(item['key']!),
        excel.TextCellValue(item['label']!),
      ]);
    }
    sheet.setColumnWidth(0, 20);
    sheet.setColumnWidth(1, 36);
    return ExcelExport.encodeWorkbook(file);
  }

  /// [buildPeriodsXlsx] 的隔离版本（H4 收口）：时段快照**必须在这里（主
  /// isolate）取**——后台 isolate 读到的是出厂时段，用户自定义的增删改名全丢。
  static Future<List<int>> buildPeriodsXlsxAsync() {
    final periods = effectivePeriods();
    return Isolate.run(() => buildPeriodsXlsx(periods));
  }

  /// 解析时间段：返回**有序**的 `[{key, label}]`，供"按文件内容整体套用"使用。
  /// 第一列优先按 key 匹配——包含自定义新增时段的 key（形如 `custom_…`），
  /// 这样"导出时间段 → 导入时间段"才能完整还原增删与顺序；
  /// 认不出 key 时再按当前标签反查（兼容用户手写的表格）。
  static List<Map<String, String>> parsePeriodsRows(List<List<String>> rows) {
    final periods = <Map<String, String>>[];
    final seen = <String>{};
    var start = 0;
    if (rows.isNotEmpty &&
        rows.first.length > 1 &&
        rows.first[0].trim() == '时段') {
      start = 1;
    }
    final knownKeys = {for (final item in effectivePeriods()) item['key']!};
    for (var i = start; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 2) continue;
      final keyText = row[0].trim();
      final label = row[1].trim();
      if (label.isEmpty) continue;
      if (validatePeriodLabel(label) != null) continue;
      final String key;
      if (timePeriods.containsKey(keyText) || knownKeys.contains(keyText)) {
        key = keyText;
      } else {
        key = matchTimePeriodKey(keyText);
      }
      if (key.isEmpty || !seen.add(key)) continue;
      periods.add({'key': key, 'label': label});
    }
    return periods;
  }

  /// 把导入行组装成原因库（整体替换时使用）。
  static ReasonLibrary libraryFromRows(Iterable<ReasonImportRow> rows) {
    final praise = <String, List<String>>{};
    final criticism = <String, List<String>>{};
    for (final row in rows) {
      final target = row.operationType == '表扬' ? praise : criticism;
      target.putIfAbsent(row.periodKey, () => <String>[]);
      if (!target[row.periodKey]!.contains(row.reason)) {
        target[row.periodKey]!.add(row.reason);
      }
    }
    return ReasonLibrary(praise: praise, criticism: criticism);
  }

  /// 把原因库展开为导入行（数据包合并导入时使用）。
  static List<ReasonImportRow> rowsOfLibrary(ReasonLibrary library) {
    final rows = <ReasonImportRow>[];
    for (final type in const ['表扬', '批评']) {
      final groups = type == '表扬' ? library.praise : library.criticism;
      groups.forEach((periodKey, reasons) {
        for (final reason in reasons) {
          rows.add(
            ReasonImportRow(
              operationType: type,
              periodKey: periodKey,
              reason: reason,
            ),
          );
        }
      });
    }
    return rows;
  }

  // -------------------- 考勤 --------------------

  /// 导出全部考勤：日期 + 学生姓名 + 考勤状态 + 登记时间；
  /// 按日期从新到旧、同日按名单顺序排列。
  ///
  /// [periods] 是时段快照，供跨 isolate 调用时传入（见 [buildAttendanceXlsxAsync]）。
  static List<int> buildAttendanceXlsx(
    List<AttendanceRecord> records,
    List<String> studentOrder, [
    List<Map<String, String>>? periods,
    bool includeRecordedBy = false,
  ]) {
    final file = ExcelExport.newWorkbook();
    final sheet = file['Sheet1'];
    // 与记录导出一致：启用身份或已有记录人时增加“记录人”列。
    final withRecorder =
        includeRecordedBy ||
        records.any((record) => record.recordedBy.isNotEmpty);
    sheet.appendRow([
      excel.TextCellValue('日期'),
      excel.TextCellValue('学生姓名'),
      excel.TextCellValue('时间段'),
      excel.TextCellValue('考勤状态'),
      excel.TextCellValue('登记时间'),
      if (withRecorder) excel.TextCellValue('记录人'),
    ]);
    for (final record in sortAttendance(records, studentOrder)) {
      sheet.appendRow([
        excel.TextCellValue(record.date),
        excel.TextCellValue(record.studentName),
        excel.TextCellValue(
          record.periodName.isNotEmpty
              ? record.periodName
              : getTimePeriodName(record.periodKey, periods),
        ),
        excel.TextCellValue(record.status),
        excel.TextCellValue(record.timestamp),
        if (withRecorder)
          excel.TextCellValue(
            record.recordedBy.isEmpty ? '未记录' : record.recordedBy,
          ),
      ]);
    }
    sheet.setColumnWidth(0, 14);
    sheet.setColumnWidth(1, 16);
    sheet.setColumnWidth(2, 20);
    sheet.setColumnWidth(3, 14);
    sheet.setColumnWidth(4, 14);
    if (withRecorder) sheet.setColumnWidth(5, 20);
    return ExcelExport.encodeWorkbook(file);
  }

  /// [buildAttendanceXlsx] 的隔离版本（性能批 H4）：考勤累计一年可达数千条，
  /// 排序 + 组装 + 编码放后台执行，避免"导出考勤"点击后界面冻结。
  ///
  /// 修复（2026-10-05 复查 P0）：时段快照同 [buildRecordsXlsxAsync]，
  /// 必须在主 isolate 侧取，否则"时间段"列写出裸 key。
  static Future<List<int>> buildAttendanceXlsxAsync(
    List<AttendanceRecord> records,
    List<String> studentOrder, {
    bool includeRecordedBy = false,
  }) {
    final periods = effectivePeriods();
    return Isolate.run(
      () => buildAttendanceXlsx(
        records,
        studentOrder,
        periods,
        includeRecordedBy,
      ),
    );
  }

  /// 考勤排序：日期从新到旧，同日期按名单顺序（不在名单里的排在后面）。
  static List<AttendanceRecord> sortAttendance(
    List<AttendanceRecord> records,
    List<String> studentOrder,
  ) {
    final order = {
      for (var i = 0; i < studentOrder.length; i++) studentOrder[i]: i,
    };
    // 名单顺序里"查不到该学生"时的哨兵名次：远大于任何班额，排到最后。
    const int unknownRosterRank = 1 << 20;
    final sorted = List<AttendanceRecord>.from(records)
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        final byName = (order[a.studentName] ?? unknownRosterRank).compareTo(
          order[b.studentName] ?? unknownRosterRank,
        );
        if (byName != 0) return byName;
        return a.studentName.compareTo(b.studentName);
      });
    return sorted;
  }

  /// 解析考勤表格：需要"日期 / 学生姓名 / 考勤状态"三列
  /// （时间段、登记时间、记录人可选）。
  /// **优先按表头列名定位各列**（用户在 Excel 里调换列顺序也不会错位）；
  /// 没有表头时退回旧的固定列序：新格式为"日期/姓名/时间段/状态/时间"，
  /// 更旧的格式为"日期/姓名/状态[/时间]"（按"全天"处理）。
  /// 返回的记录 id 为空，由导入方按需分配。
  static ({List<AttendanceRecord> records, int skipped}) parseAttendanceRows(
    List<List<String>> rows, {
    void Function(int skippedRows)? onSkipped,
  }) {
    var skipped = 0;
    int? colDate;
    int? colName;
    int? colPeriod;
    int? colStatus;
    int? colTime;
    int? colRecordedBy;
    var start = 0;
    for (var i = 0; i < rows.length && i < 10; i++) {
      final cells = rows[i].map((cell) => cell.trim()).toList();
      // 修复（审计 P1-15）：此前"含任一关键词"就锚定 —— 只含"日期"或只含
      // "学生姓名"的行会被误认成表头，且缺"考勤状态"导致整表降级为固定列序。
      // 改为三个必备列（日期/学生姓名/考勤状态）齐全才锚定。
      if (!cells.contains('日期') ||
          !cells.contains('学生姓名') ||
          !cells.contains('考勤状态')) {
        continue;
      }
      colDate = cells.indexOf('日期');
      colName = cells.indexOf('学生姓名');
      colPeriod = cells.contains('时间段') ? cells.indexOf('时间段') : null;
      colStatus = cells.indexOf('考勤状态');
      colTime = cells.contains('登记时间') ? cells.indexOf('登记时间') : null;
      colRecordedBy = cells.contains('记录人')
          ? cells.indexOf('记录人')
          : null;
      start = i + 1;
      break;
    }
    final hasHeader = colDate != null && colName != null && colStatus != null;
    var hasPeriodColumn = false;
    if (!hasHeader) {
      for (final row in rows) {
        if (row.any((cell) => cell.trim() == '时间段')) {
          hasPeriodColumn = true;
          break;
        }
      }
    }

    final result = <AttendanceRecord>[];
    for (var i = start; i < rows.length; i++) {
      final row = rows[i];
      String cell(int? index) =>
          index != null && index >= 0 && index < row.length
          ? row[index].trim()
          : '';
      var date = hasHeader ? cell(colDate) : cell(0);
      // 修复（审计 P2-43）：Excel 日期型单元格可能渲染成 "yyyy-MM-dd HH:mm:ss"，
      // 取日期段再校验。
      final dateCut = date.indexOf(' ');
      if (dateCut > 0) date = date.substring(0, dateCut);
      final name = hasHeader ? cell(colName) : cell(1);
      final periodText = hasHeader
          ? cell(colPeriod)
          : (hasPeriodColumn ? cell(2) : '');
      final status = hasHeader
          ? cell(colStatus)
          : (hasPeriodColumn ? cell(3) : cell(2));
      var timestamp = hasHeader
          ? cell(colTime)
          : (hasPeriodColumn ? cell(4) : cell(3));
      // 导出时旧记录写“未记录”，回导时按空处理，不能把它当成真实记录人。
      final recordedByText = cell(colRecordedBy);
      final recordedBy = recordedByText == '未记录' ? '' : recordedByText;
      // 修复（审计 P2-43）：时间型单元格渲染带日期前缀（"1899-12-31 08:30:00"），
      // 取最后一段（时分秒）。
      final timeSpace = timestamp.lastIndexOf(' ');
      if (timeSpace >= 0) timestamp = timestamp.substring(timeSpace + 1);
      if (name.isEmpty || status.isEmpty) continue;
      // 日期必须是真实存在的公历日期（P1-3 修复：此前只查形状，2026-13-45 会入库）。
      if (!isValidYmdDate(date)) {
        skipped++;
        continue;
      }
      // 考勤表里"未登记的学生 = 出勤"只是展示行，导入时忽略。
      if (status == AttendanceRecord.presentStatus) continue;
      var periodKey = AttendanceRecord.allDayKey;
      if (periodText.isNotEmpty && periodText != AttendanceRecord.allDayLabel) {
        periodKey = matchTimePeriodKey(periodText);
        if (periodKey.isEmpty) periodKey = AttendanceRecord.allDayKey;
      }
      result.add(
        AttendanceRecord(
          id: '',
          studentName: name,
          status: status,
          date: date,
          periodKey: periodKey,
          // B-06：保存表格里的时段显示名（无法识别时也原样保留），
          // 避免之后时段被删/改名时历史考勤退化成内部 key。
          periodName: periodText.isNotEmpty
              ? periodText
              : getTimePeriodName(periodKey),
          timestamp: timestamp,
          recordedBy: recordedBy,
        ),
      );
    }
    onSkipped?.call(skipped);
    return (records: result, skipped: skipped);
  }

  // -------------------- 数据包 --------------------

  /// 生成数据包 JSON（不含管理密码哈希）。
  static String buildPackage(AppData data, {required String exportedAt}) {
    return const JsonEncoder.withIndent('  ').convert({
      'format': packageFormat,
      'version': packageVersion,
      'exportedAt': exportedAt,
      'students': data.students,
      'periodLabels': data.settings.periodLabels,
      // 自定义时段（可增删）、每周起始日、考勤开关与同步映射：
      // 换电脑时这些设置同样需要带走，否则恢复后与原来不一致。
      'periods': data.settings.periods,
      'weekStart': data.settings.weekStart,
      'attendanceEnabled': data.settings.attendanceEnabled,
      'attendanceSyncMap': data.settings.attendanceSyncMap,
      'reasons': data.reasons.toJson(),
      'attendanceStatuses': data.settings.attendanceStatuses,
      'attendanceAbsentStatuses': data.settings.attendanceAbsentStatuses,
      'records': [
        for (final records in data.recordsByDate.values)
          for (final record in records) record.toJson(),
      ],
      'attendance': [
        for (final records in data.attendanceByDate.values)
          for (final record in records) record.toJson(),
      ],
    });
  }

  /// 解析数据包：格式不符返回 null；单条记录损坏时跳过。
  static PackageData? parsePackage(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return null;
      if (json['format'] != packageFormat) return null;
      final version = json['version'];
      if (version is! int || version > packageVersion) return null;

      final records = <StudentRecord>[];
      var discardedRecords = 0;
      final recordsJson = json['records'];
      if (recordsJson is List) {
        for (final item in recordsJson) {
          try {
            if (item is Map<String, dynamic>) {
              final record = StudentRecord.fromJson(item);
              // 姓名或日期缺失的记录无法归档，直接跳过（防损坏数据）。
              // 日期空串与 null 同义：两者都定位不到日期桶。
              if (record.studentName.trim().isEmpty ||
                  record.date == null ||
                  record.date!.isEmpty) {
                discardedRecords++;
                continue;
              }
              records.add(record);
            }
          } catch (_) {
            // 跳过损坏的单条记录
          }
        }
      }

      final students = <String>[];
      final studentsJson = json['students'];
      if (studentsJson is List) {
        for (final item in studentsJson) {
          final name = item.toString().trim();
          if (name.isNotEmpty) students.add(name);
        }
      }

      final labels = <String, String>{};
      final labelsJson = json['periodLabels'];
      if (labelsJson is Map) {
        labelsJson.forEach((key, value) {
          if (key is String && value is String && value.isNotEmpty) {
            labels[key] = value;
          }
        });
      }

      final reasonsJson = json['reasons'];
      final reasons = reasonsJson is Map<String, dynamic>
          ? ReasonLibrary.fromJson(reasonsJson)
          : ReasonLibrary.defaults();

      // 考勤为新增字段：旧数据包里没有该字段时按空处理。
      final attendance = <AttendanceRecord>[];
      final attendanceJson = json['attendance'];
      if (attendanceJson is List) {
        for (final item in attendanceJson) {
          try {
            if (item is! Map<String, dynamic>) continue;
            final record = AttendanceRecord.fromJson(item);
            if (record.studentName.trim().isEmpty || record.date.isEmpty) {
              continue;
            }
            attendance.add(record);
          } catch (_) {
            // 跳过损坏的单条考勤记录
          }
        }
      }

      // 审计 P2-33：字段**缺失**（旧包）解析为 null → 导入时保持本机现值；
      // 显式给出的列表（可为空）按包内内容处理。
      List<String>? attendanceStatuses;
      final statusesJson = json['attendanceStatuses'];
      if (statusesJson is List) {
        final built = <String>[];
        for (final item in statusesJson) {
          final value = item.toString().trim();
          if (value.isNotEmpty && !built.contains(value)) {
            built.add(value);
          }
        }
        attendanceStatuses = built;
      }

      // 同上（审计 P2-33）。
      List<String>? absentStatuses;
      final absentJson = json['attendanceAbsentStatuses'];
      if (absentJson is List) {
        final built = <String>[];
        for (final item in absentJson) {
          final value = item.toString().trim();
          if (value.isNotEmpty && !built.contains(value)) {
            built.add(value);
          }
        }
        absentStatuses = built;
      }

      // 新增字段：旧数据包没有时用默认值，保证向后兼容。
      final periods = <Map<String, String>>[];
      final periodsJson = json['periods'];
      if (periodsJson is List) {
        for (final item in periodsJson) {
          if (item is! Map) continue;
          final key = item['key'];
          final label = item['label'];
          if (key is String && label is String && key.isNotEmpty) {
            periods.add({'key': key, 'label': label});
          }
        }
      }
      // 审计 P1-18：缺失该键时返回 null（"包内未包含"）—— 导入侧据此保持
      // 本机值，不再把用户的"每周起始日=周日"悄悄重置为周一。
      final weekStartValue = json['weekStart'];
      final int? weekStart =
          weekStartValue is int && weekStartValue >= 1 && weekStartValue <= 7
          ? weekStartValue
          : null;
      // 审计 P2-33：缺失 = null（保持本机），显式给出（可为空映射）= 按包内内容。
      Map<String, String>? syncMap;
      final syncJson = json['attendanceSyncMap'];
      if (syncJson is Map) {
        final statusList = attendanceStatuses;
        final built = <String, String>{};
        syncJson.forEach((key, value) {
          if (key is! String || value is! String || value.isEmpty) return;
          // S-10：映射的状态键必须是包内真实存在的考勤状态，否则会生成指向
          // "幽灵状态"的同步映射（考勤里永远不会出现该状态，映射永不命中）。
          // 旧包没带状态列表时（null）不做此过滤，保持兼容。
          if (statusList != null && !statusList.contains(key)) {
            return;
          }
          built[key] = value;
        });
        syncMap = built;
      }

      return PackageData(
        records: records,
        students: students,
        reasons: reasons,
        periodLabels: labels,
        periods: periods,
        weekStart: weekStart,
        // 审计 P1-18：缺失该键时为 null（保持本机值），不再回退 false 关掉考勤。
        attendanceEnabled: json['attendanceEnabled'] is bool
            ? json['attendanceEnabled'] as bool
            : null,
        attendanceSyncMap: syncMap,
        attendance: attendance,
        attendanceStatuses: attendanceStatuses,
        attendanceAbsentStatuses: absentStatuses,
        exportedAt: json['exportedAt']?.toString(),
        discardedRecordCount: discardedRecords,
      );
    } catch (_) {
      return null;
    }
  }

  /// 解析数据包字节：**严格 UTF-8**（非 UTF-8 直接抛 [FormatException]）。
  /// 数据包一律由本程序以 UTF-8 导出；此前 allowMalformed 会把 GBK 乱码
  /// 静默替换为 � 后照常入库（姓名等全部变坏），属"宁可报错也不能入库
  /// 坏数据"场景（与记录表格导入同口径）。
  static PackageData? parsePackageBytes(List<int> bytes) {
    return parsePackage(utf8.decode(bytes));
  }

}
