import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/petnote_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Android 任务卡片标题与中文应用名保持一致', (tester) async {
    await tester.pumpWidget(const PetNoteApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, '宠记');
  });
}
