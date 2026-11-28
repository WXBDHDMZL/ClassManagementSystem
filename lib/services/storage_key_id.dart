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
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'atomic_file.dart';

/// 数据密钥指纹（旁挂文件，审计 A-02）。
///
/// 背景：LRX3 密文里没有密钥标识，写错密钥与文件损坏在解密层面**不可区分**。
/// 5.0.1 起在主数据旁写一个明文指纹文件 `class_management_data.enc.keyid`，
/// 内容形如 `LRKID1:<16 位十六进制>`，由当前数据密钥单向派生：
///
/// ```
/// keyId = hex(sha256("cms-keyid-v1" ‖ key)[0..8))
/// ```
///
/// 指纹只占 64 bit，无法据以暴力还原 256 bit 数据密钥；它的唯一用途是
/// 让程序在"解不开"时能区分"密钥不对（换回原 .key 即可恢复）"与
/// "文件真损坏（只能走备份）"，从而避免把错钥当成损坏而隔离/重置数据。
///
/// 兼容性：指纹是**旁挂**文件，`.enc` 字节格式完全不变；旧版本读到新数据
/// 仍能正常解密（只是它不会校验指纹），新版本读旧数据因指纹缺失而退回
/// 原有判定逻辑。
class StorageKeyId {
  StorageKeyId._();

  /// 指纹文件后缀（跟在数据文件完整路径之后）。
  static const String fileSuffix = '.keyid';

  /// 文件内容前缀，用于识别"这是本程序的指纹文件"。
  static const String prefix = 'LRKID1:';

  /// 指纹长度（十六进制字符数）：8 字节 = 16 个字符。
  static const int hexLength = 16;

  /// 派生指纹用的用途前缀，避免与其它场景的同密钥哈希串用。
  static const String _context = 'cms-keyid-v1';

  /// 计算 [key] 对应的指纹（小写十六进制，长度恒为 [hexLength]）。
  static String compute(Uint8List key) {
    final digest = sha256.convert(<int>[
      ...utf8.encode(_context),
      ...key,
    ]).bytes;
    final first = digest.sublist(0, hexLength ~/ 2);
    return first
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// 判断 [raw] 是否是一个格式合法的指纹文件内容。
  ///
  /// 允许尾部换行/空白（写入时带一个换行便于人工查看）。
  static bool isValidContent(String raw) {
    final text = raw.trim();
    if (!text.startsWith(prefix)) return false;
    final hex = text.substring(prefix.length);
    if (hex.length != hexLength) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex);
  }

  /// 从文件内容里取出指纹（合法时统一转小写）；非法返回 null。
  static String? parse(String raw) =>
      isValidContent(raw) ? raw.trim().substring(prefix.length).toLowerCase() : null;

  /// 读取指纹文件；文件不存在返回 null。
  ///
  /// 内容非法（截断、被手工改动、写入中途掉电）同样返回 null —— 调用方
  /// 必须把"非法"当成"缺失"处理（退回旧判定），绝不能据此阻断启动。
  static Future<String?> read(File file) async {
    try {
      if (!await file.exists()) return null;
      return parse(await file.readAsString());
    } on Object {
      // 读失败等同于缺失：指纹只是辅助判定，不能让它的 IO 问题阻断启动。
      return null;
    }
  }

  /// 原子写入指纹（先临时文件后 rename，避免掉电留下半份内容）。
  ///
  /// 返回是否写入成功；失败由调用方记录并标记待重试，**不影响主数据保存结果**。
  static Future<bool> write(File file, String keyId) async {
    try {
      await AtomicFile.writeString(file.path, '$prefix$keyId\n');
      return true;
    } on Object {
      return false;
    }
  }
}
