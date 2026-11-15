// V3 复合流程授权回归：入口动作验证一次后，内部子写入不应再被各自的
// 敏感动作门禁拦截；未进入管理员模式时整个作用域必须拒绝。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/password_policy.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/auth_service.dart';

void main() {
  late AppDataProvider provider;

  setUp(() {
    AuthService.resetForTest();
    provider = AppDataProvider();
    provider.setPasswordEnabled(true);
  });

  tearDown(() {
    provider.dispose();
    AuthService.resetForTest();
  });

  test('未进入管理员模式时复合流程整段拒绝', () {
    final applied = provider.runWithAuthorizedActionVoid(
      PasswordAction.dataPackageImport,
      () {
        provider.addStudent('不应写入');
        provider.setPeriods(const []);
      },
    );
    expect(applied, isFalse);
    expect(provider.appData.students.contains('不应写入'), isFalse);
  });

  test('管理员模式下入口授权一次，内部名单/时段子写入放行', () {
    provider.enterManagementMode();
    final applied = provider.runWithAuthorizedActionVoid(
      PasswordAction.dataPackageImport,
      () {
        provider.addStudent('复合流程学生');
        provider.setPeriods(const []);
      },
    );
    expect(applied, isTrue);
    expect(provider.appData.students.contains('复合流程学生'), isTrue);
  });

  test('作用域结束后恢复新模型的固定门禁', () {
    provider.enterManagementMode();
    expect(
      provider.runWithAuthorizedActionVoid(
        PasswordAction.dataPackageImport,
        () => provider.addStudent('作用域内'),
      ),
      isTrue,
    );
    provider.exitManagementMode();
    expect(provider.addStudent('作用域外'), isFalse);
  });
}
