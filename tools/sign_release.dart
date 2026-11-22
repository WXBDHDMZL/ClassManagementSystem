// 离线签名工具：对安装包的 SHA-256 摘要做 Ed25519 签名。
// 私钥不进入仓库；发布机通过 --key 指向离线保存的 Base64 私钥文件。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--verify') continue;
    if (args[i].startsWith('--') && i + 1 < args.length) {
      options[args[i].substring(2)] = args[++i];
    }
  }
  final input = options['in'];
  final verify = args.contains('--verify');
  if (verify) {
    final signaturePath = options['sig'];
    final publicKey = options['pub'];
    if (input == null || signaturePath == null || publicKey == null) {
      stderr.writeln(
        '用法: dart run tools/sign_release.dart --verify '
        '--in <安装包.exe> --sig <签名.sig> --pub <公钥Base64>',
      );
      exit(64);
    }
    final file = File(input);
    if (!file.existsSync()) {
      stderr.writeln('安装包不存在: $input');
      exit(66);
    }
    final signatureBytes = base64Decode(File(signaturePath).readAsStringSync().trim());
    final publicKeyBytes = base64Decode(publicKey.trim());
    final digest = await sha256.bind(file.openRead()).first;
    final ok = await Ed25519().verify(
      digest.bytes,
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(
          publicKeyBytes,
          type: KeyPairType.ed25519,
        ),
      ),
    );
    stdout.writeln(ok ? 'SIGNATURE_OK' : 'SIGNATURE_INVALID');
    exit(ok ? 0 : 1);
  }
  final keyFile = options['key'];
  if (input == null || keyFile == null) {
    stderr.writeln(
      '用法: dart run tools/sign_release.dart --in <安装包.exe> '
      '--key <ed25519_private.b64> [--out <输出.sig>]',
    );
    exit(64);
  }
  final file = File(input);
  if (!file.existsSync()) {
    stderr.writeln('安装包不存在: $input');
    exit(66);
  }
  final seed = base64Decode(File(keyFile).readAsStringSync().trim());
  if (seed.length != 32) {
    stderr.writeln('私钥必须是 32 字节 Base64');
    exit(65);
  }
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final digest = await sha256.bind(file.openRead()).first;
  final signature = await Ed25519().sign(digest.bytes, keyPair: keyPair);
  final out = options['out'] ?? '${file.path}.sig';
  File(out).writeAsStringSync(base64Encode(signature.bytes));
  stdout.writeln('SHA256=${digest.toString()}');
  stdout.writeln('SIG=$out');
}
