import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/navigation_palette.dart';
import 'package:petnote/state/petnote_store.dart';

void main() {
  testWidgets('uses the dark-mode tab accent palette in light mode',
      (tester) async {
    late BuildContext lightContext;
    late BuildContext darkContext;

    await tester.pumpWidget(
      Column(
        children: [
          Expanded(
            child: MaterialApp(
              theme: buildPetNoteTheme(Brightness.light),
              home: Builder(
                builder: (innerContext) {
                  lightContext = innerContext;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          Expanded(
            child: MaterialApp(
              theme: buildPetNoteTheme(Brightness.dark),
              home: Builder(
                builder: (innerContext) {
                  darkContext = innerContext;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ],
      ),
    );

    expect(
      tabAccentFor(lightContext, AppTab.checklist),
      tabAccentFor(darkContext, AppTab.checklist),
    );
    expect(
      tabAccentFor(lightContext, AppTab.overview),
      const NavigationAccent(Color(0xFF9B84E8), Color(0xFF9B84E8)),
    );
    expect(
      tabAccentFor(lightContext, AppTab.pets),
      const NavigationAccent(Color(0xFFFFA79B), Color(0xFFFFA79B)),
    );
    expect(
      tabAccentFor(lightContext, AppTab.me),
      const NavigationAccent(Color(0xFFA5C6FF), Color(0xFFA5C6FF)),
    );
    expect(
      tabAccentFor(darkContext, AppTab.overview),
      tabAccentFor(lightContext, AppTab.overview),
    );
    expect(
      tabAccentFor(darkContext, AppTab.pets),
      tabAccentFor(lightContext, AppTab.pets),
    );
    expect(
      tabAccentFor(darkContext, AppTab.me),
      tabAccentFor(lightContext, AppTab.me),
    );
  });

  testWidgets('keeps the add button palette outside tab accent mapping',
      (tester) async {
    late BuildContext context;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
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
  });
}
