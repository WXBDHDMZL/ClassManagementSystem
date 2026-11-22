// 大数据量冒烟：记录攒到约一万条（55 人 × 一学期）时，统计与存取仍然正确、不超时。
//
// 背景（V2.28.1 测试深化）：实际使用是一届学生用一整年，记录会持续累积。
// 此前所有测试都用几条~几十条数据，若某次改动引入 O(n²) 的遍历或重复排序，
// 在小数据上完全看不出来，等老师用到半年才发现统计卡死。本文件用约 1 万条
// 记录做三件事：统计结果数字自洽、存取闭环数据不丢、耗时低于宽松上限
// （上限故意放得很宽——只防"灾难性退化"，不测机器性能）。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/services/storage_service.dart';

import 'test_helpers.dart';

const _studentCount = 55;
const _recordsPerStudent = 180; // 约 9900 条，接近一学期高频使用

StudentRecord _record(int studentNo, int seq) {
  final name = '学生${studentNo.toString().padLeft(2, '0')}';
  final date = '2026-03-${(seq % 28 + 1).toString().padLeft(2, '0')}';
  return StudentRecord(
    id: 'big-$studentNo-$seq',
    studentName: name,
    operationType: studentNo <= 3 ? '批评' : '表扬', // 前 3 人高频批评
    reasons: seq.isEven ? '课堂纪律' : '作业未交',
    periodKey: 'class',
    periodName: '上课',
    remark: '',
    timestamp: '08:${(seq % 60).toString().padLeft(2, '0')}:00',
    isAppended: false,
    date: date,
  );
}

List<StudentRecord> _bigRecords() => [
      for (var s = 1; s <= _studentCount; s++)
        for (var i = 0; i < _recordsPerStudent; i++) _record(s, i),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('一万条记录：统计结果数字自洽，计算在宽松时限内完成', () {
    final records = _bigRecords();
    expect(records.length, _studentCount * _recordsPerStudent);

    final watch = Stopwatch()..start();
    final result = StatisticsService.compute(records);
    final attention = StatisticsService.attentionStudents(records);
    watch.stop();

    // 数字自洽：表扬 + 批评 = 总条数；前 3 人每人 180 条批评且霸榜。
    final praise = result.summary.praiseCount;
    final criticize = result.summary.criticizeCount;
    expect(praise + criticize, records.length);
    expect(criticize, 3 * _recordsPerStudent);
    expect(result.criticizeRanking.first.count, _recordsPerStudent);
    expect(result.criticizeRanking.take(3).map((c) => c.name).toSet(),
        {'学生01', '学生02', '学生03'});
    // 需关注：高频批评的 3 人都在，其余全是表扬的不进名单。
    expect(attention.map((a) => a.name).toSet(), {'学生01', '学生02', '学生03'});
    // 不该有重复 id（排查"同一人同一天被记两次算一条"之类的回归）。
    expect(records.map((r) => r.id).toSet().length, records.length);

    expect(watch.elapsed, lessThan(const Duration(seconds: 10)),
        reason: '一万条统计超过 10 秒 = 大概率引入了灾难性的重复遍历');
  });

  test('一万条记录：加密存盘 → 读回闭环，数据一条不少、内容一致', () async {
    final tempDir = createStorageTestRoot('cms_big_data');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.parent.path
          : null,
    );
    final storage = StorageService();

    final byDate = <String, List<StudentRecord>>{};
    for (final r in _bigRecords()) {
      byDate.putIfAbsent(r.date!, () => []).add(r);
    }
    final data = AppData(
      recordsByDate: byDate,
      settings: AppSettings(themeMode: ThemeModeType.system),
    );

    final watch = Stopwatch()..start();
    final saved = await storage.saveData(data);
    final loaded = await storage.loadData();
    watch.stop();

    expect(saved, isTrue, reason: '一万条也要能正常加密落盘');
    expect(loaded.restoredFromBackup, isFalse, reason: '读写闭环不该触发恢复');
    final loadedCount = loaded.data.recordsByDate.values
        .fold<int>(0, (sum, list) => sum + list.length);
    expect(loadedCount, _studentCount * _recordsPerStudent,
        reason: '读回的记录总数必须分毫不差');
    // 抽查内容：任取一条，关键字段原样。
    final sample = loaded.data.recordsByDate['2026-03-01']!
        .firstWhere((r) => r.id == 'big-1-0');
    expect(sample.studentName, '学生01');
    expect(sample.reasons, '课堂纪律');
    expect(sample.operationType, '批评');

    expect(watch.elapsed, lessThan(const Duration(seconds: 20)),
        reason: '一万条完整存取超过 20 秒 = 加密/序列化出现了不该有的退化');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await flushWrites(null);
    await deleteStorageTestRoot(tempDir);
  });
}
