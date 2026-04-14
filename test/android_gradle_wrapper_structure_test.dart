import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows Gradle wrapper falls back to PATH java when JAVA_HOME is invalid', () {
    final source = File('android/gradlew.bat').readAsStringSync();

    expect(source.contains(':findJavaFromKnownLocations'), isTrue);
    expect(source.contains('STUDIO_JDK'), isTrue);
    expect(source.contains(r"$env:DEVECO_HOME 'jbr'"), isTrue);
    expect(source.contains('jlink.exe'), isTrue);
    expect(source.contains('powershell -NoProfile'), isTrue);
    expect(source.contains(':findJavaFromPath'), isTrue);
    expect(
      source.contains('WARNING: JAVA_HOME points to an invalid directory'),
      isTrue,
    );
    expect(
      source.contains('goto findJavaFromPath'),
      isTrue,
    );
  });

  test('Unix Gradle wrapper falls back to PATH java when JAVA_HOME is invalid', () {
    final source = File('android/gradlew').readAsStringSync();

    expect(
      source.contains('WARNING: JAVA_HOME points to an invalid directory'),
      isTrue,
    );
    expect(
      source.contains('JAVACMD="java"'),
      isTrue,
    );
  });
}
