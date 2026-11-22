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

import 'package:excel/excel.dart' as excel;
import 'package:excel/excel.dart' show TextCellValue, IntCellValue;
import 'package:fl_chart/fl_chart.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_theme.dart';
import '../constants/time_periods.dart';
import '../models/student_record.dart';
import '../models/password_policy.dart';
import '../providers/app_data_provider.dart';
import '../services/statistics_service.dart';
import '../utils/app_date.dart';
import './record_list.dart';
import './password_action_guard.dart';
import './student_picker_dialog.dart';
import '../services/excel_export.dart';
import '../utils/app_clock.dart';

part 'statistics/summary_insight.dart';
part 'statistics/rankings.dart';
part 'statistics/charts.dart';
part 'statistics/details.dart';
part 'statistics/export.dart';

/// 统计时间范围类型：本周 / 本月 / 近 7 天 / 近 30 天 / 本学期 / 自定义
/// （枚举顺序即持久化索引：0=本周 1=本月 2=自定义 3=近7天 4=近30天 5=本学期 6=全部记录）
/// 新增项一律追加在末尾，避免打乱已保存的索引。
enum _RangeType { week, month, custom, last7, last30, term, all }

/// 区间类型与持久化索引的互转（索引顺序固定，不能调整）。
const List<_RangeType> _rangeOrder = [
  _RangeType.week,
  _RangeType.month,
  _RangeType.custom,
  _RangeType.last7,
  _RangeType.last30,
  _RangeType.term,
  _RangeType.all,
];

/// 本学期起始日：
/// 秋季学期（9 月–次年 1 月）从当年 **9 月 1 日** 起（1 月仍算秋季学期）；
/// 春季学期（2–8 月）从当年 **2 月 1 日** 起。
String _termStart(DateTime now) {
  if (now.month >= 9) {
    return StatisticsService.dateString(DateTime(now.year, 9, 1));
  }
  if (now.month >= 2) {
    return StatisticsService.dateString(DateTime(now.year, 2, 1));
  }
  // 1 月：属于上一个 9 月开始的秋季学期
  return StatisticsService.dateString(DateTime(now.year - 1, 9, 1));
}

/// 数据统计对话框：按时间范围汇总表扬/批评，展示排行榜、趋势图与学生明细，
/// 并支持导出「个人汇总单」「排名」与「统计报表」。
class StatisticsDialog extends StatefulWidget {
  const StatisticsDialog({super.key});

  @override
  State<StatisticsDialog> createState() => _StatisticsDialogState();
}

/// `_StatisticsDialogState` 的基类：持有全部状态字段与跨域
/// 共享方法（缓存、区间计算），供 5 个域 mixin `on` 它访问。
abstract class _StatsBase extends State<StatisticsDialog> {
  // P2-3：取数缓存——同一"区间 + 类型 + 数据规模"下重复 build 不再重跑全量统计，
  // 也不再重复计算"上一区间"对比（此前切换图表/勾选类型都会整套重算）。
  String? _cacheKey;
  StatisticsResult? _cachedResult;
  StatisticsSummary? _cachedPrevious;
  String _cachedPreviousRangeText = '';
  bool _previousCached = false;

  /// 缓存键 = 区间 + **数据指纹**（由数据内容算出的真值）。
  ///
  /// - 旧实现用"有记录的天数"当版本：同一天内新增/修改/删除记录后键不变，
  ///   看板会静默显示打开那一刻的旧数字（探针实测确认）。
  /// - **不含 `_types`**：它只影响显示过滤，`compute` 结果与之无关，
  ///   放进键里会让"勾选记录类型"这种纯显示操作白白重算整套统计。
  String _computeCacheKey(AppDataProvider provider) {
    final settings = provider.appData.settings;
    return '$_startDate|$_endDate|${settings.praiseEnabled}|'
        '${settings.criticismEnabled}|${provider.dataFingerprint}';
  }

  _RangeType _rangeType = _RangeType.week;

  /// 统计对象：0=表扬 1=批评，可多选（默认只看"启用的记录类型"）。
  final Set<int> _types = {0, 1};

  late String _startDate;
  late String _endDate;

  /// 当前选中的学生（用于明细与个人汇总导出）
  String? _selectedStudent;

