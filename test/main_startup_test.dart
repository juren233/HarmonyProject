import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main startup does not await system ui configuration before runApp', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source.contains('Future<void> main() async'), isFalse);
    expect(source.contains('await configureStartupSystemUi()'), isFalse);
    expect(source.contains('configureStartupSystemUi();'), isTrue);
    expect(source.contains('lockAppToPortrait();'), isTrue);
    expect(source.contains('AppVersionInfo.load().then('), isTrue);
    expect(source.contains('(appVersionInfo) {'), isTrue);
    expect(
      source.contains('runApp(_OhosRecoveryGuard('),
      isTrue,
    );
    expect(source.contains('appVersionInfo: appVersionInfo'), isTrue);
  });
}
