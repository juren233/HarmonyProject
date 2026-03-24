import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_care_harmony/app/pet_care_app.dart';

void main() {
  testWidgets('renders HyperOS style checklist shell and can switch to overview', (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    expect(find.text('清单'), findsWidgets);
    expect(find.text('总览'), findsOneWidget);
    expect(find.text('爱宠'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('今天 2 项待处理'), findsOneWidget);
    expect(find.text('今日待办'), findsOneWidget);
    expect(find.text('即将到期'), findsOneWidget);
    expect(find.text('已逾期'), findsOneWidget);

    await tester.tap(find.text('总览'));
    await tester.pumpAndSettle();

    expect(find.text('AI 照护总结'), findsOneWidget);
  });

  testWidgets('opens HyperOS style add sheet with four primary actions', (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('选择新内容'), findsOneWidget);
    expect(find.text('新增待办'), findsOneWidget);
    expect(find.text('新增提醒'), findsOneWidget);
    expect(find.text('新增记录'), findsOneWidget);
    expect(find.text('新增爱宠'), findsOneWidget);
  });

  testWidgets('uses immersive dock with compact centered add button', (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('bottom_nav_blur')), findsOneWidget);
    expect(tester.widget(find.byKey(const ValueKey('bottom_nav_blur'))), isA<BackdropFilter>());
    expect(find.byKey(const ValueKey('dock_add_button')), findsOneWidget);

    final addButtonSize = tester.getSize(find.byKey(const ValueKey('dock_add_button')));
    expect(addButtonSize.width, lessThanOrEqualTo(60));
    expect(addButtonSize.height, lessThanOrEqualTo(60));
  });

  testWidgets('configures transparent immersive status bar wrapper', (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    final annotated = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(annotated.value.statusBarColor, const Color(0x00000000));
  });

  testWidgets('uses explicit insets instead of nested SafeArea wrappers', (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    expect(find.byType(SafeArea), findsNothing);
  });
}
