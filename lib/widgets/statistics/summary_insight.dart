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
part of '../statistics_dialog.dart';

/// 统计对话框——概览卡与洞察域（汇总卡、环比洞察、关注度阈值）。
///
/// `_StatisticsDialogState` 的一个功能域（mixin 方法就是真正的
/// 类成员，可跨域调用、用 setState；on `_StatsBase` 同 library，
/// 其私有成员在此直接可见）。
mixin _SummaryInsightDomain on _StatsBase {
  Widget _buildSummaryCards(ThemeData theme, StatisticsSummary summary) {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    return Row(
      children: [
        if (provider.appData.settings.praiseEnabled) ...[
          Expanded(
            child: _buildSummaryCard(
              theme,
              '表扬总数',
              summary.praiseCount,
              theme.semantic.praise,
              Icons.thumb_up_alt_outlined,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (provider.appData.settings.criticismEnabled) ...[
          Expanded(
            child: _buildSummaryCard(
              theme,
              '批评总数',
              summary.criticizeCount,
              theme.semantic.criticize,
              Icons.thumb_down_alt_outlined,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: _buildSummaryCard(
            theme,
            '记录天数',
            summary.recordDays,
            theme.colorScheme.primary,
            Icons.calendar_month_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSummaryCard(
            theme,
            '涉及学生数',
            summary.studentCount,
            theme.semantic.warning,
            Icons.groups_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    ThemeData theme,
    String label,
    int value,
    Color color,
    IconData icon,
  ) {
    final height = 88 *
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.semantic.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedTextColor(theme, 0.8),
                  ),
                ),
              ),
            ],
          ),
          Text(
            '$value',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.semantic.subtleBorder),
      ),
      child: Text(
        '该范围内暂无记录',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: mutedTextColor(theme, 0.7),
        ),
      ),
    );
  }

  /// 对比与关注：表扬批评比、与上一等长区间环比、需关注学生（批评达到阈值次数）。
  Widget _buildInsightSection(
    ThemeData theme,
    AppDataProvider provider,
    StatisticsResult result,
  ) {
    final summary = result.summary;
    final attentionThreshold = _attentionThresholdFor(_startDate, _endDate);
    final muted = mutedTextColor(theme, 0.65);
    final settings = provider.appData.settings;
    final showPraise = settings.praiseEnabled;
    final showCriticism = settings.criticismEnabled;
    final ratio = !(showPraise && showCriticism)
        ? ''
        : summary.criticizeCount == 0
            ? (summary.praiseCount == 0
                ? '0 : 0'
                : '${summary.praiseCount} : 0')
            : '${(summary.praiseCount / summary.criticizeCount).toStringAsFixed(1)} : 1';

    // 与紧挨着的前一个等长区间对比（一周区间就比上一周、一月区间比上一月）。
    final period = StatisticsService.previousPeriod(_startDate, _endDate);
    var previous = _cachedPrevious;
    var previousRangeText = _cachedPreviousRangeText;
    if (!_previousCached) {
      // P2-11 修复：与导出报表统一口径——上一区间**没有任何记录**时视为
      // "无法对比"（此前按 0 基准算差值，屏幕显示"表扬 +7"、报表写"暂无法对比"）。
      previous = _previousPeriodSummary(provider);
      previousRangeText =
          (previous == null || period == null) ? '' : '${period.$1} 至 ${period.$2}';
      _cachedPrevious = previous;
      _cachedPreviousRangeText = previousRangeText;
      _previousCached = true;
    }

    final attention = StatisticsService.attentionStudents(
      result.records,
      threshold: attentionThreshold,
    );
    final praiseByName = {
      for (final total in result.studentTotals) total.name: total.praiseCount,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.semantic.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '对比与关注',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          _buildInsightRow(
            theme,
            '表扬批评比',
            Text(
              [
                if (showPraise) '表扬 ${summary.praiseCount} 次',
                if (showCriticism) '批评 ${summary.criticizeCount} 次',
                if (showPraise && showCriticism) '比值 $ratio',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (previous == null && period != null)
            _buildInsightRow(
              theme,
              '较上期',
              Text(
                '${period.$1} 至 ${period.$2} 无记录，暂无法对比',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          if (previous != null)
            _buildInsightRow(
              theme,
              '较上期',
              Text.rich(
                TextSpan(
                  children: [
                    if (showPraise)
                      TextSpan(
                        text:
                            '表扬 ${_formatDelta(summary.praiseCount - previous.praiseCount)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.semantic.praise,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (showPraise && showCriticism)
                      const TextSpan(text: '　'),
                    if (showCriticism)
                      TextSpan(
                        text:
                            '批评 ${_formatDelta(summary.criticizeCount - previous.criticizeCount)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.semantic.criticize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    TextSpan(
                      text: '（上期'
                          '${showPraise ? ' 表扬 ${previous.praiseCount}' : ''}'
                          '${showCriticism ? ' 批评 ${previous.criticizeCount}' : ''}，'
                          '$previousRangeText）',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ),
          if (showCriticism)
            _buildInsightRow(
              theme,
              '需关注学生（批评 ≥ $attentionThreshold 次）',
              attention.isEmpty
                  ? Text(
                      '本区间没有需要重点关注的学生',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in attention)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: theme.semantic.criticize
                                  .withValues(alpha: 0.12),
                              borderRadius: AppRadius.card,
                            ),
                            child: Text(
                              '${item.name} · 批评 ${item.count} 次'
                              '（表扬 ${praiseByName[item.name] ?? 0} 次）',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.semantic.criticize,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildInsightRow(ThemeData theme, String label, Widget content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedTextColor(theme, 0.65),
              ),
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }

  /// 环比数字：正数带 +，负数带 -，零显示 0。
  String _formatDelta(int delta) {
    if (delta > 0) return '+$delta';
    return '$delta';
  }
}
