/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-11-28
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/backup_crypto.dart';

void main() {
  final dataKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 7));

  /// 造一个声明了 [rounds] 迭代数的信封（kek 用同样的轮数派生）。
  String envelopeWith({required int rounds, String password = 'StrongPass123!'}) {
    final real = BackupCrypto.wrapKeyForTest(
      dataKey,
      password,
      rounds: rounds,
    );
    final map = jsonDecode(real) as Map<String, dynamic>;
    map['iterations'] = rounds;
    return jsonEncode(map);
  }

  group('A-20 密钥派生强度与后台派生', () {
    test('wrapKeyAsync / unwrapKeyAsync 往返一致', () async {
      final envelope = await BackupCrypto.wrapKeyAsync(
        dataKey,
        'StrongPass123!',
      );
      expect(BackupCrypto.iterationsOf(envelope), BackupCrypto.iterations);

      final unwrapped = await BackupCrypto.unwrapKeyAsync(
        envelope,
        'StrongPass123!',
      );
      expect(unwrapped, isNotNull);
      expect(unwrapped, equals(dataKey));
    });

    test('口令错误时后台解包返回 null（不抛异常）', () async {
      final envelope = await BackupCrypto.wrapKeyAsync(
        dataKey,
        'StrongPass123!',
      );
      expect(await BackupCrypto.unwrapKeyAsync(envelope, 'wrong-pass'), isNull);
    });

    test('迭代数低于下限的信封被拒绝', () async {
      final envelope = envelopeWith(rounds: BackupCrypto.minIterations - 1);
      expect(BackupCrypto.unwrapKey(envelope, 'StrongPass123!'), isNull);
    });

    test('迭代数高于上限的信封被拒绝（防篡改放大卡死恢复）', () async {
      final envelope = envelopeWith(rounds: BackupCrypto.maxIterations + 1);
      expect(BackupCrypto.unwrapKey(envelope, 'StrongPass123!'), isNull);
    });

    test('低于当前标准的旧信封仍可恢复，只是被标记为弱', () {
      final weak = envelopeWith(rounds: BackupCrypto.minIterations);
      expect(BackupCrypto.isWeakEnvelope(weak), isTrue);
      expect(
        BackupCrypto.unwrapKey(weak, 'StrongPass123!'),
        equals(dataKey),
        reason: 'A-20：旧备份不能因为强度偏低就打不开',
      );

      final current = BackupCrypto.wrapKey(dataKey, 'StrongPass123!');
      expect(BackupCrypto.isWeakEnvelope(current), isFalse);
    });

    test('信封损坏时 iterationsOf 返回 null 且不当作弱信封', () {
      expect(BackupCrypto.iterationsOf('not-json'), isNull);
      expect(BackupCrypto.iterationsOf('{"format":"LRBK"}'), isNull);
      expect(BackupCrypto.isWeakEnvelope('not-json'), isFalse);
      expect(BackupCrypto.isWeakEnvelope('{"iterations":"abc"}'), isFalse);
    });
  });
}
