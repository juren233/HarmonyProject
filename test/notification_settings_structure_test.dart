import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'ios notification settings opening prioritizes app notification settings and falls back safely',
      () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final openSettingsSection = source.substring(
      source.indexOf('private func openSettings('),
      source.indexOf('private func permissionLabel'),
    );

    expect(openSettingsSection,
        contains('UIApplication.openNotificationSettingsURLString'));
    expect(openSettingsSection,
        contains('UIApplicationOpenNotificationSettingsURLString'));
    expect(
        openSettingsSection, contains('UIApplication.openSettingsURLString'));
    expect(
      openSettingsSection,
      contains(
          'UIApplication.shared.open(url, options: [:], completionHandler:'),
    );
    expect(openSettingsSection, contains('if #available(iOS 16.0, *)'));
    expect(openSettingsSection, contains('else if #available(iOS 15.4, *)'));
  });
}
