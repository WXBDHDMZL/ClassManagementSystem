/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:isolate';

import 'package:excel/excel.dart' as excel;

import '../constants/time_periods.dart';
import '../models/student_record.dart';
import '../utils/app_date.dart';
import '../utils/record_text.dart';
import '../utils/student_name.dart';
import 'statistics_service.dart';
import 'import_limits.dart';
import 'xlsx_reader.dart';

/// 导入预览结果：可导入的记录 + 供用户确认的统计信息。
class ImportPreview {
  const ImportPreview({
    required this.records,
    required this.skippedRows,
    required this.duplicates,
    required this.unknownStudents,
    this.duplicateImports = const [],
    this.fileDuplicates = 0,
    this.dateRange,
    this.error,
  });

  /// 解析成功、等待导入的记录（已带唯一 ID）。
  final List<StudentRecord> records;

  /// 缺姓名/操作项目/日期等必填内容而被跳过的行数。
  final int skippedRows;

  /// 与现有记录重复（日期+姓名+类型+时间段+时间+原因+备注）的**现有**记录，
  /// 勾选"覆盖重复"时需要先删除它们。
  final List<StudentRecord> duplicates;

  /// 上述重复行对应的**导入**记录：勾选"覆盖重复"时必须把它们写回去，
  /// 否则会出现"只删不写"导致数据丢失。
  final List<StudentRecord> duplicateImports;

  /// **文件内**重复（同一文件里完全相同的行）被跳过的行数（审计 P2-68：
  /// 此前静默跳过、预览与结果都不显示，用户对不上行数）。
  final int fileDuplicates;

  /// 名单里还没有的学生（去重，按出现顺序）。
  final List<String> unknownStudents;

  /// 记录日期范围："起 至 止"。
  final String? dateRange;

  /// 解析失败原因（文件格式不对、找不到表头等）。
  final String? error;

  bool get hasError => error != null;
  bool get hasData => records.isNotEmpty;
}

/// 记录导入服务：解析 Excel（.xlsx）与 CSV 表格，纯计算不涉及 UI。
/// 表头按名称识别，列顺序可任意；必需列为"日期""学生姓名""操作项目"。
class ImportService {
  ImportService._();

  /// 表头别名：值 → 可能的列名。
  static const List<String> _dateHeaders = ['日期'];
  static const List<String> _nameHeaders = ['学生姓名', '姓名'];
  static const List<String> _typeHeaders = ['操作项目', '类型'];
  static const List<String> _reasonHeaders = ['原因', '原因列表'];
  static const List<String> _periodHeaders = ['时间段', '时段'];
  static const List<String> _timeHeaders = ['时间'];
  static const List<String> _remarkHeaders = ['备注'];
  static const List<String> _recordedByHeaders = ['记录人'];

  static int _idCounter = 0;

  /// 解析 Excel 字节：在全部工作表中找第一个含记录表头的工作表。
  ///
  /// [periods] 是时段快照，供跨 isolate 调用时传入（见 [parseExcelBytesAsync]）。
  static ImportPreview parseExcelBytes(
    List<int> bytes, {
    required List<StudentRecord> existing,
    List<Map<String, String>>? periods,
  }) {
    try {
      // 审计 A-08：字节上限 + 行数上限，超限直接给可读错误，不静默截断。
      ImportLimits.ensureFileBytes(bytes.length, what: '表格文件');
      late List<List<List<String>>> sheets;
      try {
        final workbook = excel.Excel.decodeBytes(bytes);
        sheets = [
          for (final name in workbook.tables.keys)
            [
              for (final row in workbook.tables[name]!.rows)
                row.map((cell) => _cellText(cell?.value)).toList(),
            ],
        ];
      } on Object {
        final rows = XlsxReader.readRows(bytes);
        if (rows.isEmpty) rethrow;
        sheets = [rows];
      }
      for (final rows in sheets) {
        if (_findHeaderRow(rows) == null) continue;
        ImportLimits.ensureRowCount(rows.length);
        return _buildFromRows(rows, existing, periods);
      }
      return _failure('表格里没找到记录表头（需要包含"学生姓名""操作项目"等列）');
    } catch (e) {
      return _failure('读取 Excel 失败：$e');
    }
  }

