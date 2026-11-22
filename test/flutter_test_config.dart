import 'dart:async';
import 'dart:typed_data';

import 'package:class_management_system/constants/attendance_feature.dart';
import 'package:class_management_system/services/local_storage_paths.dart';
import 'package:class_management_system/services/log_file_service.dart';
import 'package:class_management_system/services/storage_service.dart';
import 'package:class_management_system/utils/app_clock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_bootstrap.dart';

/// 让既有考勤引擎/数据兼容测试继续运行；生产默认仍为关闭。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AttendanceFeature.enabledForTests = true;
  // 测试使用固定 32 字节数据密钥，避免触碰 DPAPI 与真实密钥文件。
  StorageService.debugDataKeyOverride = Uint8List.fromList(
    List<int>.generate(32, (i) => i + 1),
  );
  // 测试不执行 Windows ACL 加固（临时目录无需 icacls，也避免拖慢用例）。
  LogFileService.disableProtectionForTests = true;
  // 即使终端环境带有 CMS_DATA_DIR，也不允许测试读写真实数据目录。
  LocalStoragePaths.debugIgnoreEnvironmentOverride = true;

  // 全局默认文档目录：没有自行 mock path_provider 的用例也不会写真实用户目录，
  // 也不会因 MissingPluginException 让保存链静默失败（那样断言等于没验证）。
  // 每个用例换一个全新目录，避免上一个用例的异步写盘污染下一个用例。
  installGlobalTestPathProvider('cms_global_docs_');
  setUp(() {
    rotateGlobalTestDocumentsDir('cms_global_docs_');
    // 冻结时钟的用例结束后必须回到真实时钟，否则会污染后续用例。
    AppClock.resetForTest();
  });

  try {
    await testMain();
  } finally {
    uninstallTestPathProvider();
    await deleteRetiredTestDocumentsDirs();
  }
}
