import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared IDE run configuration disables icon tree shaking', () {
    final source = File('.run/main.dart.run.xml').readAsStringSync();

    expect(source.contains('FlutterRunConfigurationType'), isTrue);
    expect(source.contains('name="additionalArgs"'), isTrue);
    expect(source.contains('--no-tree-shake-icons'), isTrue);
    expect(source.contains(r'$PROJECT_DIR$/lib/main.dart'), isTrue);
  });

  test('DevEco workspace keeps the Flutter run target selected by default', () {
    final source = File('ohos/.idea/workspace.xml').readAsStringSync();

    expect(source.contains('selected="Flutter.main.dart"'), isTrue);
    expect(
      source.contains(
        '<configuration name="entry" type="OhosDebugTask" factoryName="OpenHarmony App">',
      ),
      isTrue,
    );
  });
}
