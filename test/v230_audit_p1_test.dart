// 审计 P1 修复专项回归（2026-10-05，第二批：4/5/6/13/18/19/22）。
//
//   P1-4  "名单与原因库"密码开关此前永远失效（switch 缺 library 分支，恒要密码）；
//   P1-5  安全页"记录"开关文案与实际一致：只承诺保护编辑/删除/导入（新增记录
//         保持免密，为作者确认的设计决定）；
//   P1-6  统计区间"全部记录"(6) 可持久化，不再重启回退"本周"；
//   P1-13 数据包导入严格 UTF-8（非 UTF-8 直接拒绝，而不是 allowMalformed
//         静默乱码入库）；
//   P1-18 旧数据包缺 weekStart/attendanceEnabled 时保持本机值（不再把周日起始
//         重置为周一、把启用中的考勤关掉）；
//   P1-19 考勤表导出统一走 ExcelExport.saveWorkbook（界面层复用同一条保存链路，
//         由 analyze 与人工核对覆盖）；
//   P1-22 安装包重新打包（运维动作，非代码）。
//
// 模式沿用 v230_audit_p0_test：test() + mock path_provider。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/transfer_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late AppDataProvider provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cms_audit_p1');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.path
          : null,
    );
    provider = AppDataProvider();
  });

  tearDown(() async {
    await flushWrites(provider);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteDirectoryWithRetry(tempDir);
  });

  group('P1-6 统计区间持久化', () {
    test('全部记录(6) 存取一致；越界值回退本周(0)', () {
      final settings = AppSettings.defaultSettings();

      expect(
        AppSettings.fromJson(settings.copyWith(statisticsRange: 6).toJson())
            .statisticsRange,
        6,
      );
      expect(
        AppSettings.fromJson(settings.copyWith(statisticsRange: 7).toJson())
            .statisticsRange,
        0,
      );
    });
  });

  group('P1-13 数据包严格 UTF-8', () {
    test('非 UTF-8 字节被拒绝（抛 FormatException，不再静默乱码）', () {
      // GBK 编码的"班级"（B0 E0 BC B6）不是合法 UTF-8 序列。
      expect(
        () => TransferService.parsePackageBytes(const [0xB0, 0xE0, 0xBC, 0xB6]),
        throwsFormatException,
      );
    });

    test('本程序导出的 UTF-8 数据包可正常解析', () {
      provider.mergeStudents(['张三']);
      final text = TransferService.buildPackage(
        provider.appData,
        exportedAt: '2026-10-05T00:00:00',
      );

      final data = TransferService.parsePackageBytes(utf8.encode(text));

      expect(data, isNotNull);
      expect(data!.students, contains('张三'));
    });
  });

  group('P1-18 旧数据包缺失字段保持本机值', () {
    // 构造"旧版数据包"：顶层缺 weekStart / attendanceEnabled 两个键。
    Map<String, dynamic> legacyJson() {
      final json = jsonDecode(TransferService.buildPackage(
        AppData(
          recordsByDate: const {},
          settings: AppSettings.defaultSettings(),
        ),
        exportedAt: '2026-10-05T00:00:00',
      )) as Map<String, dynamic>;
      json.remove('weekStart');
      json.remove('attendanceEnabled');
      return json;
    }

    test('缺失键解析为 null（可区分"包内未包含"）', () {
      final data = TransferService.parsePackage(jsonEncode(legacyJson()));

      expect(data, isNotNull);
      expect(data!.weekStart, isNull, reason: '缺失应解析为 null，而不是回退 1');
      expect(data.attendanceEnabled, isNull, reason: '缺失应解析为 null，而不是回退 false');
    });

    test('整包还原旧包：本机周起始日与考勤开关保持不动', () async {
      provider.loadForTest(AppData(
        recordsByDate: const {},
        settings: AppSettings.defaultSettings()
            .copyWith(weekStart: 7, attendanceEnabled: true),
      ));
      final legacy = TransferService.parsePackage(jsonEncode(legacyJson()))!;

      await provider.restoreFromPackage(legacy);

      expect(provider.appData.settings.weekStart, 7, reason: '不能被旧包回退成 1');
      expect(provider.appData.settings.attendanceEnabled, isTrue,
          reason: '不能把启用中的考勤关掉');
    });

    test('包内带字段时按包内值生效（不误伤新包）', () async {
      provider.loadForTest(AppData(
        recordsByDate: const {},
        settings: AppSettings.defaultSettings().copyWith(weekStart: 1),
      ));
      final full = jsonDecode(TransferService.buildPackage(
        AppData(
          recordsByDate: const {},
          settings: AppSettings.defaultSettings()
              .copyWith(weekStart: 3, attendanceEnabled: false),
        ),
        exportedAt: '2026-10-05T00:00:00',
      )) as Map<String, dynamic>;
      final pkg = TransferService.parsePackage(jsonEncode(full))!;

      await provider.restoreFromPackage(pkg);

      expect(provider.appData.settings.weekStart, 3);
      expect(provider.appData.settings.attendanceEnabled, isFalse);
    });
  });
}