  /// 解析 CSV 文本（UTF-8，支持带引号的字段）。
  static ImportPreview parseCsvText(
    String text, {
    required List<StudentRecord> existing,
    List<Map<String, String>>? periods,
  }) {
    try {
      final rows = _parseCsv(text);
      ImportLimits.ensureRowCount(rows.length, what: 'CSV 文件');
      if (_findHeaderRow(rows) == null) {
        return _failure('表格里没找到记录表头（需要包含"学生姓名""操作项目"等列）');
      }
      return _buildFromRows(rows, existing, periods);
    } catch (e) {
      return _failure('读取 CSV 失败：$e');
    }
  }

  /// [parseExcelBytes] 的隔离版本（性能批 H4）：xlsx 解码 + 全表判重是纯计算，
  /// 大表（数千行）可达数百毫秒，放后台 isolate 执行避免导入预览时冻结界面。
  /// [ImportPreview] 与 [StudentRecord] 都是纯数据对象，可安全跨 isolate 返回。
  ///
  /// 修复（2026-10-05 复查 P0）：时段状态**必须在这里（主 isolate）取快照**。
  /// `time_periods.dart` 的自定义时段是模块级可变全局，后台 isolate 读到的
  /// 是出厂值 —— 不传快照时，所有自定义时段都会反查失败、periodKey 落空串，
  /// 记录被静默归到"无时段"，且判重键变化导致同一条记录可被重复导入。
  static Future<ImportPreview> parseExcelBytesAsync(
    List<int> bytes, {
    required List<StudentRecord> existing,
  }) {
    final periods = effectivePeriods();
    return Isolate.run(
      () => parseExcelBytes(bytes, existing: existing, periods: periods),
    );
  }

  /// [parseCsvText] 的隔离版本（性能批 H4）：大 CSV 的逐字符解析 + 判重同样
  /// 放后台执行。注意调用方须先完成 [TransferService.decodeCsv] 的编码校验。
  ///
  /// 时段快照同[parseExcelBytesAsync]（P0 修复），必须在主 isolate 侧取。
  static Future<ImportPreview> parseCsvTextAsync(
    String text, {
    required List<StudentRecord> existing,
  }) {
    final periods = effectivePeriods();
    return Isolate.run(
      () => parseCsvText(text, existing: existing, periods: periods),
    );
  }

  // -------------------- 内部实现 --------------------

  /// 单元格文本（供分类导入导出服务复用）：日期型转成 yyyy-MM-dd。
  static String cellTextOf(excel.CellValue? value) => _cellText(value);

  /// CSV 行解析（供分类导入导出服务复用）。
  static List<List<String>> parseCsvRows(String text) => _parseCsv(text);

  /// 记录判重身份串（供数据包"补充导入"等复用，与表格导入**完全同口径**）。
  /// X-15：此前数据包补充导入自拼 `日期|姓名|类型|时间|原因`，漏了 **时段** 与
  /// **备注** —— 只有这两项不同的记录会被误判为重复而静默丢弃。
  static String recordIdentityKey(StudentRecord record) => _identityKey(
    record.date ?? '',
    record.studentName,
    record.operationType,
    record.timestamp,
    record.reasons,
    periodKey: record.periodKey,
    remark: record.remark,
  );

  static ImportPreview _failure(String message) {
    return ImportPreview(
      records: const [],
      skippedRows: 0,
      duplicates: const [],
      unknownStudents: const [],
      error: message,
    );
  }

