import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OHOS init script resolves DevEco tools from configurable locations', () {
    final script = File('scripts/flutter-ohos.ps1').readAsStringSync();

    expect(script.contains(r'$env:DEVECO_HOME'), isTrue);
    expect(script.contains(r'$env:HARMONY_TOOLCHAIN_HOME'), isTrue);
    expect(
      script.contains("Get-OptionalCommandDirectory -Candidates @('ohpm.cmd', 'ohpm')"),
      isTrue,
    );
    expect(
      script.contains(
        "Get-OptionalCommandDirectory -Candidates @('hvigorw.bat', 'hvigorw')",
      ),
      isTrue,
    );
    expect(
      script.contains(r"'E:\Huawei\DevEco Studio\tools\ohpm\bin'"),
      isFalse,
    );
    expect(
      script.contains(r"'E:\Huawei\DevEco Studio\tools\hvigor\bin'"),
      isFalse,
    );
    expect(
      script.contains(r"'E:\Huawei\DevEco Studio\tools\node'"),
      isFalse,
    );
  });
}
