/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.13.0
 * 创建日期 (Created): 2026-10-01
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

/// 程序版本号的**唯一来源**。
///
/// 此前版本号写死在关于页、设置面板、开源许可页等 3 处 + 45 个文件头注释里，
/// 每次发版都要全量替换，曾多次出现漏改/错改。现在：
///  - 界面与开源许可页统一引用 [version]；
///  - `pubspec.yaml` 的 version 与本文档保持一致（发布脚本核对）；
///  - 文件头注释仅作说明用途，允许滞后。
class AppVersion {
  const AppVersion._();

  /// 展示用版本号（如 V2.25.2）。
  static const String version = 'V4.13.0';

  /// pubspec.yaml 中的 version 字段（便于发布脚本核对）。
  static const String pubspecVersion = '4.13.0+175';

  /// 公开源码地址。
  static const String sourceCodeUrl =
      'https://github.com/WXBDHDMZL/ClassManagementSystem';

  /// GitHub 仓库归属（用于程序内检查更新）。
  static const String githubOwner = 'WXBDHDMZL';
  static const String githubRepo = 'ClassManagementSystem';

  /// 作者联系方式：源码获取、许可问题与问题反馈。
  static const String contactEmail = 'WXBDHDMZL@outlook.com';
}
