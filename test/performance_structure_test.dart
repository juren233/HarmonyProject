import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final rootSource = File('lib/app/petnote_root.dart').readAsStringSync();
  final widgetsSource = File('lib/app/common_widgets.dart').readAsStringSync();
  final pagesSource = File('lib/app/petnote_pages.dart').readAsStringSync();
  final overviewPageSource =
      File('lib/app/petnote_pages_overview.dart').readAsStringSync();
  final petsPageSource =
      File('lib/app/petnote_pages_pets.dart').readAsStringSync();
  final petDetailsPageSource =
      File('lib/app/petnote_pages_pets_details.dart').readAsStringSync();
  final frostedPanelSection = widgetsSource.substring(
    widgetsSource.indexOf('class FrostedPanel'),
    widgetsSource.indexOf('class HeroPanel'),
  );
  final segmentedControlSection = widgetsSource.substring(
    widgetsSource.indexOf('class HyperSegmentedControl'),
    widgetsSource.indexOf('class SectionCard'),
  );
  final petsPageSelectionSection = petsPageSource.substring(
    petsPageSource.indexOf('class PetsPage'),
  );

  test('isolates page content and bottom navigation behind repaint boundaries',
      () {
    expect(rootSource, contains("ValueKey('page_content_boundary')"));
    expect(rootSource, contains("ValueKey('bottom_nav_boundary')"));
  });

  test('routes dock chrome through overlay and bar handoff during transitions',
      () {
    expect(rootSource, contains('final showBottomNavigationInBody ='));
    expect(rootSource, contains('supportsAndroidLiquidGlassDock(platform)'));
    expect(rootSource, contains('supportsIosNativeDock(platform)'));
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
  });

  test('keeps heavy tab pages mounted behind a persistent stack host', () {
    expect(rootSource, contains('IndexedStack('));
    expect(rootSource, contains('TickerMode('));
    expect(rootSource, contains('_visitedTabs.add(activeTab);'));
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

  test('extracts shared page state presentation widgets', () {
    expect(widgetsSource, contains('class PageEmptyStateBlock'));
    expect(widgetsSource, contains('class InlineLoadingMessage'));
    expect(widgetsSource, contains('class TitledBulletGroup'));
    expect(widgetsSource, contains('class StatusListRow'));
    expect(pagesSource, contains('PageEmptyStateBlock('));
    expect(overviewPageSource, contains('PageEmptyStateBlock('));
    expect(petDetailsPageSource, contains('PageEmptyStateBlock('));
    expect(petDetailsPageSource, contains('StatusListRow('));
    expect(File('lib/app/petnote_pages_ai.dart').readAsStringSync(),
        contains('TitledBulletGroup('));
  });

  test('keeps pet detail records out of build-time filtering and eager rows',
      () {
    final petDetailsBuildSection = petDetailsPageSource.substring(
      petDetailsPageSource.indexOf('  @override\n  Widget build'),
      petDetailsPageSource.indexOf('class _PetRecordBatchActions'),
    );

    expect(petDetailsBuildSection, contains('recordsForPet(widget.pet.id)'));
    expect(petDetailsBuildSection, contains('CustomScrollView('));
    expect(petDetailsBuildSection, contains('SliverList.separated('));
    expect(petDetailsBuildSection, isNot(contains('SectionCard.builder(')));
    expect(petDetailsBuildSection, isNot(contains('.where(')));
    expect(petDetailsBuildSection, isNot(contains('..sort(')));
    expect(petDetailsBuildSection, isNot(contains('.map(')));
  });
}
