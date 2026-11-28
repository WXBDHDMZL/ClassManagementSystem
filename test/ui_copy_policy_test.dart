// UI-01 守护测试：功能界面只写当前功能与操作指引，
// 不把更新日志、旧版对比、迁移/设计解释写进对话框、设置页或提示语。
//
// 覆盖范围：lib/ 下全部 Dart 文件的字符串字面量（含 ''' / """ 多行文案），
// 注释（// 与 /* */）不参与检查。历史版本号（V2./V3.）与“旧版/旧备份”
// 这类版本对比措辞一律禁止出现在界面文案里。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 规则与 Python 门禁 tools/ui_copy_check.py 共用同一份 JSON。
const _rulesPath = 'tools/ui_copy_rules.json';

/// 一个字符串字面量：起始行号 + 内容。
class _Literal {
  const _Literal(this.line, this.value);

  final int line;
  final String value;
}

/// start 指向 `$`，返回匹配 `}` 之后的位置；跳过内部嵌套字符串。
int _skipInterpolation(String source, int start) {
  var depth = 0;
  var i = start + 1;
  while (i < source.length) {
    final c = source[i];
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return i + 1;
    } else if (c == "'" || c == '"') {
      final q = c;
      final triple = q + q + q;
      if (source.startsWith(triple, i)) {
        final end = source.indexOf(triple, i + 3);
        i = end == -1 ? source.length : end + 3;
        continue;
      }
      i++;
      while (i < source.length) {
        if (source[i] == r'\') {
          i += 2;
          continue;
        }
        if (source[i] == q) {
          i++;
          break;
        }
        if (source[i] == '\n') break;
        i++;
      }
      continue;
    }
    i++;
  }
  return source.length;
}

/// 从 Dart 源码中提取字符串字面量，跳过注释。
///
/// 不追求完整语法树，只保证：注释不会误报、三引号长文案不会漏检。
List<_Literal> _extractLiterals(String source) {
  final literals = <_Literal>[];
  var i = 0;
  var line = 1;

  void advance(int count) {
    for (var k = 0; k < count && i < source.length; k++) {
      if (source.codeUnitAt(i) == 0x0A) line++;
      i++;
    }
  }

  while (i < source.length) {
    if (source.startsWith('//', i)) {
      while (i < source.length && source.codeUnitAt(i) != 0x0A) {
        i++;
      }
      continue;
    }
    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      advance((end == -1 ? source.length : end + 2) - i);
      continue;
    }
    if (source.startsWith("'''", i) || source.startsWith('"""', i)) {
      final quote = source.substring(i, i + 3);
      final startLine = line;
      var j = i + 3;
      while (j < source.length) {
        if (source[j] == r'\') {
          j += 2;
          continue;
        }
        if (source.startsWith(r'${', j)) {
          j = _skipInterpolation(source, j);
          continue;
        }
        if (source.startsWith(quote, j)) break;
        j++;
      }
      final stop = j > source.length ? source.length : j;
      literals.add(_Literal(startLine, source.substring(i + 3, stop)));
      advance((j >= source.length ? source.length : j + 3) - i);
      continue;
    }
    final unit = source.codeUnitAt(i);
    if (unit == 0x27 || unit == 0x22) {
      final quote = String.fromCharCode(unit);
      final startLine = line;
      var j = i + 1;
      var closed = false;
      while (j < source.length) {
        final c = source[j];
        if (c == r'$' && j + 1 < source.length && source[j + 1] == '{') {
          j = _skipInterpolation(source, j);
          continue;
        }
        if (c == r'\') {
          j += 2;
          continue;
        }
        if (c == quote) {
          closed = true;
          break;
        }
        if (c == '\n') break;
        j++;
      }
      final stop = j > source.length ? source.length : j;
      literals.add(_Literal(startLine, source.substring(i + 1, stop)));
      // 引号本身要吃掉，否则下一个循环会把它当成新的字符串开头。
      advance(stop - i + (closed ? 1 : 0));
      continue;
    }
    advance(1);
  }
  return literals;
}

