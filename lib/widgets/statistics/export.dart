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

/// 统计对话框——页脚与导出域（个人汇总单/统计报表/排名导出）。
///
/// `_StatisticsDialogState` 的一个功能域（mixin 方法就是真正的
/// 类成员，可跨域调用、用 setState；on `_StatsBase` 同 library，
/// 其私有成员在此直接可见）。
mixin _ExportDomain on _StatsBase {
  Widget _buildFooter(ThemeData theme, StatisticsResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.semantic.subtleBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '共 ${result.records.length} 条记录',
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedTextColor(theme, 0.7),
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: result.isEmpty ? null : _exportPersonalSummary,
            icon: const Icon(Icons.description_outlined, size: 16),
            label: const Text('个人汇总单'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: result.isEmpty ? null : _exportRanking,
            icon: const Icon(Icons.emoji_events_outlined, size: 16),
            label: const Text('导出排名'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: result.isEmpty ? null : _exportReport,
            icon: const Icon(Icons.summarize_outlined, size: 16),
            label: const Text('导出报表'),
          ),
        ],
      ),
    );
  }

  /// 导出当前选中学生的个人汇总单（单表）。
  Future<void> _exportPersonalSummary() async {
    final studentName = _selectedStudent;
    if (studentName == null) {
      showTopSnackBar(context, '请先选择学生', isError: true);
      return;
    }

    final provider = Provider.of<AppDataProvider>(context, listen: false);
    final dates = StatisticsService.datesBetween(_startDate, _endDate);
    final records = provider.getRecordsForDates(dates);
    final detail = StatisticsService.studentDetail(records, studentName);
    if (detail.records.isEmpty) {
      showTopSnackBar(context, '该范围内没有 $studentName 的记录', isError: true);
      return;
    }

    final includeRecorder =
        provider.identityFeatureEnabled ||
        detail.records.any((record) => record.recordedBy.isNotEmpty);

    final excelFile = ExcelExport.newWorkbook();
    final sheet = excelFile['Sheet1'];
    sheet.appendRow([TextCellValue('学生姓名：${detail.studentName}')]);
    sheet.appendRow([TextCellValue('时间范围：$_startDate 至 $_endDate')]);
    sheet.appendRow([TextCellValue('内容：该学生在本区间内的逐条记录')]);
    sheet.appendRow([
      TextCellValue('日期'),
      TextCellValue('时间段'),
      TextCellValue('时间'),
      TextCellValue('操作项目'),
      TextCellValue('原因'),
      TextCellValue('备注'),
      if (includeRecorder) TextCellValue('记录人'),
    ]);
    for (final record in detail.records) {
      sheet.appendRow([
        TextCellValue(record.date ?? ''),
        TextCellValue(periodNameForRecord(record.periodKey, record.periodName)),
        TextCellValue(record.timestamp),
        TextCellValue(record.operationType),
        TextCellValue(record.reasons),
        TextCellValue(record.remark),
        if (includeRecorder)
          TextCellValue(record.recordedBy.isEmpty ? '未记录' : record.recordedBy),
      ]);
    }
    // 审计 P2-23：合计行补齐到与明细相同列数，避免只有两列导致错位。
    sheet.appendRow([
      TextCellValue('合计'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(
        '表扬 ${detail.praiseCount} 次 / 批评 ${detail.criticizeCount} 次',
      ),
      if (includeRecorder) TextCellValue(''),
    ]);
    ExcelExport.autoFitColumns(sheet);

    await _saveExcel(
      excelFile,
      '个人记录_${detail.studentName}_${_startDate}_至_$_endDate',
    );
  }

  /// 导出当前区间的统计报表（分类型汇总 / 明细 / 每日统计 / 对比与关注）。
  Future<void> _exportReport() async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    final dates = StatisticsService.datesBetween(_startDate, _endDate);
    final records = provider.getRecordsForDates(dates);
    // 启用身份或已有记录人时增加“记录人”列。
    final includeRecorder =
        provider.identityFeatureEnabled ||
        records.any((record) => record.recordedBy.isNotEmpty);
    if (records.isEmpty) {
      showTopSnackBar(context, '该范围内暂无记录', isError: true);
      return;
    }
    final result = StatisticsService.compute(
      records,
      // 分类开关必须与看板一致：关闭批评后报表/环比不应再计入批评。
      includePraise: provider.appData.settings.praiseEnabled,
      includeCriticize: provider.appData.settings.criticismEnabled,
      // 审计 P2-47：报表"每日统计"同趋势口径，逐日补齐空档；
      // 复查：超长区间（>2 年）不补齐，避免工作表行数爆炸。
      rangeDates: dates.length <= StatisticsService.maxZeroFillRangeDays
          ? dates
          : null,
    );

    final excelFile = ExcelExport.newWorkbook();
    final hasPraise = result.summary.praiseCount > 0;
    final hasCriticism = result.summary.criticizeCount > 0;
    final summarySheets = <excel.Sheet>[];
    if (hasPraise) {
      final sheet = excelFile['表扬汇总'];
      sheet.appendRow([TextCellValue('统计范围：$_startDate 至 $_endDate')]);
      sheet.appendRow([TextCellValue('内容：各学生表扬次数')]);
      sheet.appendRow([TextCellValue('学生姓名'), TextCellValue('表扬次数')]);
      for (final item in result.studentTotals) {
        if (item.praiseCount <= 0) continue;
        sheet.appendRow([
          TextCellValue(item.name),
          IntCellValue(item.praiseCount),
        ]);
      }
      summarySheets.add(sheet);
    }
    if (hasCriticism) {
      final sheet = excelFile['批评汇总'];
      sheet.appendRow([TextCellValue('统计范围：$_startDate 至 $_endDate')]);
      sheet.appendRow([TextCellValue('内容：各学生批评次数')]);
      sheet.appendRow([TextCellValue('学生姓名'), TextCellValue('批评次数')]);
      final criticizeTotals =
          result.studentTotals.where((item) => item.criticizeCount > 0).toList()
            ..sort((a, b) {
              final byCount = b.criticizeCount.compareTo(a.criticizeCount);
              if (byCount != 0) return byCount;
              return a.name.compareTo(b.name);
            });
      for (final item in criticizeTotals) {
        sheet.appendRow([
          TextCellValue(item.name),
          IntCellValue(item.criticizeCount),
        ]);
      }
      summarySheets.add(sheet);
    }
    if (excelFile.tables.containsKey('Sheet1')) {
      excelFile.delete('Sheet1');
    }

    final detailSheet = excelFile['明细'];
    detailSheet.appendRow([
      TextCellValue('日期'),
      TextCellValue('学生姓名'),
      TextCellValue('操作项目'),
      TextCellValue('原因'),
      TextCellValue('时间段'),
      TextCellValue('时间'),
      TextCellValue('备注'),
      if (includeRecorder) TextCellValue('记录人'),
    ]);
    for (final record in StatisticsService.sortByDateAndTime(records)) {
      detailSheet.appendRow([
        TextCellValue(record.date ?? ''),
        TextCellValue(record.studentName),
        TextCellValue(record.operationType),
        TextCellValue(record.reasons),
        TextCellValue(periodNameForRecord(record.periodKey, record.periodName)),
        TextCellValue(record.timestamp),
        TextCellValue(record.remark),
        if (includeRecorder)
          TextCellValue(record.recordedBy.isEmpty ? '未记录' : record.recordedBy),
      ]);
    }

    // 每日统计表：趋势图背后的数据。
    final dailySheet = excelFile['每日统计'];
    dailySheet.appendRow([
      TextCellValue('日期'),
      if (hasPraise) TextCellValue('表扬次数'),
      if (hasCriticism) TextCellValue('批评次数'),
    ]);
    for (final item in result.dailyCounts) {
      dailySheet.appendRow([
        TextCellValue(item.date),
        if (hasPraise) IntCellValue(item.praiseCount),
        if (hasCriticism) IntCellValue(item.criticizeCount),
      ]);
    }

    // 对比与关注表：表扬批评比、与上一等长区间环比、需关注学生。
    final insightSheet = excelFile['对比与关注'];
    insightSheet.appendRow([TextCellValue('项目'), TextCellValue('内容')]);
    final summary = result.summary;
    insightSheet.appendRow([
      TextCellValue('表扬批评比'),
      TextCellValue(
        '表扬 ${summary.praiseCount} 次 / 批评 ${summary.criticizeCount} 次',
      ),
    ]);
    final period = StatisticsService.previousPeriod(_startDate, _endDate);
    final previous = _previousPeriodSummary(provider);
    if (previous != null && period != null) {
      insightSheet.appendRow([
        TextCellValue('对比的上一个等长区间'),
        TextCellValue('${period.$1} 至 ${period.$2}'),
      ]);
    }
    if (previous != null) {
      insightSheet.appendRow([
        TextCellValue('较上期（表扬）'),
        TextCellValue(
          '${summary.praiseCount - previous.praiseCount >= 0 ? '+' : ''}'
          '${summary.praiseCount - previous.praiseCount}（上期 ${previous.praiseCount}）',
        ),
      ]);
      insightSheet.appendRow([
        TextCellValue('较上期（批评）'),
        TextCellValue(
          '${summary.criticizeCount - previous.criticizeCount >= 0 ? '+' : ''}'
          '${summary.criticizeCount - previous.criticizeCount}（上期 ${previous.criticizeCount}）',
        ),
      ]);
    }
    if (previous == null && period != null) {
      insightSheet.appendRow([
        TextCellValue('与上一个等长区间对比'),
        TextCellValue('${period.$1} 至 ${period.$2} 无记录，暂无法对比'),
      ]);
    }
    final attention = StatisticsService.attentionStudents(
      result.records,
      threshold: _attentionThresholdFor(_startDate, _endDate),
    );
    // 修复（V2.30.10）：需关注学生此前全部用顿号连接塞进**同一个单元格**，
    // 学生一多就是横向的一长条（列宽即使顶到上限也放不下）。
    // 改为一人一行（首行是汇总，其后每行：序号 + 姓名 + 次数），便于阅读与打印。
    if (attention.isEmpty) {
      insightSheet.appendRow([TextCellValue('需关注学生'), TextCellValue('无')]);
    } else {
      insightSheet.appendRow([
        TextCellValue('需关注学生'),
        TextCellValue('共 ${attention.length} 人'),
      ]);
      var attentionIndex = 0;
      for (final item in attention) {
        attentionIndex++;
        insightSheet.appendRow([
          TextCellValue('$attentionIndex'),
          TextCellValue('${item.name}（批评 ${item.count} 次）'),
        ]);
      }
    }

    for (final sheet in summarySheets) {
      ExcelExport.autoFitColumns(sheet);
    }
    ExcelExport.autoFitColumns(detailSheet);
    ExcelExport.autoFitColumns(dailySheet);
    ExcelExport.autoFitColumns(insightSheet);

    // 名称不写死范围：区间可能是任意天数，统一叫"统计报表"。
    await _saveExcel(excelFile, '统计报表_${_startDate}_至_$_endDate');
  }

  /// 导出当前区间的排名（原"历史记录-导出排名"迁移到这里）。
  Future<void> _exportRanking() async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    final records = provider.getRecordsForDates(
      StatisticsService.datesBetween(_startDate, _endDate),
    );
    if (records.isEmpty) {
      showTopSnackBar(context, '该范围内没有可导出的记录', isError: true);
      return;
    }
    final result = StatisticsService.compute(
      records,
      includePraise: provider.appData.settings.praiseEnabled,
      includeCriticize: provider.appData.settings.criticismEnabled,
    );
    // 两类排名都为空（区间内只有"其它"非法类型）时不生成任何 sheet，
    // 否则会留下空白 Sheet1 却提示导出成功（审计 P2-27）。
    if (result.praiseRanking.isEmpty && result.criticizeRanking.isEmpty) {
      showTopSnackBar(context, '该范围内没有可排名的表扬/批评记录', isError: true);
      return;
    }

    final excelFile = ExcelExport.newWorkbook();
    // 只导出有点数的类型：区间内只有表扬就只出表扬排名，反之亦然。
    if (result.praiseRanking.isNotEmpty) {
      final praiseSheet = excelFile['表扬排名'];
      praiseSheet.appendRow([TextCellValue('时间范围：$_startDate 至 $_endDate')]);
      praiseSheet.appendRow([
        TextCellValue('排名'),
        TextCellValue('学生姓名'),
        TextCellValue('表扬次数'),
      ]);
      var praiseRank = 0;
      var prevPraise = -1;
      for (final item in result.praiseRanking) {
        if (item.count != prevPraise) {
          praiseRank++;
          prevPraise = item.count;
        }
        praiseSheet.appendRow([
          IntCellValue(praiseRank),
          TextCellValue(item.name),
          IntCellValue(item.count),
        ]);
      }
      ExcelExport.autoFitColumns(praiseSheet);
    }

    if (result.criticizeRanking.isNotEmpty) {
      final criticismSheet = excelFile['批评排名'];
      criticismSheet.appendRow([TextCellValue('时间范围：$_startDate 至 $_endDate')]);
      criticismSheet.appendRow([
        TextCellValue('排名'),
        TextCellValue('学生姓名'),
        TextCellValue('批评次数'),
      ]);
      var criticismRank = 0;
      var prevCriticism = -1;
      for (final item in result.criticizeRanking) {
        if (item.count != prevCriticism) {
          criticismRank++;
          prevCriticism = item.count;
        }
        criticismSheet.appendRow([
          IntCellValue(criticismRank),
          TextCellValue(item.name),
          IntCellValue(item.count),
        ]);
      }
      ExcelExport.autoFitColumns(criticismSheet);
    }

    // 默认创建的空工作表不再使用就删掉，避免导出文件里多出一页空白 Sheet1。
    if (excelFile.tables.containsKey('Sheet1') && excelFile.tables.length > 1) {
      excelFile.delete('Sheet1');
    }
    await _saveExcel(excelFile, '排名_${_startDate}_至_$_endDate');
  }

  /// 保存导出的工作簿（修复 审查 二-1：实现统一到 ExcelExport.saveWorkbook，
  /// 此前与记录列表各写一份且行为已分歧）。
  Future<void> _saveExcel(excel.Excel excelFile, String fileName) async {
    try {
      final provider = Provider.of<AppDataProvider>(context, listen: false);
      if (!await ensurePasswordForAction(
        context,
        provider,
        PasswordAction.recordExport,
        message: '导出统计表会包含学生姓名等明文信息，请先进入班主任管理。',
      )) {
        return;
      }
      if (!mounted) return;
      final exportPath = provider.appData.settings.exportPath;
      final baseName = provider.withExportPrefix(fileName);

      final savedPath = await ExcelExport.saveWorkbook(
        excelFile,
        baseName: baseName,
        exportPath: exportPath,
      );
      if (!mounted) return;
      showTopSnackBar(
        context,
        savedPath == null ? '已取消导出' : '已导出明文表格（含学生姓名）: $savedPath',
      );
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, exportFailureMessage(e), isError: true);
    }
  }
}
