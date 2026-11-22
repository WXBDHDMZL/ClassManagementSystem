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

import '../models/app_settings.dart';
import '../models/attendance_record.dart';
import '../models/student_record.dart';
import '../utils/app_date.dart';

/// 统计汇总指标：表扬总数、批评总数、记录天数、涉及学生数。
class StatisticsSummary {
  final int praiseCount;
  final int criticizeCount;

  /// 有记录的天数（去重后的日期数量）
  final int recordDays;

  /// 涉及的学生人数（去重后的学生数量）
  final int studentCount;

  const StatisticsSummary({
    required this.praiseCount,
    required this.criticizeCount,
    required this.recordDays,
    required this.studentCount,
  });

  /// 表扬 + 批评的记录总条数
  int get totalCount => praiseCount + criticizeCount;
}

/// 区间考勤统计结果。
///
/// 考勤功能关闭后，统计页面不再调用；底层数据与 DLC 能力保留。
class AttendanceStatsResult {
  const AttendanceStatsResult({
    required this.byStatus,
    required this.studentRanking,
    required this.totalRecords,
  });

  /// 状态 → 人次（按人次降序）。
  final Map<String, int> byStatus;

  /// 按学生的异常次数排行（次数降序）。
  final List<StudentCount> studentRanking;

  /// 异常记录总条数。
  final int totalRecords;

  /// 涉及学生数。
  int get studentCount => studentRanking.length;

  /// 状态分布的占比（0~1），用于饼图。
  double ratioOf(String status) =>
      totalRecords == 0 ? 0 : (byStatus[status] ?? 0) / totalRecords;
}

/// 单名学生某一类操作的排名项（次数降序排列后的元素）。
class StudentCount {
  final String name;
  final int count;

  const StudentCount({required this.name, required this.count});
}

/// 单名学生的表扬/批评合计，用于统计看板与分类型汇总。
class StudentTotal {
  final String name;
  final int praiseCount;
  final int criticizeCount;

  const StudentTotal({
    required this.name,
    required this.praiseCount,
    required this.criticizeCount,
  });

  /// 表扬 + 批评总数
  int get total => praiseCount + criticizeCount;
}

/// 某一天的表扬/批评条数，供趋势图使用。
class DailyCount {
  /// 日期（yyyy-MM-dd）
  final String date;
  final int praiseCount;
  final int criticizeCount;

  const DailyCount({
    required this.date,
    required this.praiseCount,
    required this.criticizeCount,
  });
}

/// 单名学生在指定范围内的明细与次数。
class StudentStatistics {
  final String studentName;
  final int praiseCount;
  final int criticizeCount;

  /// 该范围内的逐条记录（按日期、时间升序）
  final List<StudentRecord> records;

  const StudentStatistics({
    required this.studentName,
    required this.praiseCount,
    required this.criticizeCount,
    required this.records,
  });

  /// 表扬 + 批评总数
  int get total => praiseCount + criticizeCount;
}

/// 完整的统计结果：汇总 + 排行榜 + 按天计数 + 学生合计。
class StatisticsResult {
  final StatisticsSummary summary;

  /// 表扬排行榜（次数降序）
  final List<StudentCount> praiseRanking;

  /// 批评排行榜（次数降序）
  final List<StudentCount> criticizeRanking;

  /// 全部学生的表扬/批评合计（表扬次数降序）
  final List<StudentTotal> studentTotals;

  /// 按天计数（日期升序）
  final List<DailyCount> dailyCounts;

  /// 参与统计的全部记录
  final List<StudentRecord> records;

  const StatisticsResult({
    required this.summary,
    required this.praiseRanking,
    required this.criticizeRanking,
    required this.studentTotals,
    required this.dailyCounts,
    required this.records,
  });

  /// 范围内是否没有任何记录
  bool get isEmpty => records.isEmpty;
}

/// 数据统计服务：纯计算，不依赖任何 UI 组件。
class StatisticsService {
  /// 并列名次（"1、1、2…"式连续编号）：同次数共享同名次，名次连续递增。
  /// 界面排行条与导出"排名"表共用同一口径（审计 P1-21）。
  static List<int> denseRanks(Iterable<int> counts) {
    final ranks = <int>[];
    var rank = 0;
    int? previous;
    for (final count in counts) {
      if (previous == null || count != previous) {
        rank++;
        previous = count;
      }
      ranks.add(rank);
    }
    return ranks;
  }

  /// 按区间长度取"需关注学生"的批评阈值：
  /// 一周（≤[attentionWeekMaxDays] 天）用周值、一个月（≤[attentionMonthMaxDays] 天）
  /// 用月值、更长（学期 / 全部记录）用学期值。
  static const int attentionWeekMaxDays = 10;
  static const int attentionMonthMaxDays = 45;

