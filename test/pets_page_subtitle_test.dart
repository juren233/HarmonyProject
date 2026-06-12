import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(PetNoteStore store) => MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: PetsPage(
            store: store,
            onAddFirstPet: () {},
            onEditPet: (_) {},
          ),
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
}
