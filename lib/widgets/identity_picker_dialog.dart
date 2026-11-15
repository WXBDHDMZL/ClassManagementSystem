/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.8
 * 创建日期 (Created): 2026-10-17
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_theme.dart';
import '../models/identity.dart';
import '../providers/app_data_provider.dart';
import 'password_action_guard.dart';

/// 打开操作身份选择框；功能未启用时不做任何事。
Future<void> showIdentityPicker(BuildContext context) async {
  final provider = Provider.of<AppDataProvider>(context, listen: false);
  if (!provider.identityFeatureEnabled) return;
  await showDialog<void>(
    context: context,
    builder: (_) => const IdentityPickerDialog(),
  );
}

/// 记录/考勤对话框顶部：当前身份 + 更换入口；无身份时明确提示。
class IdentityBanner extends StatelessWidget {
  const IdentityBanner({
    super.key,
    required this.identity,
    required this.isEditing,
    required this.originalRecordedBy,
  });

  final Identity? identity;
  final bool isEditing;
  final String originalRecordedBy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final none = identity == null;
    final foreground =
        none ? theme.colorScheme.error : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: none
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.35)
            : theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                none
                    ? Icons.person_off_outlined
                    : Icons.person_pin_circle_outlined,
                size: 18,
                color: foreground,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  none
                      ? '请选择本次记录人'
                      : '${isEditing ? '本次操作人' : '记录人'}：${identity!.displayLabel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => showIdentityPicker(context),
                child: Text(none ? '选择' : '更换'),
              ),
            ],
          ),
          if (isEditing && originalRecordedBy.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Text(
                '原记录人：$originalRecordedBy',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: mutedTextColor(theme, 0.65),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 当前记录人选择：老师/学生分组。
/// 新身份模型下记录人只做署名，班主任也不需要密码；
/// 旧模型下仍保留班主任身份密码。
class IdentityPickerDialog extends StatelessWidget {
  const IdentityPickerDialog({super.key});

  Future<void> _select(
    BuildContext context,
    AppDataProvider provider,
    Identity identity,
  ) async {
    if (identity.isHeadTeacher) {
      // 班主任身份带管理权限，必须先验证管理密码。
      final verified = await ensureManagementMode(
        context,
        provider,
        message: '切换到班主任操作身份需要验证管理密码。',
      );
      if (!verified || !context.mounted) return;
      Navigator.pop(context);
      return;
    }
    provider.setActiveIdentity(identity.id);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final identities = provider.appData.settings.identities;
    final teachers =
        identities.where((e) => e.kind == IdentityKind.teacher).toList();
    final students =
        identities.where((e) => e.kind == IdentityKind.student).toList();
    final activeId = provider.activeIdentity?.id;
    final muted = mutedTextColor(theme, 0.62);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.58;

    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      title: const Text('选择操作身份'),
      content: SizedBox(
        width: 400,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                '请选择本次操作使用的操作身份。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              if (teachers.isNotEmpty)
                _section(context, theme, provider, '老师', teachers, activeId),
              if (students.isNotEmpty)
                _section(context, theme, provider, '学生', students, activeId),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: provider.activeIdentity == null
                      ? null
                      : () {
                          provider.clearActiveIdentity();
                          Navigator.pop(context);
                        },
                  icon: const Icon(Icons.person_off_outlined, size: 18),
                  label: const Text('退出当前身份'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _section(
    BuildContext context,
    ThemeData theme,
    AppDataProvider provider,
    String title,
    List<Identity> identities,
    String? activeId,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: mutedTextColor(theme, 0.55),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final identity in identities)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
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
            title: Text(identity.displayLabel),
            subtitle: Text(identity.kindLabel),
            trailing: activeId == identity.id
                ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                : null,
            onTap: () => _select(context, provider, identity),
          ),
      ],
    );
  }
}
