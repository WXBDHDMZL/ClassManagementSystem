// 第 10 轮清理批回归（V2.30.31）。
//
//   X-33 showTopSnackBar 统一经过 AppNotificationScope；这里覆盖宿主销毁与
//        正常计时结束两条路径，确保控制器收尾安全。
//   去重：formatChineseDate 统一了 record_list 与 attendance_dialog 的日期显示。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/utils/app_date.dart';
import 'package:class_management_system/widgets/app_notification.dart';

void main() {
  group('X-33 Scope 通知计时与销毁', () {
    testWidgets('宿主销毁后，通知计时结束不抛异常', (tester) async {
      final controller = AppNoticeController();
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: AppNotificationScope(
            controller: controller,
            child: AppNotificationHost(
              child: Builder(
                builder: (context) {
                  ctx = context;
                  return const Scaffold(body: SizedBox());
                },
              ),
            ),
          ),
        ),
      );

      showTopSnackBar(ctx, '测试提示');
      await tester.pump();
      expect(find.text('测试提示'), findsOneWidget);

      // 在 2.5 秒计时器触发前销毁宿主；控制器仍应安全完成通知。
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      controller.dispose();
    });

    testWidgets('正常路径：计时结束后条目被移除并释放', (tester) async {
      final controller = AppNoticeController();
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: AppNotificationScope(
            controller: controller,
            child: AppNotificationHost(
              child: Builder(
                builder: (context) {
                  ctx = context;
                  return const Scaffold(body: SizedBox());
                },
              ),
            ),
          ),
        ),
      );

      final handle = showTopSnackBar(ctx, '测试提示');
      await tester.pump();
      expect(handle.isDone, isFalse);
      expect(find.text('测试提示'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('测试提示'), findsNothing);
      expect(handle.isDone, isTrue);
      expect(
        () => handle.addListener(() {}),
        throwsA(isA<AssertionError>()),
        reason: '计时结束后通知句柄未被标记结束（资源泄漏）',
      );
      expect(tester.takeException(), isNull);
      controller.dispose();
    });
  });

  group('共享日期格式化', () {
    test('formatChineseDate 把 yyyy-MM-dd 显示为中文日期', () {
      expect(formatChineseDate('2026-10-04'), '2026年10月04日');
      expect(formatChineseDate('2026-01-01'), '2026年01月01日');
    });

    test('格式不符时原样返回，不抛错', () {
      expect(formatChineseDate('bad'), 'bad');
      expect(formatChineseDate(''), '');
    });
  });
}
