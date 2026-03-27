import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final rootSource = File('lib/app/pet_care_root.dart').readAsStringSync();
  final sheetSource = File('lib/app/add_sheet.dart').readAsStringSync();

  test(
      'add sheet relies on the system drag handle instead of rendering a duplicate one',
      () {
    expect(rootSource, contains('showDragHandle: true'));
    expect(sheetSource, isNot(contains('height: 5,')));
    expect(sheetSource, isNot(contains('const SizedBox(height: 18),')));
  });

  test('add sheet avoids default close text and unnecessary switch animations',
      () {
    expect(
      sheetSource,
      isNot(contains("child: Text(_action == AddAction.none ? '关闭' : '返回')")),
    );
    expect(sheetSource, isNot(contains('AnimatedSwitcher(')));
  });
}
