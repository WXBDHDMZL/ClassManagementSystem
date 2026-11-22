// 窗口尺寸工具测试：最小尺寸按名单推算 + 夹取（保证学生姓名完整显示）。
// 注意：window_manager 插件会截走 WM_GETMINMAXINFO（原生 SetMinimumSize 不生效），
// 因此最小尺寸由 DesktopService.minimumWindowSize + clampToMinimum 兜底。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/desktop_service.dart';
import 'package:class_management_system/utils/grid_layout.dart';

import 'test_helpers.dart';

void main() {
  // 测量文本需要 Flutter 绑定（TextPainter）。
  TestWidgetsFlutterBinding.ensureInitialized();

  test('下限即 1080x680（保证学生网格与记录面板完整显示）', () {
    expect(kMinWindowFloor, const Size(1080, 680));
    // 未按名单更新过时，最少也是这个下限。
    expect(DesktopService.instance.minimumWindowSize, kMinWindowFloor);
  });

  test('小于最小尺寸时被夹到最小尺寸', () {
    final service = DesktopService.instance;
    expect(
      service.clampToMinimum(const Size(600, 400)),
      service.minimumWindowSize,
    );
    expect(
      service.clampToMinimum(const Size(1080, 500)),
      const Size(1080, 680),
    );
    expect(
      service.clampToMinimum(const Size(700, 900)),
      const Size(1080, 900),
    );
  });

  test('不小于最小尺寸时保持原样', () {
    final service = DesktopService.instance;
    expect(service.clampToMinimum(const Size(1280, 720)), const Size(1280, 720));
    expect(
      service.clampToMinimum(const Size(1920, 1080)),
      const Size(1920, 1080),
    );
  });

  test('名单越多 / 姓名越长，推算出的最小窗口越大', () {
    final small = computeMinimumWindowSize(
      students: const ['张三', '李四', '王五', '赵六'],
    );
    final many = computeMinimumWindowSize(
      students: const ['张三', '李四', '王五', '赵六', '钱七', '孙八'],
    );
    // 都不低于下限。
    expect(small.width >= kMinWindowFloor.width, isTrue);
    expect(small.height >= kMinWindowFloor.height, isTrue);
    // 名单变多时面积不会变小（至少持平）。
    expect(
      many.width * many.height,
      greaterThanOrEqualTo(small.width * small.height),
    );
  });

  test('超长姓名会抬高最小窗口（同样人数下比短姓名更宽）', () {
    // 人数足够多，使"姓名宽度"成为约束（否则会被下限 1080 淹没）。
    final shortNames = List<String>.filled(30, '张三');
    final longNames = List<String>.filled(30, '张三丰爱新觉罗家族传人');
    final short = computeMinimumWindowSize(students: shortNames);
    final long = computeMinimumWindowSize(students: longNames);
    expect(long.width * long.height, greaterThan(short.width * short.height));
  });

  test('身份证长度级别的极端姓名也不会超过上限', () {
    final huge = computeMinimumWindowSize(
      students: List<String>.filled(4, '一二三四五六七八九十一二三四五六七八九十'),
    );
    expect(huge.width, lessThanOrEqualTo(kMinWindowCeiling.width));
    expect(huge.height, lessThanOrEqualTo(kMinWindowCeiling.height));
  });

  test('空名单回退到下限', () {
    expect(
      computeMinimumWindowSize(students: const []),
      kMinWindowFloor,
    );
  });

  test('选列数时把"无需滚动（单元高度≥44）"当硬约束', () {
    // 区域够高时应返回 fits=true，且单元高度不低于触控下限。
    final layout = selectStudentGrid(
      studentCount: 55,
      availableWidth: 700,
      availableHeight: 536,
    );
    expect(layout.fits, isTrue);
    expect(layout.cellHeight, greaterThanOrEqualTo(kMinTouchTarget));
  });

  test('推算出的最小窗口处，网格必须无需滚动（fits=true）', () {
    final students = syntheticStudents(55);
    final size = computeMinimumWindowSize(students: students);
    final area = gridAvailableArea(size);
    final layout = selectStudentGrid(
      studentCount: students.length,
      availableWidth: area.width,
      availableHeight: area.height,
    );
    expect(layout.fits, isTrue,
        reason: '最小窗口下若需要滚动，就与"铺满不滚动"的要求冲突');
    expect(layout.cellHeight, greaterThanOrEqualTo(kMinTouchTarget - 0.01));
  });

  test('关闭学生搜索后，最小窗口不再预留搜索框高度', () {
    expect(
      gridAvailableArea(const Size(1200, 800), searchEnabled: false).height -
          gridAvailableArea(const Size(1200, 800)).height,
      kStudentSearchChromeHeight,
    );

    // 30 人时最小高度刚好越过 680 下限，能直接看出搜索框占用的差异。
    final students = List<String>.generate(30, (index) => '学生${index + 1}');
    final withSearch = computeMinimumWindowSize(
      students: students,
      extraCells: const ['批量'],
    );
    final withoutSearch = computeMinimumWindowSize(
      students: students,
      extraCells: const ['批量'],
      searchEnabled: false,
    );
    expect(withoutSearch.height, lessThan(withSearch.height));

    final area = gridAvailableArea(withoutSearch, searchEnabled: false);
    final layout = selectStudentGrid(
      studentCount: students.length + 1,
      availableWidth: area.width,
      availableHeight: area.height,
    );
    expect(layout.fits, isTrue, reason: '关闭搜索后的最小窗口仍应无需滚动');
  });

  test('批量入口占用一格：最小窗口按多一格核算且无需滚动', () {
    final students = syntheticStudents(55);
    final without = computeMinimumWindowSize(students: students);
    final withBatch = computeMinimumWindowSize(
      students: students,
      extraCells: const ['批量'],
    );
    expect(
      withBatch.width * withBatch.height,
      greaterThanOrEqualTo(without.width * without.height),
    );
    final area = gridAvailableArea(withBatch);
    final layout = selectStudentGrid(
      studentCount: students.length + 1,
      availableWidth: area.width,
      availableHeight: area.height,
    );
    expect(layout.fits, isTrue, reason: '含批量入口的最小窗口不应需要滚动');
  });

}
