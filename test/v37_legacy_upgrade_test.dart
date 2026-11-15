// V3.7.x 回归：旧版文档根目录数据的一次性迁移与“不写空库”保护。
//
// 背景：V3.7.0 删除了旧布局迁移后，升级机器若数据仍在
// `文档/class_management_data.enc`，新版本会直接显示空库，首次保存还会生成
// 一份新的空库。本用例锁定两条底线：
//   1. 旧数据可解析 → 自动复制到 `文档/班级管理系统/`，旧文件保留；
//   2. 旧数据损坏/迁移失败 → 启动提示错误，且保存链拒绝写空库。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/storage_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory docs;
  late StorageService service;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    docs = Directory.systemTemp.createTempSync('cms_v37_legacy');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? docs.path
              : null,
        );
    service = StorageService();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await deleteDirectoryWithRetry(docs);
  });

  File legacyFile() =>
      File('${docs.path}${Platform.pathSeparator}class_management_data.enc');
  File legacyBackup() => File('${legacyFile().path}.bak');
  File newFile() => File(
    '${docs.path}${Platform.pathSeparator}班级管理系统'
    '${Platform.pathSeparator}class_management_data.enc',
  );

  AppData sampleData() => AppData(
    recordsByDate: {
      '2026-10-01': [
        StudentRecord(
          id: 'legacy-1',
          studentName: '张三',
          operationType: '表扬',
          reasons: '认真',
          periodKey: 'class',
          periodName: '上课',
          remark: '',
          timestamp: '08:00:00',
          date: '2026-10-01',
        ),
      ],
    },
    settings: AppSettings.defaultSettings(),
    students: const ['张三'],
  );

  test('新目录没有数据时，旧布局主文件与可解析备份被一次性复制', () async {
    final text = await service.encodeForTest(sampleData());
    await legacyFile().writeAsString(text);
    await legacyBackup().writeAsString(text);

    final result = await service.loadData();

    expect(result.migratedFromLegacyLayout, isTrue);
    expect(result.legacyLayoutUnreadable, isFalse);
    expect(result.data.recordsByDate['2026-10-01'], hasLength(1));
    expect(await newFile().exists(), isTrue);
    expect(await File('${newFile().path}.bak').exists(), isTrue);
    expect(await legacyFile().exists(), isTrue, reason: '迁移只复制，不删除旧文件');
  });

  test('旧主文件缺失时，仅旧备份也能迁移到新目录', () async {
    final text = await service.encodeForTest(sampleData());
    await legacyBackup().writeAsString(text);

    final result = await service.loadData();

    expect(result.migratedFromLegacyLayout, isTrue);
    expect(result.data.recordsByDate['2026-10-01'], hasLength(1));
    expect(await newFile().exists(), isTrue);
    expect(await legacyBackup().exists(), isTrue, reason: '迁移只复制，不删除旧备份');
  });

  test('仅旧备份且无法解析时，也阻止保存空库', () async {
    await legacyBackup().writeAsString('不是有效的 LRX2 数据');

    final result = await service.loadData();
    expect(result.legacyLayoutUnreadable, isTrue);

    final saved = await service.saveData(AppData.empty());
    expect(saved, isFalse);
    expect(await newFile().exists(), isFalse);
  });

  test('旧备份复制失败不影响主数据迁移', () async {
    final text = await service.encodeForTest(sampleData());
    await legacyFile().writeAsString(text);
    await legacyBackup().writeAsString(text);

    // 新 .bak 位置被目录占用，复制备份必然失败；主数据已复制成功时
    // 不能因此把整次迁移判定为失败。
    final root = Directory(
      '${docs.path}${Platform.pathSeparator}班级管理系统',
    );
    await root.create(recursive: true);
    await Directory('${newFile().path}.bak').create(recursive: true);

    final result = await service.loadData();

    expect(result.migratedFromLegacyLayout, isTrue);
    expect(result.legacyLayoutUnreadable, isFalse);
    expect(result.data.recordsByDate['2026-10-01'], hasLength(1));
    expect(await newFile().exists(), isTrue);
    expect(await legacyFile().exists(), isTrue);
  });

  test('旧布局数据无法解析时提示错误，并阻止保存空库', () async {
    await legacyFile().writeAsString('不是有效的 LRX2 数据');

    final result = await service.loadData();
    expect(result.legacyLayoutUnreadable, isTrue);
    expect(await newFile().exists(), isFalse);

    final saved = await service.saveData(AppData.empty());
    expect(saved, isFalse);
    expect(await newFile().exists(), isFalse, reason: '旧数据未迁移成功时不能生成新空库');
    expect(await legacyFile().exists(), isTrue);
  });

  test('旧布局数据损坏时，Provider 启动提示为错误', () async {
    await legacyFile().writeAsString('不是有效的 LRX2 数据');
    final provider = AppDataProvider();

    await provider.initialize();

    expect(provider.startupNoticeIsError, isTrue);
    expect(provider.startupNotice, contains('文档目录中的数据无法读取'));
    expect(await newFile().exists(), isFalse);
  });
}