  static int attentionThresholdForDays(
    int days, {
    required int weekly,
    required int monthly,
    required int semester,
  }) {
    if (days <= attentionWeekMaxDays) return weekly;
    if (days <= attentionMonthMaxDays) return monthly;
    return semester;
  }

  /// 操作类型的**统一分流**（X-10）：true=表扬、false=批评、null=其它。
  ///
  /// 此前各统计口径不一致：有的"非表扬即批评"（[compute]）、有的"非批评即表扬"
  ///（图表、快照），损坏值/未来新增类型在不同界面被算成不同类别，数字
  /// 互相矛盾（明细看板还曾经把"其它"算进批评）。统一为：只有明确的两类才计数，
  /// 其它值**不计入任何一类**。
  static bool? isPraiseType(String operationType) {
    if (operationType == '表扬') return true;
    if (operationType == '批评') return false;
    return null;
  }

  /// "需关注学生"的默认判定阈值：区间内批评达到该次数即进入名单。
  /// 可调范围与出厂值统一定义在 [AppSettings]（设置 → 日常使用 → 统计口径）。
  static const int defaultAttentionThreshold =
      AppSettings.defaultAttentionThreshold;
  const StatisticsService._();

  /// 逐日补齐趋势的区间上限（天）：更长的区间不补齐 —— 避免趋势图一次渲染
  /// 上千个点（审计复查：全部记录跨多年时 dailyCounts 会到 3650+ 个）。
  static const int maxZeroFillRangeDays = 730;

  /// 根据记录集合计算统计结果。
  ///
  /// [rangeDates]：调用方给出**完整统计区间**的日期时，趋势/每日统计逐日
  /// 补齐（空档记 0）—— 审计 P2-47：此前只含有记录的天，空档被压缩、走势失真；
  /// 不传则保持旧行为（仅含有记录的天）。
  static StatisticsResult compute(
    List<StudentRecord> records, {
    List<String>? rangeDates,
    bool includePraise = true,
    bool includeCriticize = true,
  }) {
    final rangeDateSet = rangeDates?.toSet();
    var praiseCount = 0;
    var criticizeCount = 0;
    final praiseMap = <String, int>{};
    final criticizeMap = <String, int>{};
    final days = <String>{};
    final students = <String>{};
    final dailyPraise = <String, int>{};
    final dailyCriticize = <String, int>{};

    for (final record in records) {
      // X-10：统一分流 —— 只有明确的"表扬"/"批评"才计数，"其它"不计入任何一类。
      final bucket = isPraiseType(record.operationType);
      final name = record.studentName;
      // 只有明确的表扬/批评才参与统计；非法类型既不计数，也不能制造
      // “0 表扬 0 批评”的幽灵学生。
      if (bucket == null) continue;
      if (bucket && !includePraise) continue;
      if (!bucket && !includeCriticize) continue;
      final date = record.date ?? '';
      // 审计 P2-20：调用方指定区间时，只统计真正落在区间内的记录，
      // 避免“桶日期在区间、记录自身 date 在区间外”混入每日/记录天数。
      if (rangeDateSet != null &&
          date.isNotEmpty &&
          !rangeDateSet.contains(date)) {
        continue;
      }
      students.add(name);
      if (bucket == true) {
        praiseCount++;
        praiseMap[name] = (praiseMap[name] ?? 0) + 1;
      } else if (bucket == false) {
        criticizeCount++;
        criticizeMap[name] = (criticizeMap[name] ?? 0) + 1;
      }

      if (date.isEmpty) continue;
      days.add(date);
      if (bucket == true) {
        dailyPraise[date] = (dailyPraise[date] ?? 0) + 1;
      } else if (bucket == false) {
        dailyCriticize[date] = (dailyCriticize[date] ?? 0) + 1;
      }
    }

    final studentTotals =
        students.map((name) {
          return StudentTotal(
            name: name,
            praiseCount: praiseMap[name] ?? 0,
            criticizeCount: criticizeMap[name] ?? 0,
          );
        }).toList()..sort((a, b) {
          final byPraise = b.praiseCount.compareTo(a.praiseCount);
          if (byPraise != 0) return byPraise;
          final byTotal = b.total.compareTo(a.total);
          if (byTotal != 0) return byTotal;
          return a.name.compareTo(b.name);
        });

    // D-014：放假日期产生的记录计入总数，趋势也必须保留（否则同一份统计自相矛盾）。
    // 审计 P2-47：调用方给了完整区间时逐日补齐（空档记 0）。
    final allDates = <String>{
      ...(rangeDates ?? const <String>[]),
      ...dailyPraise.keys,
      ...dailyCriticize.keys,
    }.toList()..sort();

    return StatisticsResult(
      summary: StatisticsSummary(
        praiseCount: praiseCount,
        criticizeCount: criticizeCount,
        recordDays: days.length,
        studentCount: students.length,
      ),
      praiseRanking: _toRanking(praiseMap),
      criticizeRanking: _toRanking(criticizeMap),
      studentTotals: studentTotals,
      dailyCounts: allDates
          .map(
            (date) => DailyCount(
              date: date,
              praiseCount: dailyPraise[date] ?? 0,
              criticizeCount: dailyCriticize[date] ?? 0,
            ),
          )
          .toList(),
      records: records,
    );
  }

