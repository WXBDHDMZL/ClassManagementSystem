import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/widgets/terms_of_service.dart';

void main() {
  test('LICENSE 与安装器副本都是完整 AGPL-3.0-only 文本', () {
    final root = File('LICENSE.txt');
    final installer = File('installer/LICENSE.txt');

    expect(root.existsSync(), isTrue);
    expect(installer.existsSync(), isTrue);

    final text = root.readAsStringSync();
    expect(text, contains('SPDX-License-Identifier: AGPL-3.0-only'));
    expect(text, contains('GNU AFFERO GENERAL PUBLIC LICENSE'));
    expect(text, contains('Version 3, 19 November 2007'));
    expect(text, isNot(contains('All rights reserved')));
    expect(text, isNot(contains('未经作者书面许可')));
    // 安装器在安装向导里展示的是同一份许可证，避免两处文本漂移。
    expect(installer.readAsStringSync(), text);
  });

  testWidgets('开源许可对话框说明 AGPL、商业使用与源码获取方式', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TermsOfServiceDialog())),
    );

    expect(find.text('开源许可与使用说明'), findsOneWidget);
    expect(find.text('我已了解'), findsOneWidget);

    bool hasText(String needle) => tester
        .widgetList<RichText>(find.byType(RichText))
        .any((rich) => rich.text.toPlainText().contains(needle));

    expect(hasText('AGPL-3.0-only'), isTrue);
    expect(hasText('商业使用也是允许的'), isTrue);
    expect(hasText('WXBDHDMZL@outlook.com'), isTrue);
    expect(hasText('如果你分发修改后的程序'), isTrue);
  });
}
