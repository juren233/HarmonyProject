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
    expect(find.byKey(const ValueKey('bottom_nav_panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock_add_button')), findsOneWidget);

    final addButtonSize = tester.getSize(find.byKey(const ValueKey('dock_add_button')));
    expect(addButtonSize.width, lessThanOrEqualTo(60));
    expect(addButtonSize.height, lessThanOrEqualTo(60));

    final panelRect = tester.getRect(find.byKey(const ValueKey('bottom_nav_panel')));
    final addButtonRect = tester.getRect(find.byKey(const ValueKey('dock_add_button')));
    expect((panelRect.center.dx - addButtonRect.center.dx).abs(), lessThanOrEqualTo(0.5));
    expect(addButtonRect.top, greaterThanOrEqualTo(panelRect.top));
    expect(addButtonRect.bottom, lessThanOrEqualTo(panelRect.bottom));
  });

  testWidgets('keeps blur only on the bottom dock and not on content panels', (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom_nav_blur')), findsOneWidget);
  });

  testWidgets('uses the warm pet orange theme for primary actions', (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold));
    final theme = Theme.of(context);
    expect(theme.colorScheme.primary, const Color(0xFFF2A65A));

    final filledStyle = theme.filledButtonTheme.style!;
    expect(filledStyle.backgroundColor!.resolve({}), const Color(0xFFF2A65A));

    final plusDecoratedBox = tester.widget<DecoratedBox>(
      find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    final decoration = plusDecoratedBox.decoration as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors.first, const Color(0xFF90CE9B));
    expect(gradient.colors.last, const Color(0xFF6AB57A));
  });

  testWidgets('keeps informational highlight cards on the cooler accent palette', (tester) async {
    await tester.pumpWidget(const PetCareApp());
    await tester.pumpAndSettle();

    final coolAccentCards = find.byWidgetPredicate((widget) {
      if (widget is! Container) {
        return false;
      }
      final decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.color == const Color(0xFFEAF0FF);
    });

    expect(coolAccentCards, findsWidgets);
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