  @override
  void initState() {
    super.initState();
    final now = AppClock.now();
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    final settings = provider.appData.settings;
    // 恢复上次使用的区间（含自定义起止），无效或首次则默认"本周"。
    final index = settings.statisticsRange;
    _rangeType = index >= 0 && index < _rangeOrder.length
        ? _rangeOrder[index]
        : _RangeType.week;
    // 记录类型被停用时，统计默认不再显示该类型（报表/排名导出仍包含全部历史）。
    if (!settings.praiseEnabled) _types.remove(0);
    if (!settings.criticismEnabled) _types.remove(1);
    if (_types.isEmpty &&
        (settings.praiseEnabled || settings.criticismEnabled)) {
      _types.add(settings.praiseEnabled ? 0 : 1);
    }
    final today = DateTime(now.year, now.month, now.day);
    switch (_rangeType) {
      case _RangeType.week:
        _startDate = StatisticsService.startOfWeek(
          now,
          weekStartDay: settings.weekStart,
        );
      case _RangeType.month:
        _startDate = StatisticsService.startOfMonth(now);
      case _RangeType.last7:
        _startDate = StatisticsService.dateString(
          today.subtract(const Duration(days: 6)),
        );
      case _RangeType.last30:
        _startDate = StatisticsService.dateString(
          today.subtract(const Duration(days: 29)),
        );
      case _RangeType.term:
        _startDate = _termStart(now);
      case _RangeType.all:
        // 全部记录：从最早一条记录那天开始（没有记录就用今天）。
        _startDate = _allRangeStart(provider, now);
      case _RangeType.custom:
        final start = settings.statisticsRangeStart;
        final end = settings.statisticsRangeEnd;
        final startDate = StatisticsService.parseDate(start);
        final endDate = StatisticsService.parseDate(end);
        // 审计 P2-24：设置文件被改坏时 start > end / 非法日期会让整个区间
        // 为空且显示“共 1 天”。无效则退回本周，不再展示矛盾数字。
        if (startDate != null &&
            endDate != null &&
            !startDate.isAfter(endDate)) {
          _startDate = start;
          _endDate = end;
          return;
        }
        // 自定义区间无效时退回本周，避免出现空区间。
        _rangeType = _RangeType.week;
        _startDate = StatisticsService.startOfWeek(
          now,
          weekStartDay: settings.weekStart,
        );
    }
    _endDate = StatisticsService.todayString(now);
  }

