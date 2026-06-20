import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/interaction_haptics.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(
    PetNoteStore store, {
    InteractionHapticsDriver? interactionHapticsDriver,
  }) =>
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            return Scaffold(
              body: PetsPage(
                store: store,
                onAddFirstPet: () {},
                onEditPet: (_) {},
                interactionHapticsDriver: interactionHapticsDriver,
              ),
            );
          },
        ),
      );

  testWidgets('无宠物显示添加引导副标题', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    addTearDown(store.dispose);

    await tester.pumpWidget(host(store));

    expect(find.text('添加宠物就有照护档案啦'), findsOneWidget);
  });

  testWidgets('一只宠物显示它的照护档案', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    addTearDown(store.dispose);
    await store.addPet(
      name: 'Mochi',
      type: PetType.cat,
      breed: '英短',
      sex: '妹妹',
      birthday: '2024-01-01',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '少量多餐',
      allergies: '无',
      note: '活泼',
    );

    await tester.pumpWidget(host(store));

    expect(find.text('它的照护档案'), findsOneWidget);
  });

  testWidgets('多只宠物显示它们的照护档案', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);

    await tester.pumpWidget(host(store));

    expect(find.text('它们的照护档案'), findsOneWidget);
  });

  testWidgets('长按宠物卡片二次确认后删除爱宠', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    addTearDown(store.dispose);
    await store.addPet(
      name: 'Mochi',
      type: PetType.cat,
      breed: '英短',
      sex: '妹妹',
      birthday: '2024-01-01',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '少量多餐',
      allergies: '无',
      note: '活泼',
    );
    final haptics = _RecordingInteractionHapticsDriver();

    await tester.pumpWidget(host(
      store,
      interactionHapticsDriver: haptics,
    ));
    final cardKey = ValueKey('pet-selector-card-${store.pets.single.id}');
    final gesture = await tester.startGesture(tester.getCenter(
      find.byKey(cardKey),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(haptics.calls, ['ramp:560']);

    expect(find.text('删除「Mochi」？'), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(haptics.calls, ['ramp:560', 'stop']);

    expect(find.text('删除「Mochi」？'), findsNothing);
    final cancelledProgress = tester.widget<FractionallySizedBox>(
      find.byKey(
          ValueKey('pet-selector-hold-progress-${store.pets.single.id}')),
    );
    expect(cancelledProgress.widthFactor, 0);

    final movedGesture = await tester.startGesture(tester.getCenter(
      find.byKey(cardKey),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await movedGesture.moveBy(const Offset(18, 0));
    await tester.pump(const Duration(milliseconds: 430));
    await movedGesture.up();
    await tester.pumpAndSettle();

    expect(find.text('删除「Mochi」？'), findsNothing);
    expect(haptics.calls, ['ramp:560', 'stop', 'ramp:560', 'stop']);

    final completedGesture = await tester.startGesture(tester.getCenter(
      find.byKey(cardKey),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));

    final progress = tester.widget<FractionallySizedBox>(
      find.byKey(
          ValueKey('pet-selector-hold-progress-${store.pets.single.id}')),
    );
    expect(progress.widthFactor, greaterThan(0));
    expect(progress.widthFactor, lessThan(1));

    await tester.pump(const Duration(milliseconds: 320));
    await completedGesture.up();
    await tester.pumpAndSettle();

    expect(find.text('删除「Mochi」？'), findsOneWidget);
    expect(haptics.calls, [
      'ramp:560',
      'stop',
      'ramp:560',
      'stop',
      'ramp:560',
      'stop',
      'confirm',
    ]);
    expect(find.text('确认删除'), findsOneWidget);
    final barriers = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier));
    final deleteBarrier = barriers.firstWhere(
      (barrier) => barrier.color == Colors.black54,
    );
    expect(deleteBarrier.color?.a, lessThan(1));
    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(
      dialog.backgroundColor,
      lightPetNoteTokens.panelStrongBackground.withValues(alpha: 1),
    );
    expect(dialog.backgroundColor?.a, 1);
    final dialogMaterial = tester.widget<Material>(
      find.byKey(const ValueKey('delete-pet-dialog-surface')),
    );
    expect(
      dialogMaterial.color,
      lightPetNoteTokens.panelStrongBackground.withValues(alpha: 1),
    );
    expect(dialogMaterial.color?.a, 1);
    final infoPanel = tester.widget<Container>(
      find.byKey(const ValueKey('delete-pet-dialog-info-panel')),
    );
    final infoDecoration = infoPanel.decoration as BoxDecoration?;
    expect(
      infoDecoration?.color,
      lightPetNoteTokens.panelStrongBackground.withValues(alpha: 1),
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.pets, hasLength(1));

    final confirmGesture = await tester.startGesture(tester.getCenter(
      find.byKey(cardKey),
    ));
    await tester.pump(const Duration(milliseconds: 620));
    await confirmGesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();

    expect(store.pets, isEmpty);
    expect(find.text('先添加第一只爱宠'), findsOneWidget);
  });

  testWidgets('长按完成后先停止渐强震动再触发确认震动', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    addTearDown(store.dispose);
    await store.addPet(
      name: 'Mochi',
      type: PetType.cat,
      breed: '英短',
      sex: '妹妹',
      birthday: '2024-01-01',
      weightKg: 4.2,
      neuterStatus: PetNeuterStatus.neutered,
      feedingPreferences: '少量多餐',
      allergies: '无',
      note: '活泼',
    );
    final haptics = _RecordingInteractionHapticsDriver(
      stopCompleter: Completer<void>(),
    );

    await tester.pumpWidget(host(
      store,
      interactionHapticsDriver: haptics,
    ));
    final cardKey = ValueKey('pet-selector-card-${store.pets.single.id}');
    final gesture = await tester.startGesture(tester.getCenter(
      find.byKey(cardKey),
    ));
    await tester.pump(const Duration(milliseconds: 620));

    expect(find.text('删除「Mochi」？'), findsOneWidget);
    expect(haptics.calls, ['ramp:560', 'stop']);

    haptics.stopCompleter!.complete();
    await tester.pump();
    await gesture.up();

    expect(haptics.calls, ['ramp:560', 'stop', 'confirm']);
  });
}

class _RecordingInteractionHapticsDriver implements InteractionHapticsDriver {
  _RecordingInteractionHapticsDriver({this.stopCompleter});

  final List<String> calls = [];
  final Completer<void>? stopCompleter;

  @override
  Future<void> playDeleteHoldRamp({required int durationMs}) async {
    calls.add('ramp:$durationMs');
  }

  @override
  Future<void> stopDeleteHoldRamp() async {
    calls.add('stop');
    await stopCompleter?.future;
  }

  @override
  Future<void> playDeleteConfirmImpact() async {
    calls.add('confirm');
  }
}
