// 共享测试初始化（B-19）：给 path_provider 一个临时文档目录，消掉
// “MissingPluginException(getApplicationDocumentsDirectory)”日志噪声，
// 并保证测试永远不写真实用户目录。
//
// 默认由 `test/flutter_test_config.dart` 全文件安装（每个用例前换一个全新的空目录），
// 因此绝大多数测试无需自己 mock；需要特定目录的测试仍可自行安装：
//   late Directory docsDir;
//   setUp(() { docsDir = createTestDocumentsDir('cms_xxx'); installTestPathProvider(docsDir); });
//   tearDown(() async { uninstallTestPathProvider(); await deleteTestDocumentsDir(docsDir); });
// 其中 `uninstallTestPathProvider()` 会回退到全局默认目录，而不是彻底移除 mock。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// 全局默认文档目录（由 flutter_test_config 安装，每个用例换新）。
Directory? _globalDocumentsDir;

/// 已经换下来的旧目录：等整轮测试结束后再统一删除。
///
/// 不在换目录时立刻删：上一个用例的异步写盘可能仍在进行，删掉会让它报
/// `PathNotFoundException`，日志噪声反而掩盖真实问题。
final List<Directory> _retiredDirs = <Directory>[];

/// 创建本测试专用的临时“文档目录”。
Directory createTestDocumentsDir(String prefix) {
  TestWidgetsFlutterBinding.ensureInitialized();
  return Directory.systemTemp.createTempSync(prefix);
}

/// 让 getApplicationDocumentsDirectory 返回 [dir]，避免写真实用户目录。
void installTestPathProvider(Directory dir) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async =>
        call.method == 'getApplicationDocumentsDirectory' ? dir.path : null,
  );
}

/// 安装全文件默认文档目录，并返回该目录。
///
/// 只在 `test/flutter_test_config.dart` 里调用。
Directory installGlobalTestPathProvider(String prefix) {
  final dir = createTestDocumentsDir(prefix);
  _globalDocumentsDir = dir;
  installTestPathProvider(dir);
  return dir;
}

/// 为下一个用例换一个全新的空文档目录。
Directory rotateGlobalTestDocumentsDir(String prefix) {
  final previous = _globalDocumentsDir;
  final dir = createTestDocumentsDir(prefix);
  _globalDocumentsDir = dir;
  installTestPathProvider(dir);
  if (previous != null) _retiredDirs.add(previous);
  return dir;
}

/// 删除全部换下来的旧目录（整轮测试结束时调用）。
Future<void> deleteRetiredTestDocumentsDirs() async {
  final dirs = List<Directory>.of(_retiredDirs);
  _retiredDirs.clear();
  for (final dir in dirs) {
    await deleteDirectoryWithRetry(dir);
  }
}

/// 移除本用例安装的 mock；若存在全局默认目录则回退到它。
void uninstallTestPathProvider() {
  final fallback = _globalDocumentsDir;
  if (fallback != null) {
    installTestPathProvider(fallback);
    return;
  }
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    null,
  );
}

/// 等文件句柄释放后删除临时目录（Windows 上偶发占用）。
Future<void> deleteTestDocumentsDir(Directory dir) async {
  await deleteDirectoryWithRetry(dir);
}
