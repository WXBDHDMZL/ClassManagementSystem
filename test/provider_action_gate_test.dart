// V3 权限回归：旧动作开关不再参与运行；记录编辑/删除固定按
// “本人窗口 / 管理员模式”判断。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/auth_service.dart';

void main() {
  late AppDataProvider provider;

  setUp(() {
    AuthService.resetForTest();
    provider = AppDataProvider();
    provider.addRecord('张三', '批评', const ['讲话'], 'class', '');
  });

  tearDown(() {
    provider.dispose();
    AuthService.resetForTest();
  });

  test('无本人身份时，记录编辑/删除需要管理员模式', () {
    provider.setPasswordEnabled(true);
    final record = provider.getTodayRecords().single;

    expect(
      provider.updateRecord(record.id, '批评', const ['讲话'], 'class', ''),
      isFalse,
    );
    expect(provider.deleteRecord(record.id, date: record.date), isFalse);

    provider.enterManagementMode();
    expect(
      provider.updateRecord(record.id, '批评', const ['讲话'], 'class', ''),
      isTrue,
    );
    expect(provider.deleteRecord(record.id, date: record.date), isTrue);
  });
}
