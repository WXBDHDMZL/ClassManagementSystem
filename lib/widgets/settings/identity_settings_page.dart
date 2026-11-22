/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.0
 * 创建日期 (Created): 2026-10-17
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../settings_pages.dart';

/// 操作身份设置页：功能开关、身份列表、闲置退出。
class IdentitySettingsPage extends StatelessWidget {
  const IdentitySettingsPage({super.key});

  Future<void> _editIdentity(
    BuildContext context,
    AppDataProvider provider, {
    Identity? identity,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _IdentityEditDialog(identity: identity),
    );
    if (changed == true && context.mounted) {
      showTopSnackBar(context, identity == null ? '已新增身份' : '已保存身份');
    }
  }

  Future<void> _deleteIdentity(
    BuildContext context,
    AppDataProvider provider,
    Identity identity,
  ) async {
    if (identity.isHeadTeacher) return;
    final confirmed = await confirmDestructive(
      context,
      title: '删除身份',
      message: '将删除「${identity.displayLabel}」。\n'
          '已有记录中的记录人不会改变；如果它正好是当前身份，会回到“未选择身份”。\n\n'
          '删除后需要时可以重新添加。',
      confirmLabel: '删除身份',
    );
    if (!confirmed || !context.mounted) return;
    if (provider.deleteIdentity(identity.id)) {
      showTopSnackBar(context, '已删除身份');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final settings = provider.appData.settings;
    final muted = mutedTextColor(theme, 0.65);
    final activeId = provider.activeIdentity?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('操作身份'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.identityFeatureEnabled,
          onChanged: provider.setIdentityFeatureEnabled,
          title: Text('启用操作身份', style: theme.textTheme.bodyMedium),
          subtitle: Text(
            '启用后，记录人只负责署名；'
            '修改他人记录、导入数据或调整设置时进入班主任管理。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              height: 1.4,
            ),
          ),
        ),
        if (settings.identityFeatureEnabled)
          const SettingsHint(
            '关闭此开关只会隐藏身份功能，不会清空身份列表和历史记录人。',
          ),
        const SizedBox(height: 20),
        const SettingsSectionTitle('班主任管理'),
        const SettingsHint(
          '修改他人记录、导入数据、调整设置等敏感操作统一由班主任管理保护。'
          '班主任管理输入一次管理密码即可，活动闲置超时后自动退出。',
        ),
        const SizedBox(height: 8),
        Text('保持时长', style: theme.textTheme.bodySmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minutes in AppSettings.managementSessionMinuteOptions)
              SettingsChoiceButton(
                label: '$minutes 分钟',
                selected: settings.managementSessionMinutes == minutes,
                onPressed: () =>
                    provider.setManagementSessionMinutes(minutes),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text('本人编辑窗口', style: theme.textTheme.bodySmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minutes in AppSettings.selfEditWindowMinuteOptions)
              SettingsChoiceButton(
                label: minutes == 0 ? '关闭' : '$minutes 分钟',
                selected: settings.selfEditWindowMinutes == minutes,
                onPressed: () => provider.setSelfEditWindowMinutes(minutes),
              ),
          ],
        ),
        const SizedBox(height: 4),
        SettingsHint(
          settings.selfEditWindowMinutes == 0
              ? '已关闭本人编辑窗口：所有修改/删除都需要班主任管理。'
              : '记录人在创建记录后的 ${settings.selfEditWindowMinutes} 分钟内'
                  '可以修改/删除自己的记录；超时或修改他人记录需要班主任管理。',
        ),
        const SizedBox(height: 20),
        const SettingsSectionTitle('身份列表'),
        const SettingsHint(
          '班主任固定保留、不可删除；其余老师/班干部身份可增删改。'
          '“昵称”可填学生姓名，记录时会显示为“纪律委员 · 李四”。',
        ),
        const SizedBox(height: 4),
        for (final identity in settings.identities)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: identity.isHeadTeacher
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : theme.colorScheme.surfaceContainerHigh,
              child: Icon(
                identity.isHeadTeacher
                    ? Icons.verified_user_outlined
                    : identity.kind == IdentityKind.teacher
                        ? Icons.school_outlined
                        : Icons.person_outline,
                size: 18,
                color: identity.isHeadTeacher
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
            title: Row(
              children: [
                Flexible(child: Text(identity.displayLabel)),
                if (activeId == identity.id) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '当前',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              identity.isHeadTeacher
                  ? '老师 · 班主任管理入口'
                  : '${identity.kindLabel}'
                      '${identity.allowSelfEdit ? ' · 可署名/本人窗口' : ' · 仅署名'}',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: '编辑',
                  onPressed: () => _editIdentity(
                    context,
                    provider,
                    identity: identity,
                  ),
                ),
                if (!identity.isHeadTeacher)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: '删除',
                    onPressed: () =>
                        _deleteIdentity(context, provider, identity),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _editIdentity(context, provider),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新增身份'),
          ),
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle('身份闲置退出'),
        SettingsHint(
          settings.identityIdleMinutes == 0
              ? '当前选择“不自动退出”：身份会一直保持，直到手动退出或关闭程序。'
              : '选择身份后先按设定时长计时，期间触摸不会让计时重新开始。'
                  '到最后 1 分钟内如有触摸/鼠标操作，退出时间顺延到该次操作之后 1 分钟；'
                  '之后每操作一次就再顺延 1 分钟，连续 1 分钟没有操作才退出。',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minutes in AppSettings.identityIdleMinuteOptions)
              SettingsChoiceButton(
                label: minutes == 0 ? '不自动退出' : '$minutes 分钟',
                selected: settings.identityIdleMinutes == minutes,
                onPressed: () => provider.setIdentityIdleMinutes(minutes),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const SizedBox(height: 20),
        const SettingsSectionTitle('说明'),
        const SettingsHint(
          '记录人只用于留痕署名，不是登录账号，程序无法防止冒用；'
          '敏感操作需要管理密码。'
          '班主任管理只保存在内存中，关闭程序、超时或手动退出即失效。',
        ),
      ],
    );
  }
}

