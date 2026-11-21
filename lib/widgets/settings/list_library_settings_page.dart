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
part of '../settings_pages.dart';

/// 名单库设置页。
class ListLibrarySettingsPage extends StatelessWidget {
  const ListLibrarySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppDataProvider>(context);
    final library = provider.appData.reasons;
    var reasonCount = 0;
    // 用当前生效时段（含自定义新增），避免漏计。
    final reasonPeriods = [
      ...effectivePeriods().map((item) => item['key']!),
      '_common',
    ];
    for (final type in const ['表扬', '批评']) {
      for (final period in reasonPeriods) {
        reasonCount += library.forPeriod(type, period).length;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('学生名单'),
        SettingsHint(
          '当前 ${provider.appData.students.length} 名学生，可增删改与拖动排序；改名会同步更新历史记录。',
        ),
        const SizedBox(height: 10),
        SettingsActionButton(
          label: '打开名单管理',
          onPressed: () async {
            final verified = await ensurePasswordForAction(
              context,
              provider,
              PasswordAction.rosterModify,
              message: '修改学生名单前请先进入班主任管理。',
            );
            if (!verified || !context.mounted) return;
            await showDialog<void>(
              context: context,
              builder: (context) => const StudentManageDialog(),
            );
          },
        ),
        const SizedBox(height: 20),
        const SettingsSectionTitle('表扬 / 批评原因库'),
        SettingsHint('当前约 $reasonCount 条原因，按时段分组维护，支持自定义与拖动排序。'),
        const SizedBox(height: 10),
        SettingsActionButton(
          label: '打开原因管理',
          onPressed: () async {
            final verified = await ensurePasswordForAction(
              context,
              provider,
              PasswordAction.reasonModify,
              message: '修改原因库前请先进入班主任管理。',
            );
            if (!verified || !context.mounted) return;
            await showDialog<void>(
              context: context,
              builder: (context) => const ReasonManageDialog(),
            );
          },
        ),
        const SizedBox(height: 16),
        const SettingsHint('提示：名单与原因库的修改需要进入班主任管理。'),
      ],
    );
  }
}
