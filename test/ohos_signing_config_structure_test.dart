import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OHOS build profile keeps encrypted signing secrets configured',
      () async {
    final profile = File('ohos/build-profile.json5').readAsStringSync();

    expect(
      RegExp(r'"storePassword"\s*:\s*"[^"]+"').hasMatch(profile),
      isTrue,
    );
    expect(
      RegExp(r'"keyPassword"\s*:\s*"[^"]+"').hasMatch(profile),
      isTrue,
    );
    expect(profile.contains('"storeFile": "./sign/OpenHarmony.p12"'), isTrue);
    expect(profile.contains('"profile": "./sign/debug-profile.p7b"'), isTrue);
  });

  test('OHOS signing profile bundle-name matches app bundleName', () {
    final appJson = jsonDecode(
      File('ohos/AppScope/app.json5').readAsStringSync(),
    ) as Map<String, dynamic>;
    final profileJson = jsonDecode(
      File('ohos/sign/debug-profile.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    final appBundleName = (appJson['app'] as Map<String, dynamic>)['bundleName'];
    final signingBundleName =
        (profileJson['bundle-info'] as Map<String, dynamic>)['bundle-name'];

    expect(signingBundleName, appBundleName);
  });
}