/// 新增/编辑身份的对话框。
class _IdentityEditDialog extends StatefulWidget {
  const _IdentityEditDialog({this.identity});

  final Identity? identity;

  @override
  State<_IdentityEditDialog> createState() => _IdentityEditDialogState();
}

class _IdentityEditDialogState extends State<_IdentityEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _nicknameController;
  late IdentityKind _kind;
  late bool _allowSelfEdit;
  late bool _allowAddRecord;
  late bool _allowAttendanceRegister;

  bool get _editing => widget.identity != null;
  bool get _isHeadTeacher => widget.identity?.isHeadTeacher ?? false;

  @override
  void initState() {
    super.initState();
    final identity = widget.identity;
    _nameController = TextEditingController(text: identity?.name ?? '');
    _nicknameController =
        TextEditingController(text: identity?.nickname ?? '');
    _kind = identity?.kind ?? IdentityKind.student;
    _allowSelfEdit = identity?.allowSelfEdit ?? true;
    _allowAddRecord = identity?.allowAddRecord ?? true;
    _allowAttendanceRegister = identity?.allowAttendanceRegister ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  void _save() {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    final name = _isHeadTeacher
        ? widget.identity!.name
        : _nameController.text.trim();
    if (name.isEmpty) {
      showTopSnackBar(context, '身份名称不能为空', isError: true);
      return;
    }
    final ok = _editing
        ? provider.updateIdentity(
            widget.identity!.id,
            name: name,
            nickname: _nicknameController.text,
            kind: _kind,
            allowSelfEdit: _allowSelfEdit,
            allowAddRecord: _allowAddRecord,
            allowAttendanceRegister: _allowAttendanceRegister,
          )
        : provider.addIdentity(
              name: name,
              nickname: _nicknameController.text,
              kind: _kind,
              allowSelfEdit: _allowSelfEdit,
              allowAddRecord: _allowAddRecord,
              allowAttendanceRegister: _allowAttendanceRegister,
            ) !=
            null;
    if (!ok) {
      showTopSnackBar(context, '保存身份失败，请检查名称', isError: true);
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      title: Text(_editing ? '编辑身份' : '新增身份'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              enabled: !_isHeadTeacher,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: '身份名称',
                hintText: '如：纪律委员、值日生',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nicknameController,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: '昵称 / 姓名（可选）',
                hintText: '如：李四；记录时显示为“纪律委员 · 李四”',
              ),
            ),
            const SizedBox(height: 8),
            Text('类别', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            SegmentedButton<IdentityKind>(
              segments: const [
                ButtonSegment(
                  value: IdentityKind.teacher,
                  label: Text('老师'),
                  icon: Icon(Icons.school_outlined, size: 18),
                ),
                ButtonSegment(
                  value: IdentityKind.student,
                  label: Text('学生'),
                  icon: Icon(Icons.person_outline, size: 18),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: _isHeadTeacher
                  ? null
                  : (selection) => setState(() => _kind = selection.first),
            ),
            if (!_isHeadTeacher) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowAddRecord,
                onChanged: (value) =>
                    setState(() => _allowAddRecord = value),
                title: Text('允许新增记录', style: theme.textTheme.bodyMedium),
                subtitle: Text(
                  _allowAddRecord ? '普通模式可直接新增记录。' : '该身份只能查看/署名，不能新增记录。',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (AttendanceFeature.enabled)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _allowAttendanceRegister,
                  onChanged: (value) =>
                      setState(() => _allowAttendanceRegister = value),
                  title: Text('允许考勤登记', style: theme.textTheme.bodyMedium),
                  subtitle: Text(
                    _allowAttendanceRegister
                        ? '普通模式可登记/修改考勤。'
                        : '考勤登记需要班主任管理。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowSelfEdit,
                onChanged: (value) => setState(() => _allowSelfEdit = value),
                title: Text('允许本人编辑窗口', style: theme.textTheme.bodyMedium),
                subtitle: Text(
                  _allowSelfEdit
                      ? '该身份可在窗口内改删自己创建的记录。'
                      : '该身份只署名，不能在本人窗口内改删记录。',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
            if (_isHeadTeacher)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '班主任身份固定保留，只能修改昵称。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedTextColor(theme, 0.65),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
