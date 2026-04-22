import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification and photo flows share reusable permission gate foundation',
      () {
    final permissionGateSource =
        File('lib/permissions/permission_request_gate.dart').readAsStringSync();
    final notificationCoordinatorSource =
        File('lib/notifications/notification_coordinator.dart')
            .readAsStringSync();
    final photoPickerSource =
        File('lib/app/native_pet_photo_picker.dart').readAsStringSync();

    expect(permissionGateSource, contains('class PermissionRequestGate<T>'));
    expect(permissionGateSource, contains('requestOrOpenSettings'));
    expect(permissionGateSource,
        contains('shouldOpenSettingsForPermissionRequest'));
    expect(notificationCoordinatorSource,
        contains('PermissionRequestGate<NotificationPermissionState>'));
    expect(photoPickerSource, contains('MethodChannelNativePetPhotoPicker'));
    expect(photoPickerSource,
        isNot(contains('notification_permission_prompt_handled_v1')));
  });
}
