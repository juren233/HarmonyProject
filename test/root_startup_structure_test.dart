import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('root shell defers heavy tab prewarm until after first frame', () {
    final source = File('lib/app/petnote_root.dart').readAsStringSync();

    expect(source.contains('IndexedStack('), isTrue);
    expect(source.contains('_queueDeferredTabPrewarm();'), isTrue);
    expect(source.contains('WidgetsBinding.instance.addPostFrameCallback'),
        isTrue);
    expect(source.contains('_prewarmPersistentTabs()'), isTrue);
    expect(
        source
            .contains('Future<void>.delayed(const Duration(milliseconds: 48))'),
        isTrue);
    expect(source.contains('_maxDeferredPrewarmTabCount = 1'), isTrue);
    expect(source.contains('prewarmedCount >= _maxDeferredPrewarmTabCount'),
        isTrue);
    expect(source.contains('AppTab.overview,'), isTrue);
    expect(source.contains('AppTab.pets,'), isTrue);
  });
}