  /// "全部记录"区间的起始日：最早一条记录那天；一条记录都没有时用今天。
  String _allRangeStart(AppDataProvider provider, DateTime now) {
    final history = <String>{...provider.getHistoryDates()}.toList()..sort();
    if (history.isEmpty) return StatisticsService.todayString(now);
    // 审计 P1-14：“全部记录”最多统计最近 3660 天，超出时从结束日往前取，
    // 避免只渲染最早十年而静默丢掉近年数据。
    final earliest = StatisticsService.parseDate(history.first);
    final limitStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: kMaxDateRangeDays - 1));
    if (earliest != null && earliest.isBefore(limitStart)) {
      return StatisticsService.dateString(limitStart);
    }
    return history.first;
  }

  /// 把当前区间记入设置，下次打开统计时沿用。
  void _rememberRange() {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    provider.setStatisticsRange(
      _rangeOrder.indexOf(_rangeType),
      start: _startDate,
      end: _endDate,
    );
  }

  /// 切换时间范围；选择"自定义"时弹出日期区间选择器。
  Future<void> _onRangeChanged(_RangeType type) async {
    if (type == _RangeType.custom) {
      final now = AppClock.now();
      final initialStart =
          StatisticsService.parseDate(_startDate) ??
          DateTime(now.year, now.month, now.day);
      final initialEnd =
          StatisticsService.parseDate(_endDate) ??
          DateTime(now.year, now.month, now.day);
      // 与"追加记录"保持一致的日期选择体验：先选开始日期，再选结束日期。
      final start = await showDatePicker(
        context: context,
        initialDate: initialStart,
        firstDate: DateTime(2000, 1, 1),
        lastDate: DateTime(now.year + 1, 12, 31),
        helpText: '选择开始日期',
        cancelText: '取消',
        confirmText: '下一步',
      );
      if (!mounted || start == null) return;
      final end = await showDatePicker(
        context: context,
        initialDate: initialEnd.isBefore(start) ? start : initialEnd,
        firstDate: start,
        lastDate: DateTime(now.year + 1, 12, 31),
        helpText: '选择结束日期',
        cancelText: '取消',
        confirmText: '确定',
      );
      if (!mounted || end == null) return;
      // 修复（审计 P2-45）：超长自定义区间的统计会被静默截断（约 10 年上限）——
      // 在此把结束日期夹到上限并如实提示，不再"界面显示 30 年、实际只算 10 年"。
      var safeEnd = end;
      final cappedEnd = start.add(const Duration(days: kMaxDateRangeDays - 1));
      if (end.isAfter(cappedEnd)) {
        safeEnd = cappedEnd;
        showTopSnackBar(
          context,
          '统计区间最长约 10 年，结束日期已自动调整为 '
          '${StatisticsService.dateString(safeEnd)}',
        );
      }
      setState(() {
        _rangeType = _RangeType.custom;
        _startDate = StatisticsService.dateString(start);
        _endDate = StatisticsService.dateString(safeEnd);
        // 范围变化后学生明细需重新选择，避免下拉值不在候选项中。
        _selectedStudent = null;
      });
      _rememberRange();
      return;
    }

    setState(() {
      _rangeType = type;
      final now = AppClock.now();
      final provider = Provider.of<AppDataProvider>(context, listen: false);
      final today = DateTime(now.year, now.month, now.day);
      _startDate = switch (type) {
        _RangeType.week => StatisticsService.startOfWeek(
          now,
          weekStartDay: provider.appData.settings.weekStart,
        ),
        _RangeType.month => StatisticsService.startOfMonth(now),
        _RangeType.last7 => StatisticsService.dateString(
          today.subtract(const Duration(days: 6)),
        ),
        _RangeType.last30 => StatisticsService.dateString(
          today.subtract(const Duration(days: 29)),
        ),
        _RangeType.term => _termStart(now),
        _RangeType.all => _allRangeStart(provider, now),
        _RangeType.custom => _startDate,
      };
      _endDate = StatisticsService.todayString(now);
      _selectedStudent = null;
    });
    _rememberRange();
  }

  String _shortDate(String date) =>
      date.length >= 10 ? date.substring(5) : date;

  /// 当前区间的"需关注学生"阈值：按区间天数取"一周 / 一个月 / 一学期"三档之一
  /// （三档都可在 设置 → 日常使用 → 统计口径 里调整）。
  int _attentionThresholdFor(String start, String end) {
    final settings = Provider.of<AppDataProvider>(
      context,
      listen: false,
    ).appData.settings;
    return StatisticsService.attentionThresholdForDays(
      StatisticsService.rangeDays(start, end),
      weekly: settings.attentionThreshold,
      monthly: settings.attentionMonthThreshold,
      semester: settings.attentionSemesterThreshold,
    );
  }

  /// 上一等长区间的汇总（环比用），越界或无数据时返回 null。
  /// 上一个等长区间的汇总；该区间没有记录时返回 null（避免误导性的 ±0 对比）。
  StatisticsSummary? _previousPeriodSummary(AppDataProvider provider) {
    final period = StatisticsService.previousPeriod(_startDate, _endDate);
    if (period == null) return null;
    final records = provider.getRecordsForDates(
      StatisticsService.datesBetween(period.$1, period.$2),
    );
    if (records.isEmpty) return null;
    return StatisticsService.compute(
      records,
      includePraise: provider.appData.settings.praiseEnabled,
      includeCriticize: provider.appData.settings.criticismEnabled,
    ).summary;
  }

  /// [rank] 为**并列名次**（同次数同名次，1、1、2…，与导出"排名"表同口径）。
  Widget _buildRankBar(
    ThemeData theme,
    int rank,
    StudentCount item,
    int maxCount,
    Color color,
  ) {
    final ratio = maxCount <= 0
        ? 0.0
        : (item.count / maxCount).clamp(0.0, 1.0).toDouble();
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 18, child: Text('$rank', style: labelStyle)),
          SizedBox(
            width: 56,
            child: Text(
              item.name,
              overflow: TextOverflow.ellipsis,
              style: labelStyle?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 14,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: AppRadius.field,
                      ),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: AppRadius.field,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text(
              '${item.count}',
              textAlign: TextAlign.right,
              style: labelStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatisticsDialogState extends _StatsBase
    with
        _SummaryInsightDomain,
        _RankingsDomain,
        _ChartsDomain,
        _DetailsDomain,
        _ExportDomain {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 修复（审查 三-4 / 六-2）：只订阅**数据指纹** —— 无关状态变化（切主题、
    // 改其它设置）不再触发整块看板重建与全量统计重算；数据一变指纹即变，
    // 刷新语义与之前完全一致。
    context.select<AppDataProvider, String>((p) => p.dataFingerprint);
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    final cacheKey = _computeCacheKey(provider);
    final StatisticsResult result;
    if (_cacheKey == cacheKey && _cachedResult != null) {
      result = _cachedResult!;
    } else {
      final dates = StatisticsService.datesBetween(_startDate, _endDate);
      final records = provider.getRecordsForDates(dates);
      final settings = provider.appData.settings;
      result = StatisticsService.compute(
        records,
        // 审计 P1-13：统计汇总与榜单只统计当前启用的记录类型。
        includePraise: settings.praiseEnabled,
        includeCriticize: settings.criticismEnabled,
        // 审计 P2-47：给出完整区间，趋势与"每日统计"逐日补齐空档；
        // 复查：超长区间（>2 年）不补齐，避免一次渲染上千个趋势点。
        rangeDates: dates.length <= StatisticsService.maxZeroFillRangeDays
            ? dates
            : null,
      );
      _cacheKey = cacheKey;
      _cachedResult = result;
      // 数据或区间变化：上一区间对比同步失效（null 也要重算，故用标志位）。
      _cachedPrevious = null;
      _cachedPreviousRangeText = '';
      _previousCached = false;
    }

    final screen = MediaQuery.of(context).size;
    final width = dialogWidthFor(screen);

    return DefaultTabController(
      length: 4,
      child: Dialog(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
        child: SizedBox(
          width: width,
          height: screen.height * 0.85,
          child: Column(
            children: [
              _buildHeader(theme),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: _buildRangeSelector(theme),
                    ),
                    if (!result.isEmpty) ...[
                      const TabBar(
                        isScrollable: false,
                        tabs: [
                          Tab(text: '概览'),
                          Tab(text: '趋势'),
                          Tab(text: '排行'),
                          Tab(text: '明细'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildTabBody(
                              children: [
                                _buildSummaryCards(theme, result.summary),
                                const SizedBox(height: 16),
                                _buildInsightSection(theme, provider, result),
                              ],
                            ),
                            _buildTabBody(
                              children: [_buildTrendSection(theme, result)],
                            ),
                            _buildTabBody(
                              children: [_buildRankings(theme, result)],
                            ),
                            _buildTabBody(
                              children: [
                                _buildStudentDetailSection(theme, result),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ] else
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: _buildEmptyCard(theme),
                        ),
                      ),
                  ],
                ),
              ),
              _buildFooter(theme, result),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBody({required List<Widget> children}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.semantic.subtleBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '数据统计',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeSelector(ThemeData theme) {
    // 区间按钮会随版本增加，用 Wrap 排列，窗口窄时自动换行、不会挤出边界。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const [
              MapEntry(_RangeType.week, '本周'),
              MapEntry(_RangeType.month, '本月'),
              MapEntry(_RangeType.last7, '近 7 天'),
              MapEntry(_RangeType.last30, '近 30 天'),
              MapEntry(_RangeType.term, '本学期'),
              MapEntry(_RangeType.all, '全部记录'),
              MapEntry(_RangeType.custom, '自定义'),
            ])
              ChoiceChip(
                label: Text(entry.value),
                selected: _rangeType == entry.key,
                onSelected: (_) => _onRangeChanged(entry.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '$_startDate 至 $_endDate（共 '
          '${StatisticsService.rangeDays(_startDate, _endDate)} 天）'
          '${_rangeType == _RangeType.term ? ' · 学期起算：秋季 9/1、春季 2/1' : ''}'
          '${_rangeType == _RangeType.all ? ' · 从最早一条记录起' : ''}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: mutedTextColor(theme, 0.8),
          ),
        ),
      ],
    );
  }
}
