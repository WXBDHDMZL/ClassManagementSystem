/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-11-22
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

/// 从 GitHub Release 正文中取出适合应用内展示的部分。
///
/// 发布正文通常还会包含升级说明、发布资产、签名与安装器说明；
/// 这些内容不应出现在“版本内容”卡片里。优先使用作者显式标记的
/// `<!-- app:start -->` / `<!-- app:end -->` 区块；没有标记时，
/// 只取第一个“主要变化”类标题下的内容；都没有时返回空，避免把
/// 升级说明、发布资产等无关内容展示给用户。
class ReleaseNotes {
  const ReleaseNotes._();

  static const String startMarker = '<!-- app:start -->';
  static const String endMarker = '<!-- app:end -->';

  static const Set<String> _sectionTitles = {
    '主要变化',
    '新功能',
    '修复内容',
    '改进与修复',
  };

  /// 返回应用内应展示的正文；没有可用内容时返回空字符串。
  static String forApp(String notes) {
    final normalized = notes
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (normalized.isEmpty) return '';

    final start = normalized.indexOf(startMarker);
    if (start >= 0) {
      final end = normalized.indexOf(
        endMarker,
        start + startMarker.length,
      );
      if (end > start) {
        final marked = normalized
            .substring(start + startMarker.length, end)
            .trim();
        if (marked.isNotEmpty) return marked;
      }
    }

    return _mainSection(normalized) ?? '';
  }

  static String? _mainSection(String notes) {
    final lines = notes.split('\n');
    var start = -1;
    for (var i = 0; i < lines.length; i++) {
      final title = _headingTitle(lines[i]);
      if (title != null && _sectionTitles.contains(title)) {
        start = i;
        break;
      }
    }
    if (start < 0) return null;

    final buffer = <String>[];
    for (var i = start; i < lines.length; i++) {
      if (i > start && _headingTitle(lines[i]) != null) break;
      buffer.add(lines[i]);
    }
    final section = buffer.join('\n').trim();
    return section.isEmpty ? null : section;
  }

  static String? _headingTitle(String line) {
    final match = RegExp(r'^#{1,6}\s+(.+?)\s*$').firstMatch(line.trim());
    return match?.group(1)?.trim();
  }
}