  /// 单元格转文本：日期型转成 yyyy-MM-dd，其余取文本形式。
  static String _cellText(excel.CellValue? value) {
    if (value == null) return '';
    if (value is excel.DateCellValue) {
      final iso = value.asDateTimeLocal().toIso8601String();
      return iso.length >= 10 ? iso.substring(0, 10) : iso;
    }
    // 修复（1.5，2026-10-03 审查）：`DateTimeCellValue` 与 `DateCellValue`
    // 在 excel 包里是**兄弟类**（不是子类），只判 DateCellValue 会让"带时间"的
    // 日期格落到 `toString()` 分支得到 `2026-10-01T08:30:00.000Z`，
    // 拆分后段数≠3 → 整行被当成"日期缺失"跳过（用户看到"跳过 N 行"却不知原因）。
    if (value is excel.DateTimeCellValue) {
      final dateTime = value.asDateTimeLocal();
      final iso = dateTime.toIso8601String();
      // 修复（审计 P2-43）：带时间（非午夜）的单元格保留时分秒 —— Excel 的
      // "时间"型单元格（序列值 1899-12-31 08:30）此前被截成日期，再被
      // _normalizeTime 静默归零；日期列会在 _normalizeDate 里剥掉时间部分。
      final hasTime =
          dateTime.hour != 0 || dateTime.minute != 0 || dateTime.second != 0;
      if (hasTime && iso.length >= 19) {
        return '${iso.substring(0, 10)} ${iso.substring(11, 19)}';
      }
      return iso.length >= 10 ? iso.substring(0, 10) : iso;
    }
    // 审计 A-21：公式单元格（`=SUM(A1:A2)` 之类）在 excel 包里只有公式
    // 文本、没有缓存值。此前落到 `toString()`，把公式原文当成姓名/原因
    // 写进库：既污染数据，又让判重键与真实记录对不上。这里按"空单元格"
    // 处理，含公式必填列的行会被正常计入"跳过 N 行"。
    if (value is excel.FormulaCellValue) return '';
    return value.toString().trim();
  }

  /// 在开头若干行里找表头行：同时包含姓名列与操作项目列。
  static _HeaderMap? _findHeaderRow(List<List<String>> rows) {
    final limit = rows.length < 10 ? rows.length : 10;
    for (var i = 0; i < limit; i++) {
      final map = _matchHeader(rows[i]);
      if (map != null) {
        map.rowIndex = i;
        return map;
      }
    }
    return null;
  }

  static _HeaderMap? _matchHeader(List<String> row) {
    final map = _HeaderMap();
    for (var i = 0; i < row.length; i++) {
      final title = row[i].trim();
      if (title.isEmpty) continue;
      // 修复（审计 P2-44）：重名列统一 first-wins（此前日期/姓名/类型取最后
      // 一列、其余列取第一列；同一文件同时含"操作项目"和"类型"两列时会选错）。
      if (_dateHeaders.contains(title)) {
        map.date ??= i;
      } else if (_nameHeaders.contains(title)) {
        map.name ??= i;
      } else if (_typeHeaders.contains(title)) {
        map.type ??= i;
      } else if (_reasonHeaders.contains(title)) {
        map.reason ??= i;
      } else if (_periodHeaders.contains(title)) {
        map.period ??= i;
      } else if (_timeHeaders.contains(title)) {
        map.time ??= i;
      } else if (_remarkHeaders.contains(title)) {
        map.remark ??= i;
      } else if (_recordedByHeaders.contains(title)) {
        map.recordedBy ??= i;
      }
    }
    if (map.name == null || map.type == null) return null;
    return map;
  }

