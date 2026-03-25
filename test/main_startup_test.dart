import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main startup does not await system ui configuration before runApp', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source.contains('Future<void> main() async'), isFalse);
    expect(source.contains('await configureStartupSystemUi()'), isFalse);
    expect(source.contains('configureStartupSystemUi();'), isTrue);
  });
}
