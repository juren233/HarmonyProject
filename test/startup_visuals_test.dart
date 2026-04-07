import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('android startup background is not plain white', () async {
    final launchBackground =
        File('android/app/src/main/res/drawable/launch_background.xml')
            .readAsStringSync();
    final launchBackgroundV21 =
        File('android/app/src/main/res/drawable-v21/launch_background.xml')
            .readAsStringSync();
    final styles =
        File('android/app/src/main/res/values/styles.xml').readAsStringSync();

    expect(launchBackground.contains('@android:color/white'), isFalse);
    expect(launchBackground.contains('@color/splash_background'), isTrue);
    expect(launchBackgroundV21.contains('@color/splash_background'), isTrue);
    expect(styles.contains('@color/splash_background'), isTrue);
    expect(launchBackground.contains('@mipmap/ic_launcher'), isFalse);
    expect(launchBackgroundV21.contains('@mipmap/ic_launcher'), isFalse);
  });

  test('harmony start window background is not plain white', () async {
    final jsonText =
        File('ohos/entry/src/main/resources/base/element/color.json')
            .readAsStringSync();
    final moduleText =
        File('ohos/entry/src/main/module.json5').readAsStringSync();
    final data = jsonDecode(jsonText) as Map<String, dynamic>;
    final colors = (data['color'] as List).cast<Map<String, dynamic>>();
    final startWindow = colors
        .firstWhere((entry) => entry['name'] == 'start_window_background');

    expect(startWindow['value'], isNot('#FFFFFF'));
    expect(
        moduleText.contains('"startWindowIcon": "\$media:start_window_blank"'),
        isTrue);
  });
}
