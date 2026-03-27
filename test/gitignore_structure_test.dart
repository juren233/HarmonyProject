import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gitignore excludes local intro debug output', () {
    final source = File('.gitignore').readAsStringSync();

    expect(source.contains('debug_intro_output.txt'), isTrue);
  });
}
