// 错误落盘通道（error_sink）的回归测试。
//
// 背景（V2.28.1 测试补空白）：error_sink 是"完善日志"体系的入口——models 层
// 加载丢数据时的告警、各服务的错误留痕都从这里上报，此前却没有任何测试。
// 它有三条必须守住的契约：
//   1. 未注入实现时调用**绝不抛异常**（纯 Dart 单测/插件脚本环境没有日志通道）；
//   2. 注入后 tag/错误/堆栈/场景说明**完整送达**（日志上下文缺一不可）；
//   3. 日志通道自身出错**绝不影响主流程**（写日志失败不能把业务炸了）。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/utils/error_sink.dart';

void main() {
  tearDown(() {
    // _sink 是全局状态：每个用例结束后注入空实现复位，避免影响其他测试文件。
    setErrorSink((tag, error, stack, {context}) {});
  });

  test('未注入实现时上报错误：静默返回，绝不抛异常', () {
    // 不调用 setErrorSink，模拟"纯 Dart 环境/尚未 installErrorLog"。
    expect(
      () => reportError('test_tag', StateError('未注入也要安静')),
      returnsNormally,
    );
  });

  test('注入后上报：tag / 错误对象 / 堆栈 / 场景说明完整送达', () {
    String? gotTag;
    Object? gotError;
    StackTrace? gotStack;
    String? gotContext;
    setErrorSink((tag, error, stack, {context}) {
      gotTag = tag;
      gotError = error;
      gotStack = stack;
      gotContext = context;
    });

    final stack = StackTrace.current;
    final error = StateError('加载时丢了一条记录');
    reportError('app_data', error, stack, '加载数据：解析记录');

    expect(gotTag, 'app_data');
    expect(gotError, same(error), reason: '送达的必须是同一个错误对象');
    expect(gotStack, same(stack));
    expect(gotContext, '加载数据：解析记录');
  });

  test('堆栈与场景说明可省略（以 null 送达，不强制调用方拼参数）', () {
    StackTrace? gotStack;
    String? gotContext;
    setErrorSink((tag, error, stack, {context}) {
      gotStack = stack;
      gotContext = context;
    });

    reportError('storage_service', '简写上报');
    expect(gotStack, isNull);
    expect(gotContext, isNull);
  });

  test('日志通道自身抛异常：被吞掉，绝不波及主流程', () {
    setErrorSink((tag, error, stack, {context}) {
      throw StateError('磁盘满了写不进去——日志通道自己的问题');
    });

    // 主流程照常继续，这一行不抛即为通过。
    expect(
      () => reportError('storage_service', StateError('业务错误')),
      returnsNormally,
    );
  });

  test('重复注入：后注入的实现生效（启动时 installErrorLog 覆盖旧通道）', () {
    var firstCalls = 0;
    var secondCalls = 0;
    setErrorSink((tag, error, stack, {context}) => firstCalls++);
    setErrorSink((tag, error, stack, {context}) => secondCalls++);

    reportError('tag', 'x');
    expect(firstCalls, 0, reason: '旧通道不应再被调用');
    expect(secondCalls, 1);
  });
}
