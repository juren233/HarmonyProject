import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/permissions/permission_request_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _FakePermissionState { unknown, denied, granted, unsupported }

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('未真实处理系统弹窗时继续保留申请权限路径', () async {
    var requestCount = 0;
    var settingsCount = 0;
    final gate = _fakeGate(
      requestPermission: () async {
        requestCount += 1;
        return const PermissionRequestOutcome(
          state: _FakePermissionState.denied,
          promptHandledSystemDialog: false,
        );
      },
      openPermissionSettings: () async {
        settingsCount += 1;
      },
    );

    await gate.load();

    final result =
        await gate.requestOrOpenSettings(_FakePermissionState.denied);

    expect(result, _FakePermissionState.denied);
    expect(gate.hasHandledPermissionPrompt, isFalse);
    expect(gate.shouldOpenSettingsForPermissionRequest(result), isFalse);
    expect(requestCount, 1);
    expect(settingsCount, 0);
  });

  test('真实处理过系统弹窗后后续改为跳设置', () async {
    SharedPreferences.setMockInitialValues({
      'test_permission_prompt_handled': true,
    });
    var requestCount = 0;
    var settingsCount = 0;
    final gate = _fakeGate(
      requestPermission: () async {
        requestCount += 1;
        return const PermissionRequestOutcome(
          state: _FakePermissionState.granted,
          promptHandledSystemDialog: true,
        );
      },
      openPermissionSettings: () async {
        settingsCount += 1;
      },
    );

    await gate.load();

    final result =
        await gate.requestOrOpenSettings(_FakePermissionState.denied);

    expect(result, _FakePermissionState.denied);
    expect(requestCount, 0);
    expect(settingsCount, 1);
  });

  test('已授权状态不会重复申请或跳设置', () async {
    var requestCount = 0;
    var settingsCount = 0;
    final gate = _fakeGate(
      requestPermission: () async {
        requestCount += 1;
        return const PermissionRequestOutcome(
          state: _FakePermissionState.denied,
          promptHandledSystemDialog: true,
        );
      },
      openPermissionSettings: () async {
        settingsCount += 1;
      },
    );

    await gate.load();

    final result =
        await gate.requestOrOpenSettings(_FakePermissionState.granted);

    expect(result, _FakePermissionState.granted);
    expect(requestCount, 0);
    expect(settingsCount, 0);
  });

  test('真实处理后拿到拒绝结果会被记为已处理', () async {
    final gate = _fakeGate(
      requestPermission: () async => const PermissionRequestOutcome(
        state: _FakePermissionState.denied,
        promptHandledSystemDialog: true,
      ),
      openPermissionSettings: () async {},
    );

    await gate.load();

    final result =
        await gate.requestOrOpenSettings(_FakePermissionState.denied);

    expect(result, _FakePermissionState.denied);
    expect(gate.hasHandledPermissionPrompt, isTrue);
    expect(gate.shouldOpenSettingsForPermissionRequest(result), isTrue);
  });

  test('不同权限使用独立存储键且复用同一套门控策略', () async {
    final notificationGate = _fakeGate(
      storageKey: 'notification_permission_prompt_handled',
      requestPermission: () async => const PermissionRequestOutcome(
        state: _FakePermissionState.denied,
        promptHandledSystemDialog: true,
      ),
      openPermissionSettings: () async {},
    );
    final photoGate = _fakeGate(
      storageKey: 'photo_permission_prompt_handled',
      requestPermission: () async => const PermissionRequestOutcome(
        state: _FakePermissionState.denied,
        promptHandledSystemDialog: false,
      ),
      openPermissionSettings: () async {},
    );

    await notificationGate.load();
    await photoGate.load();

    await notificationGate.requestOrOpenSettings(_FakePermissionState.denied);
    await photoGate.requestOrOpenSettings(_FakePermissionState.denied);

    expect(notificationGate.hasHandledPermissionPrompt, isTrue);
    expect(photoGate.hasHandledPermissionPrompt, isFalse);
    expect(
      notificationGate.shouldOpenSettingsForPermissionRequest(
        _FakePermissionState.denied,
      ),
      isTrue,
    );
    expect(
      photoGate.shouldOpenSettingsForPermissionRequest(
        _FakePermissionState.denied,
      ),
      isFalse,
    );
  });

  test('偏好读取超时时按未处理系统弹窗降级', () async {
    final gate = _fakeGate(
      requestPermission: () async => const PermissionRequestOutcome(
        state: _FakePermissionState.denied,
        promptHandledSystemDialog: false,
      ),
      openPermissionSettings: () async {},
      preferencesLoader: () => Completer<SharedPreferences>().future,
    );

    await gate.load();

    expect(gate.hasHandledPermissionPrompt, isFalse);
    expect(
      gate.shouldOpenSettingsForPermissionRequest(_FakePermissionState.denied),
      isFalse,
    );
  });
}

PermissionRequestGate<_FakePermissionState> _fakeGate({
  String storageKey = 'test_permission_prompt_handled',
  required Future<PermissionRequestOutcome<_FakePermissionState>> Function()
      requestPermission,
  required Future<void> Function() openPermissionSettings,
  Future<SharedPreferences> Function()? preferencesLoader,
}) {
  return PermissionRequestGate<_FakePermissionState>(
    promptHandledStorageKey: storageKey,
    isGranted: (state) => state == _FakePermissionState.granted,
    requestPermission: requestPermission,
    openPermissionSettings: openPermissionSettings,
    preferencesLoader: preferencesLoader,
  );
}
