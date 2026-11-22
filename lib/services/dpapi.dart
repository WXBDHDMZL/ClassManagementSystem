/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.0
 * 创建日期 (Created): 2026-11-22
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Windows DPAPI（当前用户范围）封装。
///
/// DPAPI 把数据绑定到当前 Windows 用户；同一台机器上的其他用户无法解密。
/// 它不防“以当前用户身份运行的程序”，但能避免把数据密钥明文放在磁盘上。
class Dpapi {
  Dpapi._();

  static const int _uiForbidden = 0x1;

  static Uint8List protect(Uint8List plain) {
    if (!Platform.isWindows) {
      throw UnsupportedError('DPAPI 仅在 Windows 上可用');
    }
    final input = calloc<Uint8>(plain.length);
    final inputBlob = calloc<CRYPT_INTEGER_BLOB>();
    final outputBlob = calloc<CRYPT_INTEGER_BLOB>();
    try {
      input.asTypedList(plain.length).setAll(0, plain);
      inputBlob.ref
        ..cbData = plain.length
        ..pbData = input;
      final ok = CryptProtectData(
        inputBlob,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        _uiForbidden,
        outputBlob,
      );
      if (ok == 0) {
        throw StateError('CryptProtectData 失败：${GetLastError()}');
      }
      final output = outputBlob.ref;
      try {
        return Uint8List.fromList(output.pbData.asTypedList(output.cbData));
      } finally {
        LocalFree(output.pbData.cast());
      }
    } finally {
      calloc.free(inputBlob);
      calloc.free(input);
      calloc.free(outputBlob);
    }
  }

  static Uint8List unprotect(Uint8List cipher) {
    if (!Platform.isWindows) {
      throw UnsupportedError('DPAPI 仅在 Windows 上可用');
    }
    final input = calloc<Uint8>(cipher.length);
    final inputBlob = calloc<CRYPT_INTEGER_BLOB>();
    final outputBlob = calloc<CRYPT_INTEGER_BLOB>();
    try {
      input.asTypedList(cipher.length).setAll(0, cipher);
      inputBlob.ref
        ..cbData = cipher.length
        ..pbData = input;
      final ok = CryptUnprotectData(
        inputBlob,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        _uiForbidden,
        outputBlob,
      );
      if (ok == 0) {
        throw StateError('CryptUnprotectData 失败：${GetLastError()}');
      }
      final output = outputBlob.ref;
      try {
        return Uint8List.fromList(output.pbData.asTypedList(output.cbData));
      } finally {
        LocalFree(output.pbData.cast());
      }
    } finally {
      calloc.free(inputBlob);
      calloc.free(input);
      calloc.free(outputBlob);
    }
  }
}