  static ImportPreview _buildFromRows(
    List<List<String>> rows,
    List<StudentRecord> existing, [
    List<Map<String, String>>? periods,
  ]) {
    final header = _findHeaderRow(rows);
    if (header == null) {
      return _failure('表格里没找到记录表头（需要包含"学生姓名""操作项目"等列）');
    }
    // V5 起日期列必填；旧版无日期列的表格直接拒绝，避免历史记录被写成今天。
    if (header.date == null) {
      return _failure('表格缺少“日期”列，V5.0.0 不再按今天导入。请使用当前版本重新导出记录。');
    }

    final existingKeys = <String>{};
    // 文件内判重必须独立于“与现有记录判重”，否则重复导入同一份文件时，
    // 每一行都会被当成“文件内重复”，界面数字虚高。
    final fileSeenKeys = <String>{};
    final existingByIdentity = <String, StudentRecord>{};
    // P2-10：另存一份"不含时间"的键表，供"表格没勾选时间列"时兜底判重。
    final existingByTimeAgnostic = <String, StudentRecord>{};
    for (final record in existing) {
      final key = _identityKey(
        record.date ?? '',
        record.studentName,
        record.operationType,
        record.timestamp,
        record.reasons,
        periodKey: record.periodKey,
        remark: record.remark,
      );
      existingKeys.add(key);
      existingByIdentity[key] = record;
      existingByTimeAgnostic[_identityKey(
            record.date ?? '',
            record.studentName,
            record.operationType,
            '00:00:00',
            record.reasons,
            periodKey: record.periodKey,
            remark: record.remark,
          )] =
          record;
    }

    final usedIds = existing.map((record) => record.id).toSet();
    final records = <StudentRecord>[];
    final duplicates = <StudentRecord>[];
    final duplicateImports = <StudentRecord>[];
    // X-6：同一条现有记录只允许对应一条"覆盖写回"记录。此前只有 duplicates
    // 去重、duplicateImports 不去重 —— 文件里同一条重复行出现两次（或两行都
    // 命中同一条现有记录）时，会写回两条，而旧记录只删一条 → 库里凭空多一条。
    final duplicateMatchIds = <String>{};
    final unknown = <String>[];
    final knownNames = <String>{
      for (final record in existing) record.studentName,
    };
    var skipped = 0;
    // 审计 P2-68：文件内重复行计入独立计数（此前静默跳过）。
    var fileDuplicates = 0;
    String? minDate;
    String? maxDate;

    for (var i = header.rowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      String cell(int? index) {
        if (index == null || index >= row.length) return '';
        return row[index].trim();
      }

      final name = cell(header.name);
      final type = cell(header.type);
      final date = _normalizeDate(cell(header.date!));
      if (name.isEmpty || date == null) {
        // 整行空白（表格末尾常见）不计入跳过数量。
        if (row.any((value) => value.trim().isNotEmpty)) skipped++;
        continue;
      }
      if (type != '表扬' && type != '批评') {
        skipped++;
        continue;
      }
      // 审计 A-04：记录导入此前只把超长姓名截断到 30 字（与名单导入
      // `validateStudentName` 直接拒绝的口径相反），前 30 字相同的两个人
      // 还会被合并成同一学生。这里与名单导入统一为"拒绝该行并计入跳过"。
      if (validateStudentName(name) != null) {
        skipped++;
        continue;
      }

      // 审计 A-21：时间写错（如 25:99）此前被静默归零成 00:00:00，
      // 用户以为导入成功、时间却变了。改为判定该行无效并计入跳过。
      final time = _normalizeTime(cell(header.time));
      if (time == null) {
        skipped++;
        continue;
      }
      final reasons = cell(header.reason);
      final periodText = cell(header.period);
      final periodKey = matchTimePeriodKey(periodText, periods);
      final remark = cell(header.remark);
      // 导出时旧记录写“未记录”，回导时按空处理，不能把它当成真实记录人。
      final recordedByText = cell(header.recordedBy);
      final recordedBy = recordedByText == '未记录' ? '' : recordedByText;
      final key = _identityKey(
        date,
        name,
        type,
        time,
        reasons,
        periodKey: periodKey,
        remark: remark,
      );

      // P2-10 修复：两侧同口径判重——表格带"时间"列时按完整键匹配；
      // 表格缺"时间"列时降级为"不含时间"键匹配（对应"导出时取消勾选时间列"
      // 的场景），避免同一份文件反复导入不断产生重复记录。
      final timeAgnosticKey = _identityKey(
        date,
        name,
        type,
        '00:00:00',
        reasons,
        periodKey: periodKey,
        remark: remark,
      );
      // 降级匹配的触发条件是"**该行时间为空**"，而不只是"表头缺时间列"：
      // 时间列存在但整列为空（用户在 Excel 里清空了值）同样要能判重。
      final rowHasNoTime = time.isEmpty || time == '00:00:00';
      final existingMatch =
          existingByIdentity[key] ??
          (rowHasNoTime ? existingByTimeAgnostic[timeAgnosticKey] : null);
      // 同一文件内部也判重：同一行出现两次只导入一条。
      final isFileDuplicate = !fileSeenKeys.add(key);
      if (isFileDuplicate) fileDuplicates++;
      if (existingMatch != null || isFileDuplicate) {
        // 修复（1.14，2026-10-03 审查）：只有"与现有记录重复"的行才进入
        // duplicateImports（勾选"覆盖重复"时写回它）；**文件内重复行只跳过**。
        // 此前 add 无条件执行，导致文件里同时存在"与库重复"和"文件内自重复"时，
        // 勾选覆盖会把自重复那行也写进库 → 库里凭空多出一条重复记录。
        if (existingMatch != null && duplicateMatchIds.add(existingMatch.id)) {
          // 同一条现有记录只记一次：避免"重复 N 条"计数虚高，也避免覆盖时写回多条。
          duplicates.add(existingMatch);
          duplicateImports.add(
            StudentRecord(
              id: _generateId(usedIds),
              studentName: name,
              operationType: type,
              reasons: reasons,
              periodKey: periodKey,
              periodName: periodKey.isEmpty
                  ? periodText
                  : getTimePeriodName(periodKey, periods),
              remark: remark,
              // 修复（1.15）：表格没给时间（00:00:00）时**沿用被覆盖记录的真实时间**，
              // 否则"覆盖重复"会把原本带时间的记录改写成午夜时刻。
              timestamp:
                  time == '00:00:00' && existingMatch.timestamp.isNotEmpty
                  ? existingMatch.timestamp
                  : time,
              isAppended: false,
              isImported: true,
              date: date,
              // 表格没带记录人时保留被覆盖记录的原记录人，避免导入擦除留痕。
              recordedBy: recordedBy.isEmpty
                  ? existingMatch.recordedBy
                  : recordedBy,
            ),
          );
        }
        continue;
      }

      records.add(
        StudentRecord(
          id: _generateId(usedIds),
          studentName: name,
          operationType: type,
          reasons: reasons,
          periodKey: periodKey,
          periodName: periodKey.isEmpty
              ? periodText
              : getTimePeriodName(periodKey, periods),
          remark: remark,
          timestamp: time,
          // 导入的历史记录标"导入"，与当天新记录、事后补录区分开。
          isAppended: false,
          isImported: true,
          date: date,
          recordedBy: recordedBy,
        ),
      );
      if (minDate == null || date.compareTo(minDate) < 0) minDate = date;
      if (maxDate == null || date.compareTo(maxDate) > 0) maxDate = date;
      if (!knownNames.contains(name)) {
        knownNames.add(name);
        unknown.add(name);
      }
    }

    return ImportPreview(
      records: records,
      skippedRows: skipped,
      duplicates: duplicates,
      duplicateImports: duplicateImports,
      fileDuplicates: fileDuplicates,
      unknownStudents: unknown,
      dateRange: minDate == null ? null : '$minDate 至 $maxDate',
    );
  }

