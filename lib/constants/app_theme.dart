/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 统一配色方案与主题入口。
 * 所有主题色、语义色在此集中管理，供各 Widget 引用，避免硬编码。
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';

/// 统一圆角：卡片、对话框、面板一律使用 [card]，避免散落的魔法数字。
class AppRadius {
  const AppRadius._();

  /// 圆角档位（V2.30.7 统一）：此前界面上散落 10 种不同数值
  ///（2/3/6/7/8/9/10/12/16/20/999），同一类元素在不同对话框里圆角不同。
  /// 现在收敛为五档，新代码一律从这里取。
  /// - [small]：细装饰（进度条、窄色块）
  /// - [field]：输入框、小标签、内部小块
  /// - [card]：卡片、面板、对话框（默认档）
  /// - [sheet]：大面板、容器
  /// - [pill]：胶囊（圆形按钮、圆形徽标）
  static const double smallValue = 6;
  static const double fieldValue = 10;
  static const double cardValue = 12;
  static const double sheetValue = 16;
  static const double pillValue = 999;

  static const BorderRadius small = BorderRadius.all(Radius.circular(smallValue));
  static const BorderRadius field = BorderRadius.all(Radius.circular(fieldValue));
  static const BorderRadius card = BorderRadius.all(Radius.circular(cardValue));
  static const BorderRadius sheet = BorderRadius.all(Radius.circular(sheetValue));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(pillValue));
}

/// 弱化文字色：正文里的次级信息（提示、副标题、单位）统一用它。
/// 参数与原来各处的 `onSurface.withValues(alpha: x)` 完全一致。
Color mutedTextColor(ThemeData theme, [double alpha = 0.6]) =>
    theme.colorScheme.onSurface.withValues(alpha: alpha);

/// 危险操作的按钮样式（删除、清空、恢复出厂等）：统一红色实心按钮。
ButtonStyle dangerButtonStyle(ThemeData theme) => FilledButton.styleFrom(
      backgroundColor: theme.colorScheme.error,
      foregroundColor: theme.colorScheme.onError,
    );

/// 对话框宽度上限（逻辑像素）：屏幕宽度的 90%，且不超过该值。
///
/// 考勤/统计/日志三处对话框此前各写一遍、字面量还不一致（700/720），
/// 统一到这里（差异仅为视觉，取较小值 700）。
const double kDialogMaxWidth = 700;

/// 按屏幕宽度计算对话框宽度：宽度的 90% 封顶 [kDialogMaxWidth]。
double dialogWidthFor(Size screen) => screen.width * 0.9 > kDialogMaxWidth
    ? kDialogMaxWidth
    : screen.width * 0.9;

/// 固定尺寸对话框的安全宽度：不超过屏幕宽度的 92%（窗口拖小时不横向溢出，见 G-48）。
double clampDialogWidth(Size screen, double want) =>
    want > screen.width * 0.92 ? screen.width * 0.92 : want;

/// 固定尺寸对话框的安全高度：不超过屏幕高度的 90%（见 G-48）。
double clampDialogHeight(Size screen, double want) =>
    want > screen.height * 0.90 ? screen.height * 0.90 : want;

/// 原始色值常量：作为 [AppSemanticColors] 的构造来源，Widget 请勿直接引用。
class AppColors {
  const AppColors._();

  /// 品牌蓝（Material Blue 500）：主题种子色与浅色模式品牌渐变
  static const brandBlue = Color(0xFF2196F3);
  static const brandBlueLight = Color(0xFF42A5F5);

  /// 深色模式品牌渐变：略加深，与暗色背景协调并保证白色前景对比度
  static const brandBlueDeep = Color(0xFF1565C0);
  static const brandBlueMid = Color(0xFF1E88E5);

  /// 表扬（正向）——浅色用深绿，暗色用浅绿降低刺眼感
  static const praiseLight = Color(0xFF2E7D32);
  static const praiseDark = Color(0xFF81C784);

  /// 批评（负向）
  static const criticizeLight = Color(0xFFC62828);
  static const criticizeDark = Color(0xFFE57373);

