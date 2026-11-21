/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

/// 设置页小节标题（各子页面共用，保证风格一致）。
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// 设置页说明文字（灰色小字）。
class SettingsHint extends StatelessWidget {
  const SettingsHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: mutedTextColor(theme, 0.65),
        height: 1.5,
      ),
    );
  }
}

/// 设置项选项按钮：选中态用主题色填充。
class SettingsChoiceButton extends StatelessWidget {
  const SettingsChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            selected ? theme.colorScheme.primary : theme.colorScheme.surface,
        foregroundColor:
            selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: Text(label),
    );
  }
}

/// 设置页主操作按钮（主题色填充）。
class SettingsActionButton extends StatelessWidget {
  const SettingsActionButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      ),
      child: Text(label),
    );
  }
}

/// 拖动只预览、松手才提交的滑块（修复 审查四 G-38）：
/// 此前各 slider 的 onChanged 逐 tick 写 provider，一次拖动触发几十次
/// 全库写盘与全界面重建；现在 onChanged 只更新本地预览，onChangeEnd 才提交一次。
class CommitSlider extends StatefulWidget {
  const CommitSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labelBuilder,
    required this.onCommit,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double value) labelBuilder;
  final ValueChanged<double> onCommit;

  @override
  State<CommitSlider> createState() => _CommitSliderState();
}

class _CommitSliderState extends State<CommitSlider> {
  late double _preview = widget.value;

  @override
  void didUpdateWidget(covariant CommitSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 修复（复查 #3）：外部改值时（provider 通知重建）同步本地预览，
    // 否则滑块会一直显示旧值。
    if (widget.value != oldWidget.value) _preview = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: _preview,
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      label: widget.labelBuilder(_preview),
      onChanged: (v) => setState(() => _preview = v),
      onChangeEnd: (v) => widget.onCommit(v),
    );
  }
}
