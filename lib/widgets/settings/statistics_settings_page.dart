/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.0
 * 创建日期 (Created): 2026-10-24
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

part of '../settings_pages.dart';

/// 统计口径：需关注阈值与排行榜显示条数（原在“记录”页内，V2.40 独立）。
class StatisticsSettingsPage extends StatelessWidget {
  const StatisticsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final settings = provider.appData.settings;
    final muted = mutedTextColor(theme, 0.65);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('每周起始日'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const [
              MapEntry(DateTime.monday, '周一'),
              MapEntry(DateTime.sunday, '周日'),
              MapEntry(DateTime.saturday, '周六'),
            ])
              SettingsChoiceButton(
                label: entry.value,
                selected: settings.weekStart == entry.key,
                onPressed: () {
                  provider.setWeekStart(entry.key);
                  showTopSnackBar(
                    context,
                    '已把每周起始日设为${entry.value}，统计的"本周"随之调整',
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        const SettingsHint(
          '统计看板的"本周"、以及环比里的"上一周"都按这里的起始日计算。',
        ),
        const SizedBox(height: 18),
        const SettingsSectionTitle('需关注学生阈值'),
        const SettingsHint(
          '区间内批评达到该次数即进入"需关注"名单；同时作用于统计看板与统计报表。',
        ),
        const SizedBox(height: 4),
        _AttentionThresholdSlider(
          label: '一周（本周 / 近 7 天）',
          value: settings.attentionThreshold,
          min: AppSettings.minAttentionThreshold,
          max: AppSettings.maxAttentionThreshold,
          onChanged: (value) =>
              provider.setStatisticsOptions(attentionThreshold: value),
        ),
        _AttentionThresholdSlider(
          label: '一个月（本月 / 近 30 天）',
          value: settings.attentionMonthThreshold,
          min: AppSettings.minAttentionMonthThreshold,
          max: AppSettings.maxAttentionMonthThreshold,
          onChanged: (value) =>
              provider.setStatisticsOptions(attentionMonthThreshold: value),
        ),
        _AttentionThresholdSlider(
          label: '一学期（本学期 / 全部记录）',
          value: settings.attentionSemesterThreshold,
          min: AppSettings.minAttentionSemesterThreshold,
          max: AppSettings.maxAttentionSemesterThreshold,
          onChanged: (value) =>
              provider.setStatisticsOptions(attentionSemesterThreshold: value),
        ),
        const SizedBox(height: 18),
        const SettingsSectionTitle('排行显示条数'),
        Text(
          '表扬 / 批评两个排行共用',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: CommitSlider(
                value: settings.rankingTopN.toDouble(),
                min: AppSettings.minRankingTopN.toDouble(),
                max: AppSettings.maxRankingTopN.toDouble(),
                divisions:
                    AppSettings.maxRankingTopN - AppSettings.minRankingTopN,
                labelBuilder: (v) => 'Top ${v.round()}',
                onCommit: (v) =>
                    provider.setStatisticsOptions(rankingTopN: v.round()),
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                'Top ${settings.rankingTopN}',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
