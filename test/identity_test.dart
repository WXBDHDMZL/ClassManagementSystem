/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V2.34.2
 * 创建日期 (Created): 2026-10-17
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/identity.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/widgets/record_dialog.dart';

void main() {
  test('身份模型：显示名、班主任与 JSON 往返', () {
    const identity = Identity(
      id: 'discipline_committee',
      name: '纪律委员',
      nickname: '李四',
      kind: IdentityKind.student,
    );
    expect(identity.displayLabel, '纪律委员 · 李四');
    expect(identity.kindLabel, '学生');
    final restored = Identity.fromJson(identity.toJson());
    expect(restored, identity);
    expect(Identity.defaultHeadTeacher.isHeadTeacher, isTrue);
  });

  test('身份设置默认关闭，序列化后保留开关、列表、超时与班主任昵称', () {
    final defaults = AppSettings(themeMode: ThemeModeType.system);
    expect(defaults.identityFeatureEnabled, isFalse);
    expect(
      defaults.identityIdleMinutes,
      AppSettings.defaultIdentityIdleMinutes,
    );
    expect(defaults.identities.first.isHeadTeacher, isTrue);

    final settings = defaults.copyWith(
      identityFeatureEnabled: true,
      identityIdleMinutes: 10,
      identities: [
        defaults.identities.first.copyWith(nickname: '王老师'),
        const Identity(
          id: 'custom_discipline',
          name: '纪律委员',
          nickname: '李四',
          kind: IdentityKind.student,
        ),
      ],
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.identityFeatureEnabled, isTrue);
    expect(restored.identityIdleMinutes, 10);
    expect(restored.identities.first.displayLabel, '班主任 · 王老师');
    expect(restored.identities.any((e) => e.name == '纪律委员'), isTrue);
  });

  test('启用身份后新增记录写入记录人，关闭后不再写入', () {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);

    expect(provider.activeIdentity, isNull);
    provider.setIdentityFeatureEnabled(true);
    expect(provider.activeIdentity, isNull);
    provider.setActiveIdentity('discipline_committee');
    expect(provider.activeIdentity?.name, '纪律委员');

    provider.addRecord('张三', '表扬', const ['认真听讲'], 'class', '');
    expect(provider.getTodayRecords().single.recordedBy, '纪律委员');

    provider.setIdentityFeatureEnabled(false);
    expect(provider.activeIdentity, isNull);
    provider.addRecord('李四', '批评', const ['迟到'], 'class', '');
    final li = provider.getTodayRecords().firstWhere(
      (record) => record.studentName == '李四',
    );
    expect(li.recordedBy, isEmpty);
  });

  test('记录人写入 JSON 并可还原', () {
    final record = StudentRecord(
      id: 'r1',
      studentName: '张三',
      operationType: '表扬',
      reasons: '认真听讲',
      periodKey: 'class',
      periodName: '课堂',
      remark: '',
      timestamp: '10:00:00',
      date: '2026-10-17',
      recordedBy: '班长 · 王五',
    );
    final restored = StudentRecord.fromJson(record.toJson());
    expect(restored.recordedBy, '班长 · 王五');
    expect(restored, record);
  });

  test('导出列包含记录人标题', () {
    expect(AppSettings.recordExportColumnTitles['recordedBy'], '记录人');
  });

  test('恢复出厂会清除当前身份', () async {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.setIdentityFeatureEnabled(true);
    provider.setActiveIdentity('discipline_committee');

    await provider.factoryReset();

    expect(provider.identityFeatureEnabled, isFalse);
    expect(provider.activeIdentity, isNull);
  });

  testWidgets('操作身份闲置到点自动退出（含班主任）', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.setIdentityFeatureEnabled(true);

    provider.setActiveIdentity('discipline_committee');
    await tester.pump(const Duration(minutes: 5));
    expect(provider.activeIdentity, isNull);

    provider.setActiveIdentity('head_teacher');
    await tester.pump(const Duration(minutes: 5));
    expect(provider.activeIdentity, isNull);
  });

  testWidgets('基础时长内的早期触摸不会延长或重新计时', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.setIdentityFeatureEnabled(true);

    provider.setActiveIdentity('discipline_committee');
    await tester.pump(const Duration(minutes: 2));
    provider.touchIdentityActivity();
    await tester.pump(const Duration(minutes: 3));
    expect(provider.activeIdentity, isNull);
  });

  testWidgets('最后 1 分钟内的触摸把退出时间顺延 1 分钟', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.setIdentityFeatureEnabled(true);

    provider.setActiveIdentity('discipline_committee');
    await tester.pump(const Duration(minutes: 4, seconds: 30));
    provider.touchIdentityActivity();

    // 5:00 基础时限到点，但 4:30 有触摸，等它之后 1 分钟再退出。
    await tester.pump(const Duration(seconds: 30));
    expect(provider.activeIdentity, isNotNull);
    await tester.pump(const Duration(seconds: 29));
    expect(provider.activeIdentity, isNotNull);
    await tester.pump(const Duration(seconds: 1));
    expect(provider.activeIdentity, isNull);
  });

  testWidgets('等待退出期间每次触摸都会重新开始 1 分钟倒计时', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.setIdentityFeatureEnabled(true);

    provider.setActiveIdentity('discipline_committee');
    await tester.pump(const Duration(minutes: 4, seconds: 30));
    provider.touchIdentityActivity();
    await tester.pump(const Duration(seconds: 30));
    provider.touchIdentityActivity();
    await tester.pump(const Duration(seconds: 59));
    expect(provider.activeIdentity, isNotNull);
    provider.touchIdentityActivity();
    await tester.pump(const Duration(seconds: 59));
    expect(provider.activeIdentity, isNotNull);
    await tester.pump(const Duration(seconds: 1));
    expect(provider.activeIdentity, isNull);
  });

  testWidgets('启用身份后记录对话框提示先选择操作身份', (tester) async {
    final provider = AppDataProvider();
    provider.setIdentityFeatureEnabled(true);
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppDataProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: RecordDialog(studentName: '张三')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('请选择本次记录人'), findsOneWidget);
  });
}
