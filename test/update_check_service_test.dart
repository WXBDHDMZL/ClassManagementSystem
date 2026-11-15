// 启动检查更新的状态流转：有可用版本、已是最新、检查失败三种情况。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/github_update_service.dart';
import 'package:class_management_system/services/update_check_service.dart';

GitHubReleaseInfo _release(String tag) => GitHubReleaseInfo(
  tagName: tag,
  title: tag,
  notes: '',
  assets: const [],
);

void main() {
  tearDown(UpdateCheckService.resetForTest);

  test('发现更高版本时记录到 availableRelease', () async {
    final release = _release('V99.0.0');
    final result = await UpdateCheckService.checkInBackground(
      fetch: () async => release,
    );

    expect(result, same(release));
    expect(UpdateCheckService.availableRelease.value, same(release));
  });

  test('已是最新时清空 availableRelease', () async {
    UpdateCheckService.availableRelease.value = _release('V99.0.0');

    final result = await UpdateCheckService.checkInBackground(
      fetch: () async => _release('V0.0.1'),
    );

    expect(result, isNull);
    expect(UpdateCheckService.availableRelease.value, isNull);
  });

  test('检查失败时静默返回 null', () async {
    final result = await UpdateCheckService.checkInBackground(
      fetch: () async => throw const GitHubUpdateException('网络不可用'),
    );

    expect(result, isNull);
    expect(UpdateCheckService.availableRelease.value, isNull);
  });
}
