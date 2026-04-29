import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_version_info.dart';
import 'package:petnote/app/petnote_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _petsStorageKey = 'pets_v1';
const String _firstLaunchIntroAutoEnabledKey =
    'first_launch_intro_auto_enabled_v1';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(_persistedSinglePetPreferences());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      null,
    );
  });

  testWidgets('PetNoteApp 从启动注入版本信息后我的页首帧直接显示版本号', (tester) async {
    await tester.pumpWidget(
      const PetNoteApp(
        appVersionInfo: AppVersionInfo(
          version: '1.2.3',
          buildNumber: '123',
        ),
      ),
    );
    await _pumpUntilFound(tester, find.byKey(const ValueKey('tab_me')));
    await _pumpDeferredTabPrewarm(tester);

    await tester.tap(find.byKey(const ValueKey('tab_me')));
    await tester.pump();

    expect(find.text('Version 1.2.3'), findsOneWidget);
    expect(find.text('Version --'), findsNothing);
  });

  testWidgets('版本插件抛出平台异常时应用仍可完成主初始化', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => throw PlatformException(
        code: 'package_info_failure',
        message: 'boom',
      ),
    );

    await tester.pumpWidget(const PetNoteApp());
    await _pumpUntilFound(tester, find.byKey(const ValueKey('tab_overview')));
    await _pumpDeferredTabPrewarm(tester);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('tab_overview')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab_me')), findsOneWidget);
  });
}

Map<String, Object> _persistedSinglePetPreferences() {
  return {
    _firstLaunchIntroAutoEnabledKey: false,
    _petsStorageKey: jsonEncode([
      {
        'id': 'pet-1',
        'name': 'Luna',
        'avatarText': 'LU',
        'type': 'cat',
        'breed': '英短',
        'sex': '母',
        'birthday': '2024-01-15',
        'ageLabel': '新加入',
        'weightKg': 4.2,
        'neuterStatus': 'neutered',
        'feedingPreferences': '未填写',
        'allergies': '未填写',
        'note': '未填写',
      },
    ]),
  };
}

Future<void> _pumpDeferredTabPrewarm(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.pump();
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 3),
  Duration step = const Duration(milliseconds: 40),
}) async {
  var elapsed = Duration.zero;
  while (finder.evaluate().isEmpty && elapsed < timeout) {
    await tester.pump(step);
    elapsed += step;
  }
  expect(finder, findsOneWidget, reason: _visibleValueKeys(tester));
}

String _visibleValueKeys(WidgetTester tester) {
  final keys = tester.allWidgets
      .map((widget) => widget.key)
      .whereType<ValueKey<Object?>>()
      .map((key) => key.value.toString())
      .take(80)
      .join(', ');
  return '当前树上的 ValueKey：$keys';
}
