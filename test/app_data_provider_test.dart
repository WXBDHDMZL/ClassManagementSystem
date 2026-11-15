// 数据层测试：记录增删改查与设置的落盘调用路径（保存失败不应抛异常）。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/providers/app_data_provider.dart';

void main() {
  test('新增记录后能在今日记录中查到，原因用顿号连接', () {
    final provider = AppDataProvider();

    provider.addRecord('张三', '表扬', ['认真听讲', '主动帮助同学'], 'class', '表现很好');

    final records = provider.getTodayRecords();
    expect(records.length, 1);
    expect(records.first.studentName, '张三');
    expect(records.first.operationType, '表扬');
    expect(records.first.reasons, '认真听讲、主动帮助同学');
    expect(records.first.remark, '表现很好');
    expect(records.first.isAppended, isFalse);
  });

  test('追加记录带追加标记，且默认备注为"追加"', () {
    final provider = AppDataProvider();

    provider.addRecord('李四', '批评', ['迟到'], 'class', '', isAppended: true);

    final record = provider.getTodayRecords().single;
    expect(record.isAppended, isTrue);
    expect(record.remark, '追加');
  });

  test('修改不存在的记录返回 false（供界面提示"记录可能已被删除"）', () {
    final provider = AppDataProvider();

    final updated = provider.updateRecord('不存在的ID', '表扬', ['认真听讲'], 'class', '');

    expect(updated, isFalse);
  });

  test('修改与删除已有记录均返回 true', () {
    final provider = AppDataProvider();
    provider.addRecord('王五', '表扬', ['认真听讲'], 'class', '');
    final id = provider.getTodayRecords().single.id;

    expect(provider.updateRecord(id, '批评', ['迟到'], 'class', '改为批评'), isTrue);
    expect(provider.getTodayRecords().single.operationType, '批评');
    expect(provider.getTodayRecords().single.remark, '改为批评');

    expect(provider.deleteRecord(id), isTrue);
    expect(provider.getTodayRecords(), isEmpty);
    expect(provider.deleteRecord(id), isFalse);
  });

  test('设置关闭行为后可在设置中读取（供持久化）', () {
    final provider = AppDataProvider();

    provider.setCloseAction(CloseActionType.minimizeToTray);

    expect(provider.appData.settings.closeAction, CloseActionType.minimizeToTray);
    // 其他设置项不受影响
    expect(provider.appData.settings.themeMode, ThemeModeType.system);
    expect(provider.appData.settings.exportPath, '');
  });

  test('出厂名单为空，清空名单后仍为空', () {
    final provider = AppDataProvider();
    expect(provider.appData.students, isEmpty,
        reason: '程序不应再内置任何真实或示例学生姓名');

    expect(provider.addStudent('测试同学'), isTrue);
    expect(provider.appData.students, ['测试同学']);

    provider.clearStudents();
    expect(provider.appData.students, isEmpty);
  });

  test('名单维护：新增/重名/改名/删除', () {
    final provider = AppDataProvider();
    final originalCount = provider.appData.students.length;

    expect(provider.addStudent('测试同学'), isTrue);
    expect(provider.appData.students.length, originalCount + 1);
    // 重名与空名拒绝
    expect(provider.addStudent('测试同学'), isFalse);
    expect(provider.addStudent('   '), isFalse);

    expect(provider.renameStudent('测试同学', '测试同学改名'), isTrue);
    expect(provider.appData.students.contains('测试同学改名'), isTrue);
    expect(provider.renameStudent('测试同学改名', '测试同学'), isTrue);
    expect(provider.appData.students.contains('测试同学'), isTrue);

    expect(provider.removeStudent('测试同学'), isTrue);
    expect(provider.appData.students.length, originalCount);
  });
}
