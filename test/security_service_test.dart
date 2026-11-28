// 管理密码测试：哈希口径一致、自定义密码校验、新密码规则。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/security_service.dart';

void main() {
  test('自定义密码校验通过，错误密码被拒绝', () {
    final stored = SecurityService.hashPassword('abcd1234');

    expect(SecurityService.verifyPassword('abcd1234', storedHash: stored), isTrue);
    expect(SecurityService.verifyPassword('abcd12345', storedHash: stored), isFalse);
    expect(SecurityService.verifyPassword('', storedHash: stored), isFalse);
  });

  test('首尾空格被忽略，避免输入法误带空格', () {
    final stored = SecurityService.hashPassword(' abcd1234 ');

    expect(SecurityService.verifyPassword('abcd1234', storedHash: stored), isTrue);
    expect(SecurityService.verifyPassword('  abcd1234  ', storedHash: stored), isTrue);
  });

  test('未设置自定义密码时回退出厂默认密码', () {
    // 出厂密码未知，只验证"错误密码一定过不了"与生效哈希的取值逻辑。
    expect(SecurityService.verifyPassword('这不是出厂密码'), isFalse);
    expect(
      SecurityService.effectivePasswordHash(''),
      isNot(SecurityService.effectivePasswordHash('abc')),
    );
  });

  test('新密码规则：非空、6-20 位、两次一致、拒绝弱口令（V2.36.0 起）', () {
    expect(SecurityService.validateNewPassword('', ''), '新密码不能为空');
    expect(SecurityService.validateNewPassword('   ', '   '), '新密码不能为空');
    expect(SecurityService.validateNewPassword('abc', 'abc'), '新密码需为 6-20 位');
    expect(
      SecurityService.validateNewPassword('a' * 21, 'a' * 21),
      '新密码需为 6-20 位',
    );
    expect(
      SecurityService.validateNewPassword('abcd1234', 'abcd12345'),
      '两次输入的新密码不一致',
    );
    expect(SecurityService.validateNewPassword('abcd', 'abcd'), '新密码需为 6-20 位');
    expect(SecurityService.validateNewPassword('abcdef', 'abcdef'), isNull);
    expect(
      SecurityService.validateNewPassword(
        'abcd1234efgh5678ijkl',
        'abcd1234efgh5678ijkl',
      ),
      isNull,
    );
    // 弱口令：常见口令 / 纯重复 / 递增数字
    expect(
      SecurityService.validateNewPassword('123456', '123456'),
      '密码过于简单，请换一个更复杂的密码',
    );
    expect(
      SecurityService.validateNewPassword('aaaaaa', 'aaaaaa'),
      '密码过于简单，请换一个更复杂的密码',
    );
    expect(
      SecurityService.validateNewPassword('12345678', '12345678'),
      '密码过于简单，请换一个更复杂的密码',
    );
  });

  test('新哈希带随机盐：同一密码两次哈希不同，但都能校验通过（V2.30.2 加固）', () {
    final first = SecurityService.hashPassword('abcd1234');
    final second = SecurityService.hashPassword(' abcd1234 ');
    // 加了随机盐之后哈希串不再稳定——这正是防"彩虹表/同密码比对"的目的。
    expect(first, isNot(second));
    expect(first.startsWith('p2:'), isTrue, reason: '新密码一律使用加盐多轮格式');
    expect(SecurityService.verifyPassword('abcd1234', storedHash: first), isTrue);
    expect(SecurityService.verifyPassword('abcd1234', storedHash: second), isTrue);
    expect(SecurityService.verifyPassword('别的密码', storedHash: first), isFalse);
  });

  test('旧格式哈希不再接受，必须是带迭代次数的 p2 三段格式', () {
    const singleRound = 'e3b0c44298fc1c149afbf4c8996fb924'
        '27ae41e4649b934ca495991b7852b855';
    expect(SecurityService.verifyPassword('', storedHash: singleRound), isFalse);

    const twoSegment =
        'p2:MDEyMzQ1Njc4OWFiY2RlZg==:NCnHNwX6k779B+V2X5RdBq3KaFX8lVLxX5FY4QLs1Uo=';
    expect(SecurityService.verifyPassword('000000', storedHash: twoSegment),
        isFalse);
  });

  group('A-17 出厂默认密码识别', () {
    test('哈希为空视为仍在用出厂默认密码', () {
      expect(SecurityService.isUsingFactoryPassword(''), isTrue);
      expect(SecurityService.isUsingFactoryPassword('   '), isTrue);
    });

    test('出厂裸 SHA-256 常量被识别（大小写与空白不敏感）', () {
      const raw =
          '5582868f17d5b4fd3aa9fe7251f8409dcfb6a11f4653e3e704bbf4842786ef6f';
      expect(SecurityService.isUsingFactoryPassword(raw), isTrue);
      expect(SecurityService.isUsingFactoryPassword(raw.toUpperCase()), isTrue);
      expect(SecurityService.isUsingFactoryPassword('  $raw '), isTrue);
    });

    test('用户自设的加盐哈希不算出厂密码', () {
      final stored = SecurityService.hashPassword('abcd1234');
      expect(SecurityService.isUsingFactoryPassword(stored), isFalse);
    });
  });
}