  /// 统计单名学生在给定范围内的次数与逐条记录。
  static StudentStatistics studentDetail(
    List<StudentRecord> records,
    String studentName,
  ) {
    var praiseCount = 0;
    var criticizeCount = 0;
    final matched = <StudentRecord>[];
    for (final record in records) {
      if (record.studentName != studentName) continue;
      matched.add(record);
      // 修复（审查四 G-33）+ X-10：只有明确"表扬"/"批评"才计入 —— 使用统一分流，
      // 与 [compute] 完全同口径（此前本方法与 compute 各写一套）。
      final bucket = isPraiseType(record.operationType);
      if (bucket == true) {
        praiseCount++;
      } else if (bucket == false) {
        criticizeCount++;
      }
    }
    matched.sort(_compareByDateAndTime);
    return StudentStatistics(
      studentName: studentName,
      praiseCount: praiseCount,
      criticizeCount: criticizeCount,
      records: matched,
    );
  }

  /// 按日期、时间升序复制排序（用于明细导出与展示）。
  static List<StudentRecord> sortByDateAndTime(List<StudentRecord> records) {
    return List<StudentRecord>.from(records)..sort(_compareByDateAndTime);
  }

  /// 区间考勤统计：状态人次、按学生的异常排行、条数与涉及人数。
  static AttendanceStatsResult computeAttendance(
    List<AttendanceRecord> records,
  ) {
    final byStatus = <String, int>{};
    final byStudent = <String, int>{};
    for (final record in records) {
      byStatus[record.status] = (byStatus[record.status] ?? 0) + 1;
      if (record.studentName.isEmpty) continue;
      byStudent[record.studentName] = (byStudent[record.studentName] ?? 0) + 1;
    }
    // 状态按人次降序，便于展示与图表着色
    final statusEntries = byStatus.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final ranking =
        byStudent.entries
            .map((entry) => StudentCount(name: entry.key, count: entry.value))
            .toList()
          ..sort((a, b) {
            final byCount = b.count.compareTo(a.count);
            if (byCount != 0) return byCount;
            return a.name.compareTo(b.name);
          });
    return AttendanceStatsResult(
      byStatus: {for (final entry in statusEntries) entry.key: entry.value},
      studentRanking: ranking,
      totalRecords: records.length,
    );
  }

