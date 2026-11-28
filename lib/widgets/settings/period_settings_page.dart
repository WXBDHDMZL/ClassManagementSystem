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
part of '../settings_pages.dart';

/// 时间段设置页（段落名称与顺序）。
class PeriodSettingsPage extends StatefulWidget {
  const PeriodSettingsPage({super.key});

  @override
  State<PeriodSettingsPage> createState() => _PeriodSettingsPageState();
}

class _PeriodRow {
  _PeriodRow(this.key, String label)
      : controller = TextEditingController(text: label);

  final String key;
  final TextEditingController controller;
}

class _PeriodSettingsPageState extends State<PeriodSettingsPage> {
  late final List<_PeriodRow> _rows = [
    for (final item in effectivePeriods())
      _PeriodRow(item['key']!, item['label']!),
  ];

  @override
  void dispose() {
    for (final row in _rows) {
      row.controller.dispose();
    }
    super.dispose();
  }

  Future<bool> _requireModify(AppDataProvider provider) {
    return ensurePasswordForAction(
      context,
      provider,
      PasswordAction.periodModify,
      message: '修改时间段前请先进入班主任管理。',
    );
  }

  void _add() {
    setState(() {
      _rows.add(
        _PeriodRow(
          'custom_${DateTime.now().millisecondsSinceEpoch}',
          '',
        ),
      );
    });
  }

  Future<void> _remove(int index) async {
    final row = _rows[index];
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    if (!await _requireModify(provider) || !mounted) return;
    // B-06：删除时段前提示影响的考勤条数；历史考勤已保存显示名快照，
    // 删除时段不会把已保存的中文名清掉（旧数据没有快照的会退化）。
    final affected = AttendanceFeature.enabled
        ? provider.countAttendanceUsingPeriodKey(row.key)
        : 0;
    if (affected > 0) {
      final confirmed = await confirmDestructive(
        context,
        title: '删除时段',
        message: '该时段有 $affected 条历史考勤。删除并保存后，这些考勤仍会保留，'
            '但之后新登记的考勤不会再使用该时段。\n\n确定删除吗？',
        confirmLabel: '仍要删除',
      );
      if (confirmed != true || !mounted) return;
    }
    // 审查 L13：先摘下并释放控制器，再 setState —— 此前 dispose 在 setState
    // 回调内执行，语义上"本帧仍可能读到已释放对象"（当前无实际后果，
    // 属防御性加固，避免未来渲染逻辑变化时触碰 debugAssertNotDisposed）。
    final removed = _rows.removeAt(index);
    removed.controller.dispose();
    setState(() {});
  }

  Future<void> _import() async {
    final periods = await PeriodImportDialog.show(context);
    if (!mounted || periods == null) return;
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    final incomingKeys = {for (final item in periods) item['key']!};
    final removedKeys = [
      for (final row in _rows)
        if (!incomingKeys.contains(row.key)) row.key,
    ];
    var affectedRecords = 0;
    var affectedAttendance = 0;
    for (final key in removedKeys) {
      affectedRecords += provider.countRecordsUsingPeriodKey(key);
      if (AttendanceFeature.enabled) {
        affectedAttendance += provider.countAttendanceUsingPeriodKey(key);
      }
    }
    if (affectedRecords + affectedAttendance > 0) {
      final confirmed = await confirmDestructive(
        context,
        title: '导入时段表',
        message: '导入的时段表不包含当前 ${removedKeys.length} 个时段，'
            '其中仍被 $affectedRecords 条记录、$affectedAttendance 条考勤引用。\n\n'
            '继续导入并保存后，这些历史记录与考勤仍会保留，'
            '但新记录不能再选择这些时段。确定导入吗？',
        confirmLabel: '仍要导入',
      );
      if (confirmed != true || !mounted) return;
    }
    final oldRows = List<_PeriodRow>.from(_rows);
    for (final row in oldRows) {
      row.controller.dispose();
    }
    _rows
      ..clear()
      ..addAll([
        for (final item in periods)
          _PeriodRow(item['key']!, item['label']!),
      ]);
    setState(() {});
    showTopSnackBar(context, '已填入时段列表，点击保存后生效');
  }

