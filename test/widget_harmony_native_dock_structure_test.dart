import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OHOS floating dock keeps the Flutter add button visual tokens aligned',
      () {
    final source = File(
      'ohos/entry/src/main/ets/plugins/PetNoteHarmonyNativeDockPlugin.ets',
    ).readAsStringSync();

    expect(source.contains("'#90CE9B'"), isTrue);
    expect(source.contains("'#6AB57A'"), isTrue);
    expect(source.contains("'#73B87F'"), isTrue);
    expect(source.contains("'#528F63'"), isTrue);
    expect(source.contains("'#7E8492'"), isTrue);
    expect(source.contains("'#A1A8B4'"), isTrue);
  });
}
