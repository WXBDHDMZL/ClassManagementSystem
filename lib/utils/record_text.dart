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

/// 记录文本的统一净化口径（纯 Dart，不依赖 Flutter/provider）。
///
/// 为什么单独抽出来：写入侧（`_buildRecord`）与导入判重侧（`import_service`）
/// 必须用**同一套** trim/限长/分隔符规则，否则“先导入、再导入同一文件”会因
/// 判重键与落库值不一致而重复入库（BACKLOG B-07）。
class RecordText {
  RecordText._();

  static const int maxNameLength = 30;
  static const int maxReasonLength = 50;
  static const int maxRemarkLength = 200;

  /// 按“字符”而非 UTF-16 code unit 截断（审计 P3）。
  ///
  /// 旧实现用 `String.length`/`substring`，遇到 emoji、生僻字等代理对时会把
  /// 一个字符切成两半，落库后显示成"�"。这里按 runes 截断，保证不会切断
  /// 任何完整字符。
  static String _clip(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    final runes = value.runes.toList(growable: false);
    if (runes.length <= maxLength) return value;
    return String.fromCharCodes(runes.take(maxLength));
  }

  static String clipName(String name) => _clip(name, maxNameLength);

  static String clipReason(String reason) => _clip(reason, maxReasonLength);

  static String clipRemark(String remark) => _clip(remark, maxRemarkLength);

  /// 姓名净化：trim + 限长（写入侧与判重侧同口径）。
  static String normalizeName(String name) => clipName(name.trim());

  /// 单条原因净化：trim、顿号换成中文逗号（顿号是存储分隔符）、限长。
  static String normalizeReason(String reason) =>
      clipReason(reason.trim().replaceAll('、', '，'));

  /// 原因串净化：按顿号拆分 → 逐条净化 → 丢弃空项 → 用顿号重新拼接。
  ///
  /// 表格里的原因单元格可能带空格/多余顿号；写入侧会拆开后再拼接，
  /// 判重键也必须走同一路径，否则会误判为“新记录”。
  static String normalizeReasons(String reasons) {
    final parts = reasons.split('、');
    final cleaned = <String>[];
    for (final part in parts) {
      final value = normalizeReason(part);
      if (value.isNotEmpty) cleaned.add(value);
    }
    return cleaned.join('、');
  }

  /// 备注净化：trim + 限长。
  static String normalizeRemark(String remark) => clipRemark(remark.trim());
}