  /// 追加/其他标签（警示）
  static const warningLight = Color(0xFFEF6C00);
  static const warningDark = Color(0xFFFFB74D);
}

/// 语义色集合：挂载于 [ThemeData.extensions]，亮色/暗色各一套。
/// Widget 统一通过 `theme.semantic` 获取，自动适配当前亮度，无需手动判断 brightness。
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.praise,
    required this.criticize,
    required this.warning,
    required this.onSemantic,
    required this.onBrand,
    required this.brandGradient,
    required this.subtleBorder,
  });

  /// 表扬色（正向操作）
  final Color praise;

  /// 批评色（负向操作）
  final Color criticize;

  /// 警示/追加色
  final Color warning;

  /// 表扬/批评/警示填充背景上的前景色（暗色模式用深色保证对比度）
  final Color onSemantic;

  /// 品牌渐变上的前景色
  final Color onBrand;

  /// 关于对话框品牌渐变
  final LinearGradient brandGradient;

  /// 轻边框色（统一替代 dividerColor 15% 透明度的写法）
  final Color subtleBorder;

  /// 浅色模式语义色
  static const light = AppSemanticColors(
    praise: AppColors.praiseLight,
    criticize: AppColors.criticizeLight,
    warning: AppColors.warningLight,
    onSemantic: Color(0xFFFFFFFF),
    onBrand: Color(0xFFFFFFFF),
    brandGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.brandBlue, AppColors.brandBlueLight],
    ),
    subtleBorder: Color(0x26000000),
  );

  /// 深色模式语义色
  static const dark = AppSemanticColors(
    praise: AppColors.praiseDark,
    criticize: AppColors.criticizeDark,
    warning: AppColors.warningDark,
    onSemantic: Color(0xFF121212),
    onBrand: Color(0xFFFFFFFF),
    brandGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.brandBlueDeep, AppColors.brandBlueMid],
    ),
    subtleBorder: Color(0x26FFFFFF),
  );

  @override
  AppSemanticColors copyWith({
    Color? praise,
    Color? criticize,
    Color? warning,
    Color? onSemantic,
    Color? onBrand,
    LinearGradient? brandGradient,
    Color? subtleBorder,
  }) {
    return AppSemanticColors(
      praise: praise ?? this.praise,
      criticize: criticize ?? this.criticize,
      warning: warning ?? this.warning,
      onSemantic: onSemantic ?? this.onSemantic,
      onBrand: onBrand ?? this.onBrand,
      brandGradient: brandGradient ?? this.brandGradient,
      subtleBorder: subtleBorder ?? this.subtleBorder,
    );
  }

  @override
  AppSemanticColors lerp(covariant AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      praise: Color.lerp(praise, other.praise, t)!,
      criticize: Color.lerp(criticize, other.criticize, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onSemantic: Color.lerp(onSemantic, other.onSemantic, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      brandGradient:
          LinearGradient.lerp(brandGradient, other.brandGradient, t)!,
      subtleBorder: Color.lerp(subtleBorder, other.subtleBorder, t)!,
    );
  }
}

/// 便捷访问：`theme.semantic` 获取当前语义色集合。
extension AppSemanticTheme on ThemeData {
  /// 修复（审计 P2-74）：扩展缺失时按主题亮度回退 —— 此前 `!` 强解包，
  /// 任何未挂扩展的 ThemeData（局部自建主题、第三方组件测试等）一访问就崩。
  AppSemanticColors get semantic =>
      extension<AppSemanticColors>() ??
      (brightness == Brightness.dark
          ? AppSemanticColors.dark
          : AppSemanticColors.light);
}

/// 统一主题定义：亮色 / 暗色。
/// 项目内所有 MaterialApp 均引用此入口，保证配色单一来源。
class AppTheme {
  const AppTheme._();

  static ThemeData light() => ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: AppColors.brandBlue,
        useMaterial3: true,
        extensions: const [AppSemanticColors.light],
      );

  static ThemeData dark() => ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: AppColors.brandBlue,
        useMaterial3: true,
        extensions: const [AppSemanticColors.dark],
      );
}
