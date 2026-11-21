/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.13.0
 * 创建日期 (Created): 2026-10-04
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

/// 学生网格布局与"最小窗口尺寸"的**唯一实现**（主界面与窗口服务共用）。
///
/// 需求：学生姓名**任何情况下都要显示完全**，且最小窗口尺寸按名单人数自动推算。
/// 本文件负责两件事：
///  1. [selectStudentGrid]：枚举列数，在"无需滚动"的前提下取宽高比最接近 2.5:1 的布局；
///  2. [computeMinimumWindowSize]：反推"姓名能完整显示"所需的最小窗口尺寸。
///
/// 说明：这里的骨架占用是**保守估计**；即便估偏，姓名也不会被截断——卡片里的姓名
/// 另有 `FittedBox(scaleDown)` 兜底（超长姓名会缩到刚好放下，而不是显示省略号）。
library;

import 'package:flutter/painting.dart';

/// 右侧"今日记录"面板宽度（与 main.dart 的布局保持一致）。
const double kRightPanelWidth = 360;

/// 网格外层 Container 与内层 Padding 的留白（main.dart）与卡片间距。
const double kGridOuterPadding = 16;
const double kGridInnerPadding = 16;
const double kGridSpacing = 8;

/// 网格两侧合计留白。
const double kGridHorizontalChrome = (kGridOuterPadding + kGridInnerPadding) * 2;

/// 表头（含保存失败横幅等）的保守高度估计。
const double kHeaderChromeHeight = 80;

/// 主页学生搜索框及其下间距的保守高度（main.dart）。
const double kStudentSearchChromeHeight = 54;

/// 主页底部版权栏的高度（含内边距与分隔线）。
const double kBottomBarChromeHeight = 33;

/// 卡片字号：相对短边的系数与上下限（与 main.dart 的常量一致）。
const double kCardFontScaleFactor = 0.4;
const double kCardFontMin = 12;
const double kCardFontMax = 40;

/// 触控点按区下限（逻辑像素）。
const double kMinTouchTarget = 44;

/// 卡片内姓名的左右留白 + 边框（姓名可用宽度 = 单元宽 - 它）。
const double kCardNamePadding = 12;

/// 最小窗口尺寸的下限（名单很少时也不小于它；也保证各弹窗放得下）。
const Size kMinWindowFloor = Size(1080, 680);

/// 最小窗口尺寸的上限：再大的名单也不会要求超过它（超出的部分由卡片内缩放兜底）。
const Size kMinWindowCeiling = Size(1920, 1200);

/// 网格选择结果。
class StudentGridLayout {
  const StudentGridLayout({
    required this.columns,
    required this.cellWidth,
    required this.cellHeight,
    required this.fits,
  });

  final int columns;
  final double cellWidth;
  final double cellHeight;

  /// 该布局在给定区域内**无需滚动**即可完整放下（单元高度达到触控下限）。
  final bool fits;
}

/// 选择网格布局：在**满足触控高度下限（无需滚动）**的列数里，取宽高比最接近
/// 2.5:1 的一种。
///
/// 为什么把"无需滚动"当硬约束：此前只按比例选列数，选中的列可能让单元高度
/// 低于 44，于是被抬到 44 → 总高超出可用区域 → **最小窗口下出现滚动条**
/// （用户明确要求：任何情况下都应铺满、不滚动）。
/// 只有当所有列数都放不下（窗口极窄/极矮）时才退回"比例最优"并标记 `fits=false`，
/// 由调用方兜底允许滚动（避免裁掉卡片）。
StudentGridLayout selectStudentGrid({
  required int studentCount,
  required double availableWidth,
  required double availableHeight,
  double spacing = kGridSpacing,
  double minCellHeight = kMinTouchTarget,
}) {
  StudentGridLayout? fallback;
  var fallbackScore = double.infinity;
  StudentGridLayout? best;
  var bestScore = double.infinity;

  final maxColumns = 16;
  for (var columns = 2; columns <= maxColumns; columns++) {
    final rows = (studentCount / columns).ceil();
    final cellWidth = (availableWidth - (columns - 1) * spacing) / columns;
    final cellHeight = (availableHeight - (rows - 1) * spacing) / rows;
    if (cellWidth <= 0) continue;
    // 比例分数：越接近 2.5:1 越好。
    final score = (cellWidth / (cellHeight <= 0 ? 1 : cellHeight) - 2.5).abs();
    if (cellHeight >= minCellHeight) {
      // 放得下：优先在这里面挑。
      if (score < bestScore) {
        bestScore = score;
        best = StudentGridLayout(
          columns: columns,
          cellWidth: cellWidth,
          cellHeight: cellHeight,
          fits: true,
        );
      }
    } else if (score < fallbackScore) {
      // 放不下（该列数会导致单元过矮）：作为兜底候选。
      fallbackScore = score;
      fallback = StudentGridLayout(
        columns: columns,
        cellWidth: cellWidth,
        cellHeight: minCellHeight,
        fits: false,
      );
    }
  }
  return best ?? fallback ?? const StudentGridLayout(
    columns: 2,
    cellWidth: 0,
    cellHeight: kMinTouchTarget,
    fits: false,
  );
}

/// 卡片字号：按单元格短边计算（与主界面同一口径）。
double gridFontSize(double cellWidth, double cellHeight) {
  final shorter = cellWidth < cellHeight ? cellWidth : cellHeight;
  return (shorter * kCardFontScaleFactor)
      .clamp(kCardFontMin, kCardFontMax)
      .toDouble();
}

