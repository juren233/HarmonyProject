import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final rootSource = File('lib/app/petnote_root.dart').readAsStringSync();
  final widgetsSource = File('lib/app/common_widgets.dart').readAsStringSync();
  final pagesSource = File('lib/app/petnote_pages.dart').readAsStringSync();
  final frostedPanelSection = widgetsSource.substring(
    widgetsSource.indexOf('class FrostedPanel'),
    widgetsSource.indexOf('class HeroPanel'),
  );
  final segmentedControlSection = widgetsSource.substring(
    widgetsSource.indexOf('class HyperSegmentedControl'),
    widgetsSource.indexOf('class SectionCard'),
  );
  final petsPageSelectionSection = pagesSource.substring(
    pagesSource.indexOf('class PetsPage'),
    pagesSource.indexOf('class MePage'),
  );

  test('isolates page content and bottom navigation behind repaint boundaries',
      () {
    expect(rootSource, contains("ValueKey('page_content_boundary')"));
    expect(rootSource, contains("ValueKey('bottom_nav_boundary')"));
  });

  test('routes dock chrome through overlay and bar handoff during transitions',
      () {
    expect(rootSource, contains('final showBottomNavigationInBody ='));
    expect(rootSource, contains('bottomNavigationOverlay:'));
    expect(
      rootSource,
      contains('showBottomNavigationInBody ? bottomNavigation : null'),
    );
    expect(rootSource, contains('bottomNavigationBar:'));
    expect(
      rootSource,
      contains('showBottomNavigationInBody ? null : bottomNavigation'),
    );
    expect(rootSource, contains('supportsIosNativeDock(Theme.of(context).platform)'));
  });

  test('wraps frosted panels in repaint boundaries for scroll reuse', () {
    expect(frostedPanelSection, contains('return RepaintBoundary('));
  });

  test('avoids extra clipping layers inside frosted panels', () {
    expect(frostedPanelSection, isNot(contains('ClipRRect(')));
  });

  test('selected buttons do not add extra elevation shadows', () {
    expect(segmentedControlSection,
        isNot(contains('boxShadow: selectedKey == item.key')));
    expect(petsPageSelectionSection, isNot(contains('boxShadow: selected')));
  });
}