  Future<void> _save() async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    if (!await _requireModify(provider) || !mounted) return;
    final periods = <Map<String, String>>[];
    final seenLabels = <String>{};
    for (final row in _rows) {
      final label = row.controller.text.trim();
      final error = validatePeriodLabel(label);
      if (error != null) {
        showTopSnackBar(context, error, isError: true);
        return;
      }
      if (!seenLabels.add(label)) {
        showTopSnackBar(context, '时段名称不能重复：$label', isError: true);
        return;
      }
      periods.add({'key': row.key, 'label': label});
    }
    if (periods.isEmpty) {
      showTopSnackBar(context, '至少需要保留一个时段', isError: true);
      return;
    }
    // P1-1 修复：此前用 effectivePeriods() 当"出厂基线"，而它在存在自定义时段时
    // 返回的就是自定义列表本身，导致"不动直接保存"会把自定义时段清空回出厂 9 段。
    // 现在无条件保存用户当前编辑的时段。
    final saved = provider.setPeriods(periods);
    showTopSnackBar(
      context,
      saved
          ? '已保存，记录预选、显示与导出将使用新的时段'
          : '时段未保存：当前无法写入数据文件，请先处理数据提示后重试',
      isError: !saved,
    );
  }

  Future<void> _resetToDefaults() async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    if (!await _requireModify(provider) || !mounted) return;
    final confirmed = await _confirmAction(
      context,
      title: '恢复出厂时段',
      message: '将把时段恢复为出厂的 9 段并清除自定义的增删与改名，'
          '历史记录与统计里已保存的时段不受影响。确定吗？',
    );
    if (confirmed != true || !mounted) return;
    // 审查 L13：同 _remove —— 先释放旧控制器，再整体换新行并 setState。
    final oldRows = List<_PeriodRow>.from(_rows);
    for (final row in oldRows) {
      row.controller.dispose();
    }
    _rows
      ..clear()
      ..addAll([
        for (final entry in timePeriods.entries)
          _PeriodRow(entry.key, entry.value),
      ]);
    setState(() {});
    final saved = Provider.of<AppDataProvider>(
      context,
      listen: false,
    ).setPeriods(const []);
    showTopSnackBar(
      context,
      saved ? '已恢复出厂时段设置' : '恢复出厂未保存：当前无法写入数据文件，请先处理数据提示后重试',
      isError: !saved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 风格统一（V2.30.9）：其它设置页都以 SettingsSectionTitle 开头，本页此前直接是提示文字。
        const SettingsSectionTitle('时段列表'),
        const SettingsHint(
          '格式为"时间段 名称"，可写多段（用、分隔），名称放在最后，'
          '例如：08:00-12:30、14:00-16:40 上课。可新增或删除时段；'
          '记录时的自动预选、显示与导出都会使用这里的设置。',
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _rows[i].controller,
                    decoration: const InputDecoration(
                      hintText: '如 08:00-12:30 上课',
                      // 风格统一（V2.30.9）：输入框圆角此前是 Material 默认小圆角，
                      // 与其它设置页的 AppRadius 输入框不一致。
                      border: OutlineInputBorder(
                        borderRadius: AppRadius.field,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '删除该时段',
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: () => _remove(i),
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('新增时段'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _import,
          icon: const Icon(Icons.upload_file, size: 16),
          label: const Text('导入时段'),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SettingsActionButton(label: '保存', onPressed: _save),
            ),
            const SizedBox(width: 8),
            Expanded(
              // 风格统一（V2.30.9）：与数据页/考勤页的"恢复出厂"按钮统一为图标描边款。
              child: OutlinedButton.icon(
                onPressed: _resetToDefaults,
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('恢复出厂时段'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
