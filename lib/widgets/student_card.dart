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

import 'package:flutter/material.dart';

import '../constants/app_theme.dart';

/// 学生姓名卡片：网格中的单个学生入口，选中态高亮，点击触发记录对话框。
/// 卡片随网格单元尺寸自适应，姓名字号由外部按卡片高度计算传入。
/// 今日角标（V2.30.0）：左上角绿色=今日表扬数，右上角红色=今日批评数，
/// 像手机 App 的角标一样**绝对定位在卡片角上，不改变卡片与名字框的尺寸**。
class StudentCard extends StatelessWidget {
  final String name;
  final bool isSelected;
  final VoidCallback onTap;
  final double fontSize;

  /// 今日表扬次数（左上角绿色角标；0 不显示）。
  final int todayPraise;

  /// 今日批评次数（右上角红色角标；0 不显示）。
  final int todayCriticism;

  const StudentCard({
    super.key,
    required this.name,
    required this.isSelected,
    required this.onTap,
    this.fontSize = 14,
    this.todayPraise = 0,
    this.todayCriticism = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.25)
              : theme.colorScheme.surfaceContainer,
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: AppRadius.card,
        ),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                // 姓名**任何情况下都必须完整显示**：不省略号、不换行。
                // 正常情况下由"按名单推算的最小窗口尺寸"保证放得下；
                // 万一窗口被放到极窄（或屏幕本身很小），这里再缩放兜底，
                // 保证用户永远看得到完整姓名，而不是"张…"。
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    name,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ),
            ),
            // 今日角标（V2.30.0）：左绿=今日表扬，右红=今日批评；
            // 绝对定位、不占布局空间，因此**不会改变名字展示框的大小**。
            if (todayPraise > 0)
              Positioned(
                top: 2,
                left: 3,
                child: _todayBadge('$todayPraise', theme.semantic.praise, theme),
              ),
            if (todayCriticism > 0)
              Positioned(
                top: 2,
                right: 3,
                child: _todayBadge('$todayCriticism', theme.semantic.criticize, theme),
              ),
          ],
        ),
      ),
    );
  }

  /// 今日角标样式：圆角胶囊 + 白描边，字号随卡片字号缩放。
  Widget _todayBadge(String text, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      constraints: const BoxConstraints(minWidth: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.field,
        // 修复（一致性）：描边与文字改用语义前景色 —— 此前写死白色，
        // 浅色主题下白描边几乎看不见、深色主题下也不是同一套视觉。
        border: Border.all(color: theme.semantic.onSemantic, width: 1),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: theme.semantic.onSemantic,
          fontSize: (fontSize * 0.45).clamp(10.0, 15.0),
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
      ),
    );
  }
}
