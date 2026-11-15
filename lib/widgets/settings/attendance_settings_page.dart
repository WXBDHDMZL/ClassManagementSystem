/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.7
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../settings_pages.dart';

/// 考勤设置页（状态映射等）。
class AttendanceSettingsPage extends StatefulWidget {
  const AttendanceSettingsPage({super.key});

  @override
  State<AttendanceSettingsPage> createState() => _AttendanceSettingsPageState();
}

class _AttendanceSettingsPageState extends State<AttendanceSettingsPage> {
  final TextEditingController _addController = TextEditingController();

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<bool> _requireSettings(AppDataProvider provider) {
    return ensurePasswordForAction(
      context,
      provider,
      PasswordAction.attendanceSettings,
      message: '修改考勤设置与状态项前请先进入班主任管理。',
    );
  }

  Future<void> _add(AppDataProvider provider) async {
    if (!await _requireSettings(provider) || !mounted) return;
    final value = _addController.text.trim();
    final statuses = provider.appData.settings.attendanceStatuses;
    final error = AttendanceRecord.validateStatus(value);
    if (error != null) {
      showTopSnackBar(context, error, isError: true);
      return;
    }
    if (statuses.contains(value)) {
      showTopSnackBar(context, '考勤状态「$value」已存在', isError: true);
      return;
    }
    _addController.clear();
    provider.setAttendanceStatuses([...statuses, value]);
    showTopSnackBar(context, '已新增考勤状态「$value」');
  }

  Future<void> _rename(AppDataProvider provider, String status) async {
    if (!await _requireSettings(provider) || !mounted) return;
    final value = await showTextPrompt(
      context,
      title: '修改考勤状态',
      initialValue: status,
    );
    if (value == null || !mounted) return;
    final trimmed = value.trim();
    final error = AttendanceRecord.validateStatus(trimmed);
    if (error != null) {
      showTopSnackBar(context, error, isError: true);
      return;
    }
    if (trimmed == status) return;
    if (provider.appData.settings.attendanceStatuses.contains(trimmed)) {
      showTopSnackBar(context, '考勤状态「$trimmed」已存在', isError: true);
      return;
    }
    provider.renameAttendanceStatus(status, trimmed);
    showTopSnackBar(context, '已改为「$trimmed」，历史考勤记录同步更新');
  }

  /// 修改某状态同步的批评原因；留空表示不生成批评记录。
  Future<void> _editSync(AppDataProvider provider, String status) async {
    if (!await _requireSettings(provider) || !mounted) return;
    final current = provider.attendanceSyncReasonFor(status);
    final result = await showTextPrompt(
      context,
      title: '「$status」同步的批评原因',
      initialValue: current,
      label: '批评原因（留空表示不同步）',
    );
    if (result == null || !mounted) return;
    final map = Map<String, String>.from(
      provider.appData.settings.attendanceSyncMap,
    );
    final value = result.trim();
    if (value.isEmpty) {
      map.remove(status);
      provider.setAttendanceSyncMap(map);
      showTopSnackBar(context, '「$status」不再生成批评记录');
      return;
    }
    if (value == AttendanceRecord.presentStatus) {
      showTopSnackBar(
        context,
        '「${AttendanceRecord.presentStatus}」是保留状态，不能作为同步的批评原因',
        isError: true,
      );
      return;
    }
    // 说明（审查 五-6）：原先这里还有一段"value 为空"的判断，但上面
    //（value.isEmpty 时已 return）之后不可能再为空 —— 死代码，已删除。
    map[status] = value;
    provider.setAttendanceSyncMap(map);
    showTopSnackBar(context, '「$status」将同步批评原因「$value」');
  }

  Future<void> _remove(AppDataProvider provider, String status) async {
    if (!await _requireSettings(provider) || !mounted) return;
    final statuses = provider.appData.settings.attendanceStatuses;
    if (statuses.length <= 1) {
      showTopSnackBar(context, '至少需要保留一个考勤状态', isError: true);
      return;
    }
    final used = provider.countAttendanceWithStatus(status);
    // 修复（审计 P2-31）：若该状态计入"未到"，删除会同时改变历史统计的
    // 实到人数 —— 在确认文案里如实说明。
    final affectsPresent =
        provider.appData.settings.attendanceAbsentStatuses.contains(status);
    final confirmed = await _confirmAction(
      context,
      title: '删除考勤状态',
      message: used == 0
          ? '确定删除考勤状态「$status」吗？'
          : '有 $used 条考勤记录使用「$status」：删除该状态后，这些记录会显示为'
                '「$status（已停用）」，可重新改名恢复。'
                '${affectsPresent ? '该状态当前计入"未到"：删除后历史统计的"实到"人数会相应变化。' : ''}'
                '确定删除吗？',
    );
    if (confirmed != true || !mounted) return;
    provider.setAttendanceStatuses(
      statuses.where((item) => item != status).toList(),
    );
    showTopSnackBar(context, '已删除考勤状态「$status」');
  }

