// ReleaseNotes.forApp：只展示应用内需要的更新内容。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/utils/release_notes.dart';

void main() {
  test('优先使用显式标记区块', () {
    const notes = '''
# V5.0.0

<!-- app:start -->
## 主要变化

- 新增名单导入
<!-- app:end -->

## 发布资产

- setup.exe
''';

    final visible = ReleaseNotes.forApp(notes);

    expect(visible, contains('新增名单导入'));
    expect(visible, isNot(contains('发布资产')));
    expect(visible, isNot(contains('setup.exe')));
  });

  test('没有标记时只取主要变化一节', () {
    const notes = '''
# V5.0.0

本版包含一些兼容说明。

## 主要变化

- 新增名单导入
- 修复统计细节

## 升级说明

从旧版本升级前请先备份。
''';

    final visible = ReleaseNotes.forApp(notes);

    expect(visible, contains('新增名单导入'));
    expect(visible, contains('修复统计细节'));
    expect(visible, isNot(contains('升级说明')));
    expect(visible, isNot(contains('兼容说明')));
  });

  test('没有可用标题时退回全文', () {
    const notes = '- 新增名单导入\n- 修复统计细节';

    expect(ReleaseNotes.forApp(notes), notes);
  });

  test('支持其它常见更新标题', () {
    const notes = '''
# V5.0.0

## 新功能

- 优化表格导入

## 已知问题

- 暂无
''';

    final visible = ReleaseNotes.forApp(notes);

    expect(visible, contains('优化表格导入'));
    expect(visible, isNot(contains('已知问题')));
  });

  test('空正文返回空字符串', () {
    expect(ReleaseNotes.forApp(''), isEmpty);
    expect(ReleaseNotes.forApp('   '), isEmpty);
  });
}
