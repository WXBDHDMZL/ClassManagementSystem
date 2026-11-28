/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.2
 * 创建日期 (Created): 2026-07-25
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../statistics_dialog.dart';

/// 统计对话框——榜单域（排行榜面板与排名条）。
///
/// `_StatisticsDialogState` 的一个功能域（mixin 方法就是真正的
/// 类成员，可跨域调用、用 setState；on `_StatsBase` 同 library，
/// 其私有成员在此直接可见）。
mixin _RankingsDomain on _StatsBase {
  Widget _buildRankings(ThemeData theme, StatisticsResult result) {
    final settings = Provider.of<AppDataProvider>(
      context,
      listen: false,
    ).appData.settings;
    final topN = settings.rankingTopN;
    final panels = <Widget>[
      if (settings.praiseEnabled)
        Expanded(
          child: _buildRankingPanel(
            theme,
            '表扬 Top $topN',
            Icons.emoji_events_outlined,
            theme.semantic.praise,
            result.praiseRanking,
            topN,
          ),
        ),
      if (settings.criticismEnabled)
        Expanded(
          child: _buildRankingPanel(
            theme,
            '批评 Top $topN',
            Icons.report_gmailerrorred_outlined,
            theme.semantic.criticize,
            result.criticizeRanking,
            topN,
          ),
        ),
    ];
    if (panels.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < panels.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          panels[i],
        ],
      ],
    );
  }

  Widget _buildRankingPanel(
    ThemeData theme,
    String title,
    IconData icon,
    Color color,
    List<StudentCount> ranking,
    int topN,
  ) {
    final top = ranking.take(topN).toList();
    final maxCount = top.isEmpty ? 0 : top.first.count;
    // 修复（审计 P1-21）：与导出"排名"表同口径 —— 同次数并列同名次（1、1、2…），
    // 此前界面按位次显示（1、2、3），同一份数据两处数字不一致。
    final ranks = StatisticsService.denseRanks(top.map((item) => item.count));

    return Container(
      padding: const EdgeInsets.all(12),
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
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (top.isEmpty)
            Text(
              '该范围内暂无记录',
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedTextColor(theme, 0.7),
              ),
            )
          else ...[
            ...top.asMap().entries.map(
              (entry) => _buildRankBar(
                theme,
                ranks[entry.key],
                entry.value,
                maxCount,
                color,
              ),
            ),
            if (ranking.length > top.length)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '其余 ${ranking.length - top.length} 人未显示',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedTextColor(theme, 0.7),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

}