/// 测量一行文本的宽度（姓名不换行、加粗）。
double measureTextWidth(String text, double fontSize) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

/// 给定窗口尺寸下，学生网格的可用区域（扣除表头、内外留白与右侧面板）。
/// 供"最小窗口推算"与用例共用，保证两边口径一致。
///
/// [searchEnabled] 与主页是否渲染学生搜索框保持一致；关闭搜索时不能再扣
/// 搜索框占用的 54px，否则最小窗口会无谓地多出一截。
Size gridAvailableArea(Size window, {bool searchEnabled = true}) => Size(
      window.width - (kRightPanelWidth + kGridHorizontalChrome + 2),
      window.height -
          (kHeaderChromeHeight +
              (searchEnabled ? kStudentSearchChromeHeight : 0) +
              kBottomBarChromeHeight +
              kGridHorizontalChrome),
    );

/// 按名单推算**最小窗口尺寸**：保证每张卡片的姓名能完整显示。
///
/// 思路：先求"姓名放得下 + 触控下限"所需的单元格尺寸（不动点迭代：字号随单元
/// 变大而变大，需要收敛），再枚举列数、取最终窗口面积最小的一种，最后与
/// [kMinWindowFloor]（下限）和 [kMinWindowCeiling]（上限）取夹。
Size computeMinimumWindowSize({
  required List<String> students,
  List<String> extraCells = const [],
  bool searchEnabled = true,
}) {
  if (students.isEmpty) return kMinWindowFloor;
  // 主界面的“批量”入口等非学生单元格也占一格，宽度按其中的文字一起核算。
  final labels = <String>[...students, ...extraCells];
  final cellCount = labels.length;

  // ① 不动点迭代求所需单元格尺寸。
  var cellWidth = 64.0;
  var cellHeight = 64.0;
  for (var i = 0; i < 8; i++) {
    final font = gridFontSize(cellWidth, cellHeight);
    var neededWidth = kMinTouchTarget;
    for (final name in labels) {
      final width = measureTextWidth(name, font) + kCardNamePadding;
      if (width > neededWidth) neededWidth = width;
    }
    // 高度：字号行高 + 上下留白，且不低于触控下限。
    final neededHeight = font * 1.5 + 12;
    final targetHeight =
        neededHeight < kMinTouchTarget ? kMinTouchTarget : neededHeight;
    final nextWidth = neededWidth > cellWidth ? neededWidth : cellWidth;
    final nextHeight = targetHeight > cellHeight ? targetHeight : cellHeight;
    if (nextWidth == cellWidth && nextHeight == cellHeight) break;
    cellWidth = nextWidth;
    cellHeight = nextHeight;
  }

  // ② 枚举列数，取"通过自校验"的候选里窗口面积最小者。
  //    自校验 = 用**渲染时的同一函数**在该窗口尺寸下重算布局，确认
  //    （a）无需滚动、（b）每个姓名在该布局的字号下都放得下。
  //    这样"最小窗口"与"实际渲染"必然一致，不会再出现最小窗口下出滚动条。
  const chromeWidth = kRightPanelWidth + kGridHorizontalChrome + 2;
  final chromeHeight =
      kHeaderChromeHeight +
      (searchEnabled ? kStudentSearchChromeHeight : 0) +
      kGridHorizontalChrome;

  Size? best;
  var bestArea = double.infinity;
  Size? fallbackSize;
  var fallbackArea = double.infinity;
  final maxColumns = cellCount < 16 ? cellCount : 16;
  for (var columns = 2; columns <= maxColumns; columns++) {
    final rows = (cellCount / columns).ceil();
    final gridWidth = columns * cellWidth + (columns - 1) * kGridSpacing;
    final gridHeight = rows * cellHeight + (rows - 1) * kGridSpacing;
    final rawWidth = gridWidth + chromeWidth;
    final rawHeight = gridHeight + chromeHeight;
    final width = rawWidth < kMinWindowFloor.width ? kMinWindowFloor.width : rawWidth;
    final height =
        rawHeight < kMinWindowFloor.height ? kMinWindowFloor.height : rawHeight;
    final window = Size(width, height);
    final area = width * height;

    if (area < fallbackArea) {
      fallbackArea = area;
      fallbackSize = window;
    }

    final layout = selectStudentGrid(
      studentCount: cellCount,
      availableWidth: gridAvailableArea(
        window,
        searchEnabled: searchEnabled,
      ).width,
      availableHeight: gridAvailableArea(
        window,
        searchEnabled: searchEnabled,
      ).height,
    );
    if (!layout.fits) continue;
    final font = gridFontSize(layout.cellWidth, layout.cellHeight);
    var needed = kMinTouchTarget;
    for (final name in labels) {
      final nameWidth = measureTextWidth(name, font) + kCardNamePadding;
      if (nameWidth > needed) needed = nameWidth;
    }
    if (layout.cellWidth + 0.5 < needed) continue;
    if (area < bestArea) {
      bestArea = area;
      best = window;
    }
  }
  final result = best ?? fallbackSize ?? kMinWindowFloor;
  return Size(
    result.width > kMinWindowCeiling.width ? kMinWindowCeiling.width : result.width,
    result.height > kMinWindowCeiling.height
        ? kMinWindowCeiling.height
        : result.height,
  );
}