void main() {
  test('三引号长文案与注释能被正确区分', () {
    const source = '''
// 注释里的旧版说明不参与检查
const a = '单行旧版对比';
const b = """
多行
旧版本内容
""";
final c = r'raw';
final d = '记录新增、\${true ? '考勤登记' : ''}';
''';
    final values = _extractLiterals(source).map((l) => l.value).toList();
    expect(values.any((v) => v.contains('单行旧版对比')), isTrue);
    expect(values.any((v) => v.contains('旧版本内容')), isTrue);
    expect(values.any((v) => v.contains('注释里的旧版说明')), isFalse);
    expect(values.any((v) => v.contains('记录新增') && v.contains('考勤登记')), isTrue);
  });

  test('功能界面字符串不得包含更新说明或旧版表述', () {
    final root = Directory('lib');
    expect(root.existsSync(), isTrue);

    final rulesFile = File(_rulesPath);
    expect(rulesFile.existsSync(), isTrue, reason: '缺少文案规则文件 $_rulesPath');
    final rules =
        jsonDecode(rulesFile.readAsStringSync()) as Map<String, dynamic>;
    final forbidden = (rules['forbidden'] as List).cast<String>();
    // 运行时状态词：描述“现在正在发生什么”，不是版本说明。
    final allowed = (rules['allowed'] as List).cast<String>();
    final gated = ((rules['gated_features'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final exemptFiles = ((rules['exempt_files'] as List?) ?? const [])
        .cast<String>()
        .toSet();

    final violations = <String>[];
    final files =
        root
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final rel = file.path.replaceAll('\\', '/');
      if (exemptFiles.contains(rel)) continue;
      final source = file.readAsStringSync();
      final literals = _extractLiterals(source);
      for (final literal in literals) {
        if (allowed.any(literal.value.contains)) continue;
        final hit = forbidden.where(literal.value.contains).toList();
        if (hit.isEmpty) continue;
        final flat = literal.value.replaceAll(RegExp(r'\s+'), ' ').trim();
        final shown = flat.length > 120 ? flat.substring(0, 120) : flat;
        violations.add(
          '${file.path}:${literal.line}: $shown（命中 ${hit.join('、')}）',
        );
      }
      violations.addAll(_gatedViolations(file.path, source, literals, gated));
    }

    expect(
      violations,
      isEmpty,
      reason: '发现功能界面更新说明/旧版表述：\n${violations.join('\n')}',
    );
  });
}

/// 功能未开放时仍被界面提到的文案（与 tools/ui_copy_check.py 同构）。
List<String> _gatedViolations(
  String path,
  String source,
  List<_Literal> literals,
  List<Map<String, dynamic>> gated,
) {
  final out = <String>[];
  final lines = source.split('\n');
  final rel = path.replaceAll('\\', '/');
  for (final rule in gated) {
    final word = (rule['word'] as String?) ?? '';
    if (word.isEmpty) continue;
    final guard = (rule['guard'] as String?) ?? '';
    final marker = (rule['marker'] as String?) ?? '';
    final window = (rule['window'] as num?)?.toInt() ?? 20;
    final scope = ((rule['scope'] as List?) ?? const []).cast<String>();
    final exempt = ((rule['exempt_files'] as List?) ?? const [])
        .cast<String>()
        .toSet();
    if (scope.isNotEmpty && !scope.any(rel.startsWith)) continue;
    if (exempt.contains(rel)) continue;
    for (final literal in literals) {
      if (!literal.value.contains(word)) continue;
      final idx = literal.line - 1;
      final lo = idx - window < 0 ? 0 : idx - window;
      final nearby = lines.sublist(lo, idx + 1).join('\n');
      if (guard.isNotEmpty && nearby.contains(guard)) continue;
      if (marker.isNotEmpty && nearby.contains(marker)) continue;
      final flat = literal.value.replaceAll(RegExp(r'\s+'), ' ').trim();
      final shown = flat.length > 120 ? flat.substring(0, 120) : flat;
      out.add('$path:${literal.line}: $shown（功能未开放仍提到「$word」）');
    }
  }
  return out;
}
