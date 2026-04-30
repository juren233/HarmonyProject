import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/petnote_app.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Android 任务卡片标题与中文应用名保持一致', (tester) async {
    final store = await PetNoteStore.load(
      storage: PetNoteLocalStorage.memory(),
    );

    await tester.pumpWidget(
      PetNoteApp(
        storeLoader: () async => store,
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, '宠记');
  });
}