  /// 本周起始日：默认周一起算；[weekStartDay] 支持周日(7)/周六(6)等自定义
  /// （例如周日就要返校时，把每周起始日设为周日更符合在校周）。
  static String startOfWeek(
    DateTime now, {
    int weekStartDay = DateTime.monday,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    // weekday：周一为 1 … 周日为 7，据此回退到本周起始日。
    final diff = (today.weekday - weekStartDay + 7) % 7;
    return dateString(today.subtract(Duration(days: diff)));
  }

  /// 本月起始日（1 号）。
  static String startOfMonth(DateTime now) =>
      dateString(DateTime(now.year, now.month, 1));

  /// 今天（作为区间结束日）。
  static String todayString(DateTime now) =>
      dateString(DateTime(now.year, now.month, now.day));

  /// 格式化为 yyyy-MM-dd。
  /// 审查 M10：与工具层同口径 —— 实现统一在 `utils/app_date.dart` 的 [formatYmd]。
  static String dateString(DateTime date) => formatYmd(date);

  /// 解析 yyyy-MM-dd，格式非法时返回 null（不抛异常）。
  ///
  /// 修复（1.6，2026-10-03 审查）：此前的校验只到"月 1-12 / 日 1-31"，
  /// `parseDate('2026-02-31')` 会被 `DateTime` 滚动成 03-03 返回——
  /// 而调用点全是关键路径（统计区间起止、考勤基准日、备份/自动导出间隔、
  /// 周起始）。这里补齐：每段只含数字、年份限 1900-2100、
  /// **日期必须真实存在**（与 `utils/app_date.dart` 的 isValidYmdDate 同口径）。
  static DateTime? parseDate(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return null;
    for (final part in parts) {
      if (part.isEmpty) return null;
      for (final code in part.codeUnits) {
        if (code < 0x30 || code > 0x39) return null;
      }
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    // 复查 3.1：与 utils/app_date.dart 的 isValidYmdDate 统一为 1900-2100。
    if (year < kMinSupportedYear || year > kMaxSupportedYear) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  /// 起止日期（含两端）之间的全部日期，格式为 yyyy-MM-dd。
  static List<String> datesBetween(String startDate, String endDate) {
    final start = parseDate(startDate);
    final end = parseDate(endDate);
    if (start == null || end == null) return const [];

    // 审计 P1-14：超长区间不再只取最早 3660 天（会静默丢掉近年数据），
    // 改为取**结束日往前**的最近 3660 天，保证最近的数据始终在统计内。
    var effectiveStart = start;
    final totalDays =
        DateTime.utc(
          end.year,
          end.month,
          end.day,
        ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
        1;
    if (totalDays > kMaxDateRangeDays) {
      effectiveStart = DateTime(
        end.year,
        end.month,
        end.day - (kMaxDateRangeDays - 1),
      );
    }

    final dates = <String>[];
    var current = effectiveStart;
    while (!current.isAfter(end) && dates.length < kMaxDateRangeDays) {
      dates.add(dateString(current));
      // 修复（1.7）：用**日历进位**而不是 +24 小时 —— 在有夏令时的时区，
      // 回拨日有 25 小时，`add(Duration(days:1))` 会停在当天 23:00，
      // dateString 输出的还是同一天 → 该日期被写入两次。Dart 的
      // `DateTime(y, m, d + 1)` 按日历进位，不依赖时长。
      current = DateTime(current.year, current.month, current.day + 1);
    }
    return dates;
  }

  /// 间隔天数（含首尾，至少为 1）。
  static int rangeDays(String startDate, String endDate) {
    final start = parseDate(startDate);
    final end = parseDate(endDate);
    if (start == null || end == null) return 1;
    // 修复（1.8）：按 24 小时整除在夏令时切换日会少算一天（前一日实际间隔
    // 23 小时 → inDays == 0）。改在 UTC 下比较纯日期差，绕开时区影响。
    final diff =
        DateTime.utc(
          end.year,
          end.month,
          end.day,
        ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
        1;
    // 与 datesBetween 的截断上限保持一致：否则界面会声称统计了 N 天，
    // 实际只分析了前 kMaxDateRangeDays 天。
    if (diff < 1) return 1;
    return diff > kMaxDateRangeDays ? kMaxDateRangeDays : diff;
  }

  /// 需关注的学生：区间内批评次数达到 [threshold] 次及以上，按次数降序、同次数按姓名排序。
  static List<StudentCount> attentionStudents(
    List<StudentRecord> records, {
    int threshold = defaultAttentionThreshold,
  }) {
    final counts = <String, int>{};
    for (final record in records) {
      if (record.operationType != '批评') continue;
      counts[record.studentName] = (counts[record.studentName] ?? 0) + 1;
    }
    counts.removeWhere((_, count) => count < threshold);
    return _toRanking(counts);
  }

  /// 与 [startDate]~[endDate] 等长、紧接在前面的区间（用于环比）；
  /// 日期非法时返回 null。
  static (String, String)? previousPeriod(String startDate, String endDate) {
    final start = parseDate(startDate);
    final end = parseDate(endDate);
    if (start == null || end == null || end.isBefore(start)) return null;
    // 修复（审查 P2-11）：与 datesBetween / rangeDays 同口径，按**日历**运算 ——
    // 用 24 小时步进在夏令时切换日会把环比区间算错一天（国内无 DST，属前瞻修正）。
    final days =
        (DateTime.utc(end.year, end.month, end.day)
                    .difference(
                      DateTime.utc(start.year, start.month, start.day),
                    )
                    .inDays +
                1)
            .clamp(1, kMaxDateRangeDays);
    final previousEnd = DateTime.utc(start.year, start.month, start.day - 1);
    final previousStart = DateTime.utc(
      previousEnd.year,
      previousEnd.month,
      previousEnd.day - (days - 1),
    );
    return (dateString(previousStart), dateString(previousEnd));
  }

  // 次数降序、同次数按姓名排序，保证展示稳定。
  static List<StudentCount> _toRanking(Map<String, int> counts) {
    return counts.entries
        .map((entry) => StudentCount(name: entry.key, count: entry.value))
        .toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        return a.name.compareTo(b.name);
      });
  }

  static int _compareByDateAndTime(StudentRecord a, StudentRecord b) {
    final byDate = (a.date ?? '').compareTo(b.date ?? '');
    if (byDate != 0) return byDate;
    return a.timestamp.compareTo(b.timestamp);
  }
}
