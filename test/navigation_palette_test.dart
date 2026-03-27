import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_care_harmony/app/app_theme.dart';
import 'package:pet_care_harmony/app/navigation_palette.dart';
import 'package:pet_care_harmony/state/pet_care_store.dart';

void main() {
  testWidgets('maps each bottom tab to a theme-driven accent palette',
      (tester) async {
    late BuildContext context;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetCareTheme(Brightness.light),
        home: Builder(
          builder: (innerContext) {
            context = innerContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      tabAccentFor(context, AppTab.checklist),
      const NavigationAccent(Color(0xFFF2A65A), Color(0xFFF2A65A)),
    );
    expect(
      tabAccentFor(context, AppTab.overview),
      const NavigationAccent(Color(0xFF335FCA), Color(0xFF335FCA)),
    );
    expect(
      tabAccentFor(context, AppTab.pets),
      const NavigationAccent(Color(0xFFC7533E), Color(0xFFC7533E)),
    );
    expect(
      tabAccentFor(context, AppTab.me),
      const NavigationAccent(Color(0xFF976A00), Color(0xFF976A00)),
    );
  });
}
