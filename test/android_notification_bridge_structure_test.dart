import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('android notification permission treats cancelled request as unhandled prompt', () {
    final source = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/PetNoteNotificationBridge.kt',
    ).readAsStringSync();

    expect(source, contains('val promptHandled = grantResults.isNotEmpty()'));
    expect(source, contains('permissionRequestResult(state, promptHandled)'));
    expect(
      source,
      isNot(contains('permissionRequestResult(if (granted) "authorized" else "denied", true)')),
    );
  });
}