  /// 归一化日期：支持 2026-09-01 / 2026/9/1 / 2026.9.1，以及带时间的写法。
  static String? _normalizeDate(String text) {
    if (text.isEmpty) return null;
    // 修复（复查 3.3）：网页版或第三方工具导出的日期列常是**文本型 ISO 串**
    // （`2026-10-01T08:30:00.000Z`）或带时间的文本（`2026-10-01 08:30:00`）。
    // 此前拆分后段数≠3 → 整行被判为"日期缺失"跳过（用户只看到"跳过 N 行"）。
    // 先剥掉时间部分：'T' / 't' / 空格之后的全部内容（含 Z 时区标记）。
    var value = text.trim();
    final cut = value.indexOf(RegExp(r'[Tt ]'));
    if (cut > 0) value = value.substring(0, cut);
    // 审计 P2-30：xlsx 兜底读取器会把日期单元格的序列号原样返回
    // （如 46357）。日期列拿到纯数字时按 Excel 1900 日期系统换算；
    // 限制在 1900-01-01 到 2100-12-31 的序列号范围，避免把学号等
    // 纯数字误当日期。
    final serial = double.tryParse(value);
    if (serial != null && serial >= 1 && serial <= 73415) {
      final date = DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
      if (date.year >= kMinSupportedYear && date.year <= kMaxSupportedYear) {
        return StatisticsService.dateString(date);
      }
      return null;
    }
    final normalized = value.replaceAll('/', '-').replaceAll('.', '-');
    final parts = normalized.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    // G-31：上界与下游统一为 kMaxSupportedYear（2100）——此前放行到 9999，
    // 2101+ 日期能过预览（提示"可导入 N 条"）却被下游 isValidYmdDate 静默丢弃。
    if (year < kMinSupportedYear || year > kMaxSupportedYear) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    // 2 月 31 日这类会被 DateTime 滚动到下个月，这里直接判为非法。
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return StatisticsService.dateString(date);
  }

