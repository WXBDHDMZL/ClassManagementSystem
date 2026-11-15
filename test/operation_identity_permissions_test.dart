// A+C 第一阶段的回归测试：管理员模式 + 记录所有权窗口。
//
// 默认关闭管理模式的旧行为不能被改变；只有显式开启后才生效。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/auth_service.dart';

void main() {
  late AppDataProvider provider;

  setUp(() {
    AuthService.resetForTest();
    provider = AppDataProvider();
    provider.setPasswordEnabled(true);
    provider.setIdentityFeatureEnabled(true);
    provider.setActiveIdentity('discipline_committee');
  });

  tearDown(() {
    provider.dispose();
    AuthService.resetForTest();
  });

  test('管理设置可序列化并保持', () {
    final settings = AppSettings.defaultSettings().copyWith(
      managementSessionMinutes: 30,
      selfEditWindowMinutes: 5,
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.managementSessionMinutes, 30);
    expect(restored.selfEditWindowMinutes, 5);
  });

  test('V3 起管理员模式固定启用，旧的“模式开关”不再参与运行', () {
    expect(provider.isManagementMode, isFalse);

    provider.addRecord('张三', '批评', const ['讲话'], 'class', '');
    final record = provider.getTodayRecords().single;
    expect(provider.canMutateRecord(record), isTrue);
  });

  test('开启后，记录人可在窗口内改删自己创建的记录', () {
    provider.setSelfEditWindowMinutes(10);
    provider.addRecord('张三', '批评', const ['讲话'], 'class', '');
    final record = provider.getTodayRecords().single;

    expect(record.createdByIdentityId, 'discipline_committee');
    expect(provider.canMutateRecord(record), isTrue);
    expect(
      provider.updateRecord(record.id, '批评', const ['讲话'], 'class', ''),
      isTrue,
    );
    expect(provider.deleteRecord(record.id, date: record.date), isTrue);
  });

  test('记录人不能改删他人记录；进入管理员模式后可以', () {
    provider.addRecord('张三', '批评', const ['讲话'], 'class', '');
    final record = provider.getTodayRecords().single;

    provider.setActiveIdentity('class_monitor');
    expect(provider.canMutateRecord(record), isFalse);
    expect(
      provider.updateRecord(record.id, '批评', const ['讲话'], 'class', ''),
      isFalse,
    );

    provider.enterManagementMode();
    expect(provider.isManagementMode, isTrue);
    expect(provider.canMutateRecord(record), isTrue);
    expect(
      provider.updateRecord(record.id, '批评', const ['讲话'], 'class', ''),
      isTrue,
    );
    provider.exitManagementMode();
    expect(provider.isManagementMode, isFalse);
  });

  test('关闭新增记录权限后，普通模式不能新增，管理员模式可以', () {
    provider.updateIdentity('discipline_committee', allowAddRecord: false);
    expect(provider.canActiveIdentityAddRecord, isFalse);

    provider.addRecord('张三', '批评', const ['讲话'], 'class', '');
    expect(provider.getTodayRecords(), isEmpty);

    provider.enterManagementMode();
    expect(provider.canActiveIdentityAddRecord, isTrue);
    provider.addRecord('张三', '批评', const ['讲话'], 'class', '');
    expect(provider.getTodayRecords().isNotEmpty, isTrue);
  });

  test('关闭考勤登记权限后，普通模式登记不生效，管理员模式可以', () {
    provider.updateIdentity(
      'discipline_committee',
      allowAttendanceRegister: false,
    );
    expect(provider.canActiveIdentityRegisterAttendance, isFalse);
    expect(
      provider.setAttendance('张三', '迟到', date: '2026-10-31'),
      isFalse,
    );

    provider.enterManagementMode();
    expect(provider.canActiveIdentityRegisterAttendance, isTrue);
    expect(
      provider.setAttendance('张三', '迟到', date: '2026-10-31'),
      isTrue,
    );
  });

  test('关闭某个身份的本人窗口权限后，该身份只能署名', () {
    expect(
      provider.updateIdentity(
        'discipline_committee',
        allowSelfEdit: false,
      ),
      isTrue,
    );
    provider.addRecord('张三', '批评', const ['讲话'], 'class', '');
    final record = provider.getTodayRecords().single;

    expect(record.createdByIdentityId, 'discipline_committee');
    expect(provider.canMutateRecord(record), isFalse);
    expect(
      provider.updateRecord(record.id, '批评', const ['讲话'], 'class', ''),
      isFalse,
    );
    provider.enterManagementMode();
    expect(
      provider.updateRecord(record.id, '批评', const ['讲话'], 'class', ''),
      isTrue,
    );
  });

  test('本人编辑窗口为 0 时，普通模式一律不能改删', () {
    provider.setSelfEditWindowMinutes(0);
    provider.addRecord('张三', '批评', const ['讲话'], 'class', '');
    final record = provider.getTodayRecords().single;

    expect(provider.canMutateRecord(record), isFalse);
    expect(
      provider.updateRecord(record.id, '批评', const ['讲话'], 'class', ''),
      isFalse,
    );
    provider.enterManagementMode();
    expect(
      provider.updateRecord(record.id, '批评', const ['讲话'], 'class', ''),
      isTrue,
    );
  });

  test('密码关闭时，普通模式不因无会话而阻止记录人操作', () {
    provider.setPasswordEnabled(false);
    provider.addRecord('张三', '批评', const ['讲话'], 'class', '');
    final record = provider.getTodayRecords().single;
    expect(provider.canMutateRecord(record), isTrue);
  });

  testWidgets('退出当前身份会结束管理会话，不会在超时后恢复旧身份', (tester) async {
    await tester.pumpWidget(const SizedBox());
    provider.enterManagementMode();
    expect(provider.isManagementMode, isTrue);
    expect(provider.activeIdentity?.isHeadTeacher, isTrue);

    provider.clearActiveIdentity();
    expect(provider.activeIdentity, isNull);
    expect(provider.isManagementMode, isFalse);

    await tester.pump(const Duration(minutes: 16));
    expect(provider.activeIdentity, isNull, reason: '旧管理计时器不能恢复身份');
  });

  testWidgets('管理中修改设置不会重新启动身份闲置计时', (tester) async {
    await tester.pumpWidget(const SizedBox());
    provider.enterManagementMode();
    expect(provider.isManagementMode, isTrue);

    provider.setIdentityIdleMinutes(1);
    await tester.pump(const Duration(minutes: 2));

    expect(provider.isManagementMode, isTrue,
        reason: '班主任管理只能由 management timer 结束，不能被身份闲置提前结束');
    provider.exitManagementMode();
    provider.clearActiveIdentity();
  });

  test('恢复出厂会清除管理会话与活动身份', () {
    provider.enterManagementMode();
    expect(provider.isManagementMode, isTrue);

    provider.factoryReset();

    expect(provider.isManagementMode, isFalse);
    expect(provider.activeIdentity, isNull);
  });

  test('考勤同步更新记录时保留创建者和创建时间', () {
    provider.setPasswordEnabled(false);
    provider.setAttendanceEnabled(true);
    provider.setAttendanceSyncMap(
      const {'迟到': '迟到', '早退': '早退'},
    );
    provider.setActiveIdentity('discipline_committee');
    provider.addRecord('张三', '批评', const ['迟到'], 'class', '');
    final before = provider.getTodayRecords().firstWhere(
      (record) => record.reasons.contains('迟到'),
    );
    expect(before.createdByIdentityId, 'discipline_committee');

    provider.setAttendance('张三', '早退', date: before.date!);

    final after = provider
        .getTodayRecords()
        .firstWhere((record) => record.id == before.id);
    expect(after.createdByIdentityId, 'discipline_committee');
    expect(after.createdAtIso, before.createdAtIso);
  });

  testWidgets('手动退出班主任管理后恢复进入前的普通身份', (tester) async {
    await tester.pumpWidget(const SizedBox());
    provider.enterManagementMode();
    expect(provider.activeIdentity?.isHeadTeacher, isTrue);

    provider.exitManagementMode();

    expect(provider.isManagementMode, isFalse);
    expect(provider.activeIdentity?.id, 'discipline_committee');
    provider.clearActiveIdentity();
  });

  testWidgets('班主任管理超时后恢复进入前的普通身份', (tester) async {
    await tester.pumpWidget(const SizedBox());
    provider.enterManagementMode();
    expect(provider.activeIdentity?.isHeadTeacher, isTrue);

    await tester.pump(const Duration(minutes: 16));

    expect(provider.isManagementMode, isFalse);
    expect(provider.activeIdentity?.id, 'discipline_committee');
    provider.clearActiveIdentity();
  });

}