  Future<void> _resetToDefaults(AppDataProvider provider) async {
    if (!await _requireSettings(provider) || !mounted) return;
    final confirmed = await _confirmAction(
      context,
      title: '恢复出厂考勤状态',
      message: '将把状态项恢复为"迟到 / 早退 / 请假 / 缺勤"，'
          '自定义状态项与"考勤→批评"的同步映射会被清除；'
          '历史考勤记录本身不会删除，但使用被清除状态的记录会显示为"已停用"。确定吗？',
    );
    if (confirmed != true || !mounted) return;
    provider.setAttendanceStatuses(AppSettings.defaultAttendanceStatuses);
    showTopSnackBar(context, '已恢复出厂考勤状态');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final settings = provider.appData.settings;
    final statuses = settings.attendanceStatuses;
    final syncMap = settings.attendanceSyncMap;
    final absentStatuses = settings.attendanceAbsentStatuses;
    final muted = mutedTextColor(theme, 0.65);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('考勤功能'),
        SwitchListTile(
          value: settings.attendanceEnabled,
          onChanged: (value) async {
            final provider = Provider.of<AppDataProvider>(context, listen: false);
            if (!await _requireSettings(provider) || !mounted) return;
            provider.setAttendanceEnabled(value);
          },
          title: Text('启用考勤', style: theme.textTheme.bodyMedium),
          subtitle: Text(
            settings.attendanceEnabled
                ? '记录列表中已显示"考勤"入口：默认全员到齐，只登记请假、缺勤等异常'
                : '关闭时记录列表不显示"考勤"入口，已有考勤数据仍会保留',
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              height: 1.4,
            ),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 16),
        const SettingsSectionTitle('考勤状态项'),
        const SettingsHint(
          '登记异常时可选择的状态，例如 迟到、早退、请假、缺勤。'
          '没有登记的学生一律视为"出勤"，因此"出勤"不能作为状态项。'
          '改名会同步更新已有考勤记录；删除后使用该状态的记录会显示为"已停用"，可重新改名恢复。\n'
          '每个人名前的图标控制"实到"口径：计为未到的状态（默认 请假、缺勤）会减少实到人数，'
          '迟到、早退这类"到了但不合规范"的状态默认不减实到，可按需调整。',
        ),
        const SizedBox(height: 10),
        for (final status in statuses)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: AppRadius.field,
              border: Border.all(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          '${absentStatuses.contains(status) ? '计为未到（减实到）' : '到校（不减实到）'}'
                          ' · ${syncMap[status] == null ? '不生成批评记录' : '同步批评原因：${syncMap[status]}'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      absentStatuses.contains(status)
                          ? Icons.person_off_outlined
                          : Icons.person_outline,
                      size: 20,
                    ),
                    tooltip: absentStatuses.contains(status)
                        ? '当前计为未到（点击改为"到校"）'
                        : '当前计为到校（点击改为"未到"）',
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: () async {
                      final ok = await _requireSettings(provider);
                      if (!ok) return;
                      if (!mounted) return;
                      final next = List<String>.from(absentStatuses);
                      if (next.contains(status)) {
                        next.remove(status);
                      } else {
                        next.add(status);
                      }
                      provider.setAttendanceAbsentStatuses(next);
                      showTopSnackBar(
                        // ignore: use_build_context_synchronously
                        context,
                        next.contains(status)
                            ? '「$status」将计入未到（减少实到人数）'
                            : '「$status」不再计入未到（不减实到）',
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.sync_alt, size: 20),
                    tooltip: '设置同步的批评原因',
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: () => _editSync(provider, status),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    tooltip: '修改名称',
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: () => _rename(provider, status),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20),
                    tooltip: '删除',
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: () => _remove(provider, status),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _addController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(AppRadius.cardValue)),
                  ),
                  hintText: '输入考勤状态，如 事假',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _add(provider),
              ),
            ),
            const SizedBox(width: 8),
            SettingsActionButton(
              label: '新增',
              onPressed: () => _add(provider),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 风格统一（V2.30.9）：与时间段页/数据页的"恢复出厂"按钮一致（描边 + 图标）。
        OutlinedButton.icon(
          onPressed: () => _resetToDefaults(provider),
          icon: const Icon(Icons.restore, size: 16),
          label: const Text('恢复出厂考勤状态'),
        ),
        const SizedBox(height: 20),
        const SettingsSectionTitle('与批评记录同步'),
        const SettingsHint(
          '登记考勤时，命中映射的状态会自动在"批评"里同步一条对应原因的记录'
          '（备注注明"考勤同步"）；反过来，在记录里选到这些原因也会自动登记考勤。'
          '撤销考勤或删除该记录时，另一边会同步删除。点每个状态右侧的 ⇄ 可修改映射，'
          '留空表示不生成批评记录（如"请假"通常不需要批评）。',
        ),
        if (!settings.criticismEnabled)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SettingsHint(
              '当前“批评”记录类型已停用：登记考勤不会再新生成批评记录；'
              '已经同步生成的记录仍会随考勤修改或撤销一起更新。'
              '重新启用“批评”后恢复生成。',
            ),
          ),
      ],
    );
  }
}

/// 窗口设置：关闭窗口行为 + 启动时窗口状态。
