/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.8
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_data_provider.dart';
import '../constants/attendance_feature.dart';
import '../constants/time_periods.dart';
import '../constants/app_theme.dart';
import '../models/student_record.dart';
import './identity_picker_dialog.dart';
import './record_list.dart';
import '../utils/app_clock.dart';

/// 打开批量追加对话框（历史记录页与主界面“批量”入口共用）：
/// 恰好 1 人时按单人追加处理，2 人及以上一次写入。
///
/// [date] 为空表示“此刻记录”，由 Provider 按所选时段计算归属日
/// （主界面批量入口）；历史页补录必须传入明确日期。
Future<void> showAppendRecordDialog(
  BuildContext context, {
  String? date,
  required List<String> students,
  String? initialOperationType,
}) {
  if (students.isEmpty) return Future<void>.value();
  if (students.length == 1) {
    return showDialog<void>(
      context: context,
      builder: (context) => RecordDialog(
        studentName: students.first,
        targetDate: date,
        isAppend: date != null,
        initialOperationType: initialOperationType,
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => RecordDialog(
      studentName: '',
      targetDate: date,
      isAppend: date != null,
      isBatch: true,
      selectedStudents: List<String>.unmodifiable(students),
      initialOperationType: initialOperationType,
    ),
  );
}

/// 记录操作对话框：选择表扬/批评、时间段、原因（支持自定义）与备注。
/// 同时承担三种场景：新建记录、编辑已有记录（editRecord）、批量追加记录（selectedStudents）。
class RecordDialog extends StatefulWidget {
  final String studentName;
  final StudentRecord? editRecord;
  final String? targetDate;
  final bool isAppend;
  final bool isBatch;
  final List<String>? selectedStudents;

  /// 新建记录时预选的类型（悬浮球快速记录用：表扬/批评）。
  final String? initialOperationType;

  const RecordDialog({
    super.key,
    required this.studentName,
    this.editRecord,
    this.targetDate,
    this.isAppend = false,
    this.isBatch = false,
    this.selectedStudents,
    this.initialOperationType,
  });

  @override
  State<RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<RecordDialog> {
  String _operationType = '批评';
  String? _selectedPeriod;
  List<String> _selectedReasons = [];

  /// 原因较多时默认只显示常用的一部分，其余折叠（已选项始终可见）。
  static const int _reasonPreviewCount = 8;
  bool _showAllReasons = false;

  /// "按使用频率排序"的使用次数缓存（审计 P2-63）：此前每次 build 都全库
  /// 扫描一遍原因使用次数（切换类型/时段会反复触发），大库下有卡顿。
  Map<String, int>? _usageCountsCache;
  String _customReason = '';
  String _customRemark = '';
  String? _selectedStudent;

  late final TextEditingController _customReasonController =
      TextEditingController(text: _customReason);
  late final TextEditingController _customRemarkController =
      TextEditingController(text: _customRemark);

  @override
  void initState() {
    super.initState();
    // 接口陷阱（建议级）：selectedStudents 只用于"≥2 人批量追加"——见
    // history_dialog 的用法：恰好 1 人时改传 studentName + isAppend、不传本列表。
    // 若误传恰好 1 人，界面会按"追加记录"渲染学生选择器，而保存逻辑却直接用该
    // 列表内容，二者不一致。这里在 debug 下直接拦下，避免调用方踩坑。
    assert(
      widget.selectedStudents == null || widget.selectedStudents!.length != 1,
      'selectedStudents 仅用于 2 人及以上的批量追加；单人请改用 studentName',
    );
    _selectedStudent = widget.studentName.isNotEmpty
        ? widget.studentName
        : null;
    if (widget.editRecord != null) {
      _operationType = widget.editRecord!.operationType;
      _selectedPeriod = widget.editRecord!.periodKey;
      final allReasons = widget.editRecord!.reasons
          .split('、')
          .where((r) => r.isNotEmpty)
          .toList();
      // 预置原因归入选中项；非预置原因视为自定义原因，
      // 填入输入框以便编辑时直接修改（同备注逻辑），避免新旧自定义原因叠加。
      final preset = _currentReasons;
      _selectedReasons = allReasons.where(preset.contains).toList();
      _customReason = allReasons.where((r) => !preset.contains(r)).join('、');
      _customReasonController.text = _customReason;
      _customRemark = widget.editRecord!.remark;
      _customRemarkController.text = _customRemark;
    } else {
      // 默认类型必须收敛到"启用的记录类型"：设置里停用批评后，
      // 出厂默认（批评）会让界面只剩未选中的"表扬"，却仍按批评提交。
      _operationType =
          _enabledOperationType(widget.initialOperationType ?? _defaultOperationType());
      if (Provider.of<AppDataProvider>(context, listen: false)
          .appData
          .settings
          .autoSelectPeriod) {
        _selectedPeriod = _getCurrentPeriod();
      }
    }
  }

  @override
  void dispose() {
    _customReasonController.dispose();
    _customRemarkController.dispose();
    super.dispose();
  }

  /// 记录对话框的默认操作类型：可固定表扬/批评，或跟随上次使用。
  String _defaultOperationType() {
    final settings =
        Provider.of<AppDataProvider>(context, listen: false).appData.settings;
    switch (settings.recordDefaultType) {
      case 1:
        return '批评';
      case 2:
        return settings.lastOperationType == 1 ? '批评' : '表扬';
      default:
        return '表扬';
    }
  }

  /// 把期望的操作类型收敛到"设置里启用的记录类型"：
  /// 停用的类型不能作为默认值（两者至少启用一个，故一定有可用类型）。
  String _enabledOperationType(String preferred) {
    final settings =
        Provider.of<AppDataProvider>(context, listen: false).appData.settings;
    if (preferred == '表扬' && !settings.praiseEnabled) return '批评';
    if (preferred == '批评' && !settings.criticismEnabled) return '表扬';
    return preferred;
  }

  /// 按当前时刻自动预选时段（时段划分可在设置里自定义）。
  String? _getCurrentPeriod() {
    final now = AppClock.now();
    return matchPeriodByMinutes(now.hour * 60 + now.minute);
  }

  /// 当前可选原因：取自 provider 中的原因库（专属项 + 全时段通用项）。
  /// 开启"按使用频率排序"时，按历史使用次数从多到少排列（次数相同保持库内顺序）。
  List<String> get _currentReasons {
    final provider = context.read<AppDataProvider>();
    final library = provider.appData.reasons;
    final reasons = library.forPeriod(
      _operationType,
      _selectedPeriod ?? '_common',
    );
    if (!provider.appData.settings.reasonSortByUsage) return reasons;
    // 审计 P2-63：缓存使用次数（对话框生命周期内不变）。
    final counts = _usageCountsCache ??= provider.reasonUsageCounts();
    final sorted = List<String>.from(reasons);
    sorted.sort((a, b) {
      final byCount = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
      if (byCount != 0) return byCount;
      return reasons.indexOf(a).compareTo(reasons.indexOf(b));
    });
    return sorted;
  }

  /// 折叠时展示的原因：已选的始终展示，其余取常用（库内已按频率排序）的前若干个。
  List<String> get _visibleReasons {
    final all = _currentReasons;
    if (_showAllReasons || all.length <= _reasonPreviewCount) return all;
    final visible = <String>[..._selectedReasons.where(all.contains)];
    for (final reason in all) {
      if (visible.length >= _reasonPreviewCount) break;
      if (!visible.contains(reason)) visible.add(reason);
    }
    return visible;
  }

  void _toggleReason(String reason) {
    setState(() {
      if (_selectedReasons.contains(reason)) {
        _selectedReasons.remove(reason);
      } else {
        _selectedReasons.add(reason);
      }
    });
  }

  /// 切换操作类型/时间段后，剔除不再可见的已选原因，防止隐藏选项被提交。
  void _pruneReasons() {
    final valid = _currentReasons;
    _selectedReasons = _selectedReasons.where(valid.contains).toList();
  }

  void _selectOperation(String label) {
    setState(() {
      _operationType = label;
      _showAllReasons = false;
      _pruneReasons();
    });
  }

  void _selectPeriod(String? key) {
    setState(() {
      _selectedPeriod = key;
      _pruneReasons();
    });
  }

  void _submit() {
    final identityProvider = context.read<AppDataProvider>();
    if (identityProvider.identityFeatureEnabled &&
        identityProvider.activeIdentity == null) {
      showTopSnackBar(context, '请先选择本次记录人', isError: true);
      unawaited(showIdentityPicker(context));
      return;
    }
    final allReasons = [..._selectedReasons];
    // 修复（审计 P1-11）：自定义原因框可能承载**多条**原因（编辑含多个非预置
    // 原因的记录时以"、"拼接回填）——提交时按顿号拆回多条，否则会被当成一条
    //（净化把顿号换成逗号），原因条数与统计口径随之改变；全空格输入同时被拦下。
    for (final part in _customReason.split('、')) {
      final reason = part.trim();
      if (reason.isNotEmpty) allReasons.add(reason);
    }

    if (allReasons.isEmpty) {
      showTopSnackBar(context, '请至少选择一个原因或填写自定义原因', isError: true);
      return;
    }

    final remark = _customRemark;
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    // 追加记录（事后补录）与当天记录用不同提示文案。
    final isAppend = widget.targetDate != null || widget.isAppend;

    if (widget.editRecord != null) {
      final updated = provider.updateRecord(
        widget.editRecord!.id,
        _operationType,
        allReasons,
        _selectedPeriod ?? '',
        remark,
        date: widget.targetDate,
      );
      if (!updated) {
        showTopSnackBar(context, '未找到该记录，可能已被删除', isError: true);
        return;
      }
      showUndoTopSnackBar(
        context,
        '已修改记录',
        onUndo: provider.undoLastRecordChange,
      );
      Navigator.pop(context);
      return;
    }

    if (!provider.canActiveIdentityAddRecord) {
      showTopSnackBar(context, '当前身份没有普通模式新增记录权限', isError: true);
      return;
    }

    final targetStudents = widget.selectedStudents ?? [];
    if (targetStudents.isNotEmpty) {
      // 一次写盘：逐条 addRecord 会触发 N 次整库加密保存，全班 50 人时会明显卡顿。
      final added = provider.addRecordsForStudents(
        targetStudents,
        _operationType,
        allReasons,
        _selectedPeriod ?? '',
        remark,
        isAppended: isAppend,
        isBatch: widget.isBatch,
        date: widget.targetDate,
      );
      if (added <= 0) {
        showTopSnackBar(context, '没有添加任何记录', isError: true);
        return;
      }
      showUndoTopSnackBar(
        context,
        isAppend
            ? '已为 $added 名学生追加记录'
            : '已为 $added 名学生添加记录',
        onUndo: provider.undoLastRecordChange,
      );
      Navigator.pop(context);
      return;
    }

    if (_selectedStudent == null || _selectedStudent!.isEmpty) {
      showTopSnackBar(context, '请选择学生', isError: true);
      return;
    }

    final record = provider.addRecord(
      _selectedStudent!,
      _operationType,
      allReasons,
      _selectedPeriod ?? '',
      remark,
      isAppended: isAppend,
      isBatch: widget.isBatch,
      date: widget.targetDate,
    );
    if (record == null) {
      showTopSnackBar(context, '没有添加任何记录', isError: true);
      return;
    }

    showUndoTopSnackBar(
      context,
      isAppend
          ? '已追加：${_selectedStudent!} · $_operationType'
          : '已记录：${_selectedStudent!} · $_operationType',
      onUndo: provider.undoLastRecordChange,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final settings = provider.appData.settings;
    final isEditing = widget.editRecord != null;
    final batchStudents = widget.selectedStudents ?? <String>[];
    final isBatchAppend = batchStudents.length >= 2;
    final isAppendMode = widget.studentName.isEmpty && !isBatchAppend;
    // 停用的类型只在"当前记录本身就是该类型"（编辑历史记录）时一并显示，
    // 避免出现"两个按钮都没选中"、看不出当前类型的困惑。
    final showPraise = settings.praiseEnabled || _operationType == '表扬';
    final showCriticism = settings.criticismEnabled || _operationType == '批评';
    // 标题：批量追加时最多显示前两名学生，超过两人追加"等"。
    final String title;
    if (isEditing) {
      title = '编辑 ${widget.studentName} 的记录';
    } else if (isBatchAppend) {
      final shown = batchStudents.take(2).join('、');
      title = batchStudents.length > 2
          ? '为 $shown 等 ${batchStudents.length} 人操作'
          : '为 $shown 操作';
    } else if (isAppendMode) {
      title = '追加记录';
    } else {
      title = '为 ${widget.studentName} 操作';
    }

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (settings.identityFeatureEnabled) ...[
                const SizedBox(height: 12),
                IdentityBanner(
                  identity: provider.activeIdentity,
                  isEditing: isEditing,
                  originalRecordedBy: widget.editRecord?.recordedBy ?? '',
                ),
              ],
              const SizedBox(height: 20),
              if (isAppendMode) ...[
                Text('选择学生', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: provider.appData.students.map((student) {
                    return FilterChip(
                      label: Text(student),
                      selected: _selectedStudent == student,
                      onSelected: (_) => setState(() {
                        _selectedStudent = student;
                      }),
                      backgroundColor: theme.cardColor,
                      selectedColor: theme.colorScheme.primary.withValues(
                        alpha: 0.2,
                      ),
                      checkmarkColor: theme.colorScheme.primary,
                      labelStyle: TextStyle(
                        color: _selectedStudent == student
                            ? theme.colorScheme.primary
                            : theme.textTheme.bodyMedium?.color,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.sheet,
                      ),
                      side: BorderSide(color: theme.dividerColor),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
              ],
              // 只显示"启用的记录类型"；两者至少保留一个，因此不会出现空行。
              Row(
                children: [
                  if (showCriticism)
                    Expanded(child: _buildOperationButton('批评', false)),
                  if (showCriticism && showPraise) const SizedBox(width: 12),
                  if (showPraise)
                    Expanded(child: _buildOperationButton('表扬', true)),
                ],
              ),
              if (_operationTypeDisabled) ...[
                const SizedBox(height: 6),
                Text(
                  '提示：「$_operationType」已在"设置 → 记录与名单 → 记录设置"中停用，'
                  '保存时仍按原类型保留；如需改成其它类型，请点上面的按钮。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.semantic.warning,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text('时间段选择', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in effectivePeriods())
                    _buildPeriodChip(entry['key']!, entry['label']!),
                  // 记录自身的时间段不在常规列表里时补一个（如考勤同步的"全天"），
                  // 否则会出现"没有任何时段被选中"的困惑。
                  if (_selectedPeriod != null &&
                      !effectivePeriods().any(
                        (entry) => entry['key'] == _selectedPeriod,
                      ))
                    _buildPeriodChip(
                      _selectedPeriod!,
                      // 修复（审计 P1-12）："时段无法识别"的导入记录（key 为空）
                      // 回退显示保存的原始时段名，而不是空白 chip。
                      periodNameForRecord(
                        _selectedPeriod!,
                        widget.editRecord?.periodName ?? '',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('原因选择', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  if (_currentReasons.length > _reasonPreviewCount)
                    TextButton.icon(
                      icon: Icon(
                        _showAllReasons ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                      ),
                      label: Text(
                        _showAllReasons
                            ? '收起'
                            : '展开全部（${_currentReasons.length}）',
                      ),
                      onPressed: () => setState(
                        () => _showAllReasons = !_showAllReasons,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _visibleReasons.map(_buildReasonChip).toList(),
              ),
              const SizedBox(height: 12),
              _buildCustomReasonInput(),
              // 命中"考勤同步"的原因会同时登记考勤，提前告知避免意外。
              if (_syncedStatusText.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.how_to_reg_outlined,
                      size: 16,
                      color: theme.semantic.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _syncedStatusText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.semantic.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Text('备注', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                // N-2：上限在输入时就可见（带字数计数器），不再"提交后静默截断"。
                maxLength: AppDataProvider.maxRemarkLength,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                  hintText: '备注内容',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                onChanged: (value) => _customRemark = value,
                controller: _customRemarkController,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.sheet,
                      ),
                    ),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.sheet,
                      ),
                    ),
                    child: const Text('确认'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOperationButton(String label, bool isPraise) {
    final theme = Theme.of(context);
    final isSelected = _operationType == label;
    // 语义色随主题亮度自动适配（表扬绿 / 批评红）
    final color = isPraise ? theme.semantic.praise : theme.semantic.criticize;

    return ElevatedButton(
      onPressed: () => _selectOperation(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? color : theme.colorScheme.surface,
        foregroundColor: isSelected
            ? theme.semantic.onSemantic
            : theme.colorScheme.onSurface,
        side: BorderSide(color: isSelected ? color : theme.colorScheme.outline),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      ),
      child: Text(label),
    );
  }

  Widget _buildPeriodChip(String key, String label) {
    final theme = Theme.of(context);
    final isSelected = _selectedPeriod == key;

    return FilterChip(
      // 修复（审计 P1-12）：key 为空（时段无法识别）时显示原始时段名。
      label: Text(
        key.isEmpty
            ? (label.isNotEmpty ? label : '未标注时段')
            : getTimePeriodShortName(key),
      ),
      selected: isSelected,
      onSelected: (_) => _selectPeriod(isSelected ? null : key),
      backgroundColor: theme.cardColor,
      selectedColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      checkmarkColor: theme.colorScheme.primary,
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.primary
            : theme.textTheme.bodyMedium?.color,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      side: BorderSide(color: theme.dividerColor),
    );
  }

  /// 当前选中的类型是否已在设置里停用（编辑历史记录时可能出现）。
  bool get _operationTypeDisabled {
    final settings =
        Provider.of<AppDataProvider>(context, listen: false).appData.settings;
    return (_operationType == '表扬' && !settings.praiseEnabled) ||
        (_operationType == '批评' && !settings.criticismEnabled);
  }

  /// 当前选中的原因里会同步到考勤的提示文案（没有则返回空）。
  String get _syncedStatusText {
    if (!AttendanceFeature.enabled) return '';
    if (_operationType != '批评') return '';
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    // 修复（审计 P2-67）：按**最终原因集合**计算（含自定义原因）——
    // 此前只扫预置原因，自定义原因命中同步映射时没有任何提示。
    final allReasons = <String>[
      ..._selectedReasons,
      for (final part in _customReason.split('、'))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    final matched = <String>[];
    for (final reason in allReasons) {
      final status = provider.attendanceStatusForReason(reason);
      if (status.isNotEmpty && !matched.contains(status)) matched.add(status);
    }
    if (matched.isEmpty) return '';
    return '保存后会同步登记考勤：${matched.join('、')}（撤销该记录时考勤一并撤销）';
  }

  Widget _buildReasonChip(String reason) {
    final theme = Theme.of(context);
    final isSelected = _selectedReasons.contains(reason);

    return FilterChip(
      label: Text(reason),
      selected: isSelected,
      onSelected: (_) => _toggleReason(reason),
      backgroundColor: theme.cardColor,
      selectedColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      checkmarkColor: theme.colorScheme.primary,
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.primary
            : theme.textTheme.bodyMedium?.color,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      side: BorderSide(color: theme.dividerColor),
    );
  }

  Widget _buildCustomReasonInput() {
    return TextField(
      // N-2：原因上限（50 字）在输入时可见，避免超长原因被静默截断。
      maxLength: AppDataProvider.maxReasonLength,
      decoration: const InputDecoration(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        hintText: '自定义原因',
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      // 修复（审计 P2-67）：输入自定义原因时即时刷新 —— 否则"保存后会同步
      // 登记考勤"的提示要等到下一次 rebuild（如切换原因）才会出现。
      onChanged: (value) => setState(() => _customReason = value),
      controller: _customReasonController,
    );
  }
}