  /// 归一化时间：支持 HH:mm 与 HH:mm:ss，缺失时用 00:00:00。
  ///
  /// 返回 null 表示"这一格写了时间但根本不合法"（如 25:99、8点半），
  /// 由调用方判定整行无效 —— 不再静默归零（审计 A-21）。
  static String? _normalizeTime(String text) {
    if (text.isEmpty) return '00:00:00';
    // 修复（审计 P2-43）：时间型单元格渲染为 "1899-12-31 08:30:00"，
    // 取最后一段（时分秒）再解析。
    var value = text.trim();
    final space = value.lastIndexOf(' ');
    if (space >= 0) value = value.substring(space + 1);
    final parts = value.split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '');
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '');
    if (hour == null || minute == null) return null;
    final second = int.tryParse(parts.length > 2 ? parts[2] : '') ?? 0;
    // G-32 + 审计 A-21：超范围既不静默钳制也不静默归零，直接判该行无效。
    if (hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        second < 0 ||
        second > 59) {
      return null;
    }
    return '${twoDigit(hour)}:${twoDigit(minute)}:${twoDigit(second)}';
  }

  /// 判重用的身份串：日期+姓名+类型+时间+原因。
  static String _identityKey(
    String date,
    String name,
    String type,
    String time,
    String reasons, {
    String periodKey = '',
    String remark = '',
  }) {
    // B-07：判重键必须与写入侧净化口径一致（trim/限长/顿号规范化），否则
    // “带空格/超长姓名”的表格会先被写成净化后的值，再导入时判重不命中 → 重复。
    final normalizedName = RecordText.normalizeName(name);
    final normalizedReasons = RecordText.normalizeReasons(reasons);
    final normalizedRemark = RecordText.normalizeRemark(remark);
    final normalizedDate = date.trim();
    final normalizedType = type.trim();
    // P2-10 修复：时间列缺失时归一化恒为 00:00:00，会让同一份文件反复导入
    // 不断产生重复记录；此时身份串降级为"不含时间"。
    final timePart = time.trim() == '00:00:00' ? '' : time.trim();
    return '$normalizedDate|$normalizedName|$normalizedType|$timePart|'
        '$normalizedReasons|${periodKey.trim()}|$normalizedRemark';
  }

  static String _generateId(Set<String> used) {
    var id = 'imp${DateTime.now().microsecondsSinceEpoch}${_idCounter++}';
    while (used.contains(id)) {
      id = 'imp${DateTime.now().microsecondsSinceEpoch}${_idCounter++}';
    }
    used.add(id);
    return id;
  }

  /// 极简 CSV 解析：支持双引号包裹字段（含逗号与换行）与 "" 转义。
  static List<List<String>> _parseCsv(String text) {
    var content = text;
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < content.length; i++) {
      final char = content[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < content.length && content[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(char);
        }
        continue;
      }
      if (char == '"') {
        inQuotes = true;
      } else if (char == ',') {
        row.add(field.toString());
        field.clear();
      } else if (char == '\n' || char == '\r') {
        if (char == '\r' && i + 1 < content.length && content[i + 1] == '\n') {
          i++;
        }
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else {
        field.write(char);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}

/// 表头列位置（null 表示该列不存在）。
class _HeaderMap {
  int rowIndex = 0;
  int? date;
  int? name;
  int? type;
  int? reason;
  int? period;
  int? time;
  int? remark;
  int? recordedBy;
}
