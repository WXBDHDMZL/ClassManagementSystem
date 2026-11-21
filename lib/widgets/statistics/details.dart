/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.1
 * 创建日期 (Created): 2026-07-25
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../statistics_dialog.dart';

/// 统计对话框——学生明细域（学生选择、明细行）。
///
/// `_StatisticsDialogState` 的一个功能域（mixin 方法就是真正的
/// 类成员，可跨域调用、用 setState；on `_StatsBase` 同 library，
/// 其私有成员在此直接可见）。
mixin _DetailsDomain on _StatsBase {
  /// 打开统一样式的学生选择框（带区间内的表扬/批评次数）。
  Future<void> _pickDetailStudent() async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    // 修复（审查四 G-47）：复用看板已缓存的统计结果，不再对整区间重跑 compute
    //（"全部记录"区间数据量大时，打开选择器会明显卡顿）。
    final result = _cachedResult ??
        StatisticsService.compute(
          provider.getRecordsForDates(
            StatisticsService.datesBetween(_startDate, _endDate),
          ),
        );
    final counts = {
      for (final item in result.studentTotals)
        item.name: '表扬 ${item.praiseCount} · 批评 ${item.criticizeCount}',
    };
    final picked = await StudentPickerDialog.show(
      context,
      title: '选择学生',
      students: provider.appData.students,
      initialSelection: _selectedStudent == null ? const [] : [_selectedStudent!],
      subtitleBuilder: (name) => counts[name] ?? '本区间暂无记录',
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _selectedStudent = picked.first);
  }

  Widget _buildStudentDetailSection(
    ThemeData theme,
    StatisticsResult result,
  ) {
    final detail = _selectedStudent == null
        ? null
        : StatisticsService.studentDetail(result.records, _selectedStudent!);

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
          Text(
            '学生明细',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectedStudent == null
                      ? '选择学生后查看该学生在本区间内的逐条记录'
                      : '当前学生：$_selectedStudent',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedTextColor(theme, 0.7),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickDetailStudent,
                icon: const Icon(Icons.person_search_outlined, size: 16),
                label: Text(_selectedStudent == null ? '选择学生' : '重新选择'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (detail == null)
            Text(
              '请选择学生查看明细',
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedTextColor(theme, 0.7),
              ),
            )
          else if (detail.records.isEmpty)
            Text(
              '该范围内暂无记录',
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedTextColor(theme, 0.7),
              ),
            )
          else
            // G-45：明细可能数百条，此前一次性全量构建进 Column（"全部记录"区间
            // 某学生可达数百条）。改为定高 ListView.builder 懒加载，只渲染可见行。
            SizedBox(
              height: 320,
              child: ListView.builder(
                itemCount: detail.records.length,
                itemBuilder: (context, index) {
                  // 审查 M4：补稳定 key（行内原因/备注文本可换行，行高不固定，
                  // 因此不用 itemExtent/prototypeItem，避免裁字）。
                  final record = detail.records[index];
                  return KeyedSubtree(
                    key: ObjectKey(record),
                    child: _buildDetailRow(theme, record),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(ThemeData theme, StudentRecord record) {
    final isPraise = record.operationType == '表扬';
    final color = isPraise ? theme.semantic.praise : theme.semantic.criticize;
    // G-46：与 record_list 统一口径——优先当前生效的时段名（改名后同步），
    // 识别不了（如导入的外部数据）时回退记录里保存的名称；再取简称显示。
    final periodLabel = periodNameForRecord(record.periodKey, record.periodName);
    final periodName =
        periodLabel.isEmpty ? '' : periodLabel.split(' ').last.trim();
    final extra = StringBuffer(record.reasons);
    if (periodName.isNotEmpty) {
      extra.write(' · $periodName');
    }
    if (record.recordedBy.isNotEmpty) {
      extra.write(' · 记录人：${record.recordedBy}');
    }
    if (record.remark.isNotEmpty) {
      extra.write(' · 备注：${record.remark}');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(record.date ?? '', style: theme.textTheme.bodySmall),
          ),
          SizedBox(
            width: 58,
            child: Text(record.timestamp, style: theme.textTheme.bodySmall),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: AppRadius.field,
            ),
            child: Text(
              record.operationType,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              extra.toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

}
