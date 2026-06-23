import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/pet_device_home.dart';
import 'package:petnote/platform/device_keep_alive.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('宠物端入口销毁时不关闭外部共享 store 的同步 mutation 流', (tester) async {
    final settings = await AppSettingsController.load();
    await settings.setDeviceRole(DeviceRole.pet);
    final store = PetNoteStore.seeded();
    addTearDown(() {
      settings.dispose();
      try {
        store.dispose();
      } catch (_) {}
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: PetDeviceHome(
          settingsController: settings,
          storeLoader: () async => store,
          keepAlive: _NoopDeviceKeepAlive(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 64));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    Object? mutationError;
    try {
      await store.addTodo(
        title: '更新重建后待办',
        petId: store.pets.first.id,
        dueAt: DateTime.utc(2026, 6, 24, 10),
        note: '',
      );
    } catch (error) {
      mutationError = error;
    }

    expect(mutationError, isNull);
    expect(
      store.pendingLocalMutations
          .where((mutation) => mutation.entityType == PetNoteEntityType.todo)
          .length,
      1,
    );
  });

  test('PetNoteApp 复用应用级 store 避免角色入口重复加载', () {
    final source = File('lib/app/petnote_app.dart').readAsStringSync();

    expect(source, contains('PetNoteStore? _appStore;'));
    expect(source, contains('Future<PetNoteStore>? _storeLoadTask;'));
    expect(source, contains('final existingStore = _appStore;'));
    expect(
        source, contains('return Future<PetNoteStore>.value(existingStore);'));
    expect(source, isNot(contains('_preloadedStore = null')));
  });
}

class _NoopDeviceKeepAlive extends DeviceKeepAlive {
  @override
  Future<void> setKeepScreenOn(bool enabled) async {}

  @override
  Future<void> startBackgroundKeepAlive() async {}

  @override
  Future<void> stopBackgroundKeepAlive() async {}
}
