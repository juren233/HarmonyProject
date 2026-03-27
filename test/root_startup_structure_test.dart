import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('root shell avoids eager IndexedStack tab construction on startup', () {
    final source = File('lib/app/pet_care_root.dart').readAsStringSync();

    expect(source.contains('IndexedStack('), isFalse);
    expect(source.contains('final activeTab = store.activeTab;'), isTrue);
    expect(source.contains('switch (activeTab)'), isTrue);
    expect(source.contains('PetFirstLaunchIntro('), isTrue);
  });
}
