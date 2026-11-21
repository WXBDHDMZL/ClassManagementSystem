/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.0
 * 创建日期 (Created): 2026-07-25
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

part of '../statistics_dialog.dart';

/// 趋势图上的一个聚合点：按天/周/月自动聚合。
class _TrendBucket {
  const _TrendBucket({
    required this.label,
    required this.fullLabel,
    required this.praiseCount,
    required this.criticizeCount,
  });

  final String label;
  final String fullLabel;
  final int praiseCount;
  final int criticizeCount;
}

/// 统计对话框——趋势图表域（单张趋势图，不重复提供柱形/饼图）。
mixin _ChartsDomain on _StatsBase {
  Widget _buildTrendSection(ThemeData theme, StatisticsResult result) {
    final daily = result.dailyCounts;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.semantic.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '趋势',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _trendGranularity(daily),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: mutedTextColor(theme, 0.7),
                ),
              ),
              const Spacer(),
              for (final entry in [
                if (_types.contains(0) ||
                    Provider.of<AppDataProvider>(context, listen: false)
                        .appData
                        .settings
                        .praiseEnabled)
                  const MapEntry(0, '表扬'),
                if (_types.contains(1) ||
                    Provider.of<AppDataProvider>(context, listen: false)
                        .appData
                        .settings
                        .criticismEnabled)
                  const MapEntry(1, '批评'),
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: FilterChip(
                    label: Text(entry.value),
                    selected: _types.contains(entry.key),
                    selectedColor: (entry.key == 0
                            ? theme.semantic.praise
                            : theme.semantic.criticize)
                        .withValues(alpha: 0.25),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _types.add(entry.key);
                      } else if (_types.length > 1) {
                        _types.remove(entry.key);
                      }
                    }),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 250,
            child: daily.isEmpty
                ? Center(
                    child: Text(
                      '该范围内暂无记录',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: mutedTextColor(theme, 0.7),
                      ),
                    ),
                  )
                : _buildLineChart(theme, daily),
          ),
        ],
      ),
    );
  }

  /// 是否显示表扬 / 是否显示批评（右上角多选）。
  bool get _showPraise => _types.contains(0);
  bool get _showCriticism => _types.contains(1);

  String _trendGranularity(List<DailyCount> daily) {
    final days = StatisticsService.rangeDays(_startDate, _endDate);
    if (days > 180) return '按月';
    if (days > 31) return '按周';
    return '按天';
  }

  Widget _buildLineChart(ThemeData theme, List<DailyCount> daily) {
    final weekStartDay = Provider.of<AppDataProvider>(
      context,
      listen: false,
    ).appData.settings.weekStart;
    final buckets = _buildTrendBuckets(daily, weekStartDay);
    if (buckets.isEmpty) {
      return Center(
        child: Text(
          '该范围内暂无记录',
          style: theme.textTheme.bodySmall?.copyWith(
            color: mutedTextColor(theme, 0.7),
          ),
        ),
      );
    }

    final praiseSpots = <FlSpot>[];
    final criticizeSpots = <FlSpot>[];
    var peak = 0;
    for (var i = 0; i < buckets.length; i++) {
      final item = buckets[i];
      if (_showPraise) {
        praiseSpots.add(FlSpot(i.toDouble(), item.praiseCount.toDouble()));
      }
      if (_showCriticism) {
        criticizeSpots.add(FlSpot(i.toDouble(), item.criticizeCount.toDouble()));
      }
      if (item.praiseCount > peak) peak = item.praiseCount;
      if (item.criticizeCount > peak) peak = item.criticizeCount;
    }

    final maxY = (peak + 1).toDouble();
    final leftInterval = (maxY / 5).ceilToDouble().clamp(1.0, double.infinity);
    final labelInterval = buckets.length <= 6
        ? 1
        : (buckets.length / 6).ceil();
    final axisStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 10,
      color: mutedTextColor(theme, 0.7),
    );
    final gridColor = theme.semantic.subtleBorder;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: buckets.length <= 1 ? 1 : (buckets.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        clipData: const FlClipData.all(),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            maxContentWidth: 180,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) {
              if (spots.isEmpty) return const [];
              final index = spots.first.x.round().clamp(0, buckets.length - 1);
              final bucket = buckets[index];
              return [
                LineTooltipItem(
                  '${bucket.fullLabel}\n'
                  '表扬 ${bucket.praiseCount} · 批评 ${bucket.criticizeCount}',
                  const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ];
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: leftInterval,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: gridColor, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: leftInterval,
              getTitlesWidget: (value, meta) =>
                  Text(value.toInt().toString(), style: axisStyle),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: labelInterval.toDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= buckets.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(buckets[index].label, style: axisStyle),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          if (_showPraise)
            _lineData(
              spots: praiseSpots,
              color: theme.semantic.praise,
              showDots: buckets.length <= 14,
            ),
          if (_showCriticism)
            _lineData(
              spots: criticizeSpots,
              color: theme.semantic.criticize,
              showDots: buckets.length <= 14,
            ),
        ],
      ),
    );
  }

  LineChartBarData _lineData({
    required List<FlSpot> spots,
    required Color color,
    required bool showDots,
  }) {
    return LineChartBarData(
      isCurved: true,
      curveSmoothness: 0.22,
      preventCurveOverShooting: true,
      spots: spots,
      color: color,
      barWidth: 2.2,
      isStrokeCapRound: true,
      dotData: FlDotData(show: showDots),
      belowBarData: BarAreaData(show: false),
    );
  }

  List<_TrendBucket> _buildTrendBuckets(
    List<DailyCount> daily,
    int weekStartDay,
  ) {
    if (daily.isEmpty) return const [];
    final days = StatisticsService.rangeDays(_startDate, _endDate);
    final byWeek = days > 31 && days <= 180;
    final byMonth = days > 180;
    if (!byWeek && !byMonth) {
      return [
        for (final item in daily)
          _TrendBucket(
            label: _shortDate(item.date),
            fullLabel: item.date,
            praiseCount: item.praiseCount,
            criticizeCount: item.criticizeCount,
          ),
      ];
    }

    final buckets = <String, _TrendBucket>{};
    for (final item in daily) {
      final date = DateTime.tryParse(item.date);
      if (date == null) continue;
      final String key;
      final String label;
      if (byMonth) {
        key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        label = key;
      } else {
        final start = date.subtract(
          Duration(days: (date.weekday - weekStartDay + 7) % 7),
        );
        key = StatisticsService.dateString(start);
        label = _shortDate(key);
      }
      final old = buckets[key];
      buckets[key] = _TrendBucket(
        label: label,
        fullLabel: key,
        praiseCount: (old?.praiseCount ?? 0) + item.praiseCount,
        criticizeCount: (old?.criticizeCount ?? 0) + item.criticizeCount,
      );
    }
    final list = buckets.values.toList()
      ..sort((a, b) => a.fullLabel.compareTo(b.fullLabel));
    return list;
  }
}
