/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.2
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

/// 更新包签名公钥。
///
/// 私钥离线保管，不进入仓库或 CI；客户端只内置公钥。
/// 签名对象是安装包 SHA-256 摘要的 32 字节原始值，不是十六进制文本。
class UpdateSigningKey {
  const UpdateSigningKey._();

  static const String algorithm = 'Ed25519';

  /// 32 字节 Ed25519 公钥的 Base64。
  static const String publicKeyBase64 =
      'LWqn4rjZTaepwjPYMTYDPGneXs/Lj+tnrCWFMahkn48=';
}
