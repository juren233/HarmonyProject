import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'ios native dock view configures transparent non-opaque container layers',
      () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(source.contains('rootView.backgroundColor = .clear'), isTrue);
    expect(source.contains('rootView.isOpaque = false'), isTrue);
    expect(source.contains('controllerView.backgroundColor = .clear'), isTrue);
    expect(source.contains('controllerView.isOpaque = false'), isTrue);
    expect(source.contains('tabBar.backgroundColor = .clear'), isTrue);
    expect(source.contains('tabBar.isOpaque = false'), isTrue);
  });
}
