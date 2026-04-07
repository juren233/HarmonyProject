import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final rootSource = File('lib/app/petnote_root.dart').readAsStringSync();
  final sheetSource = File('lib/app/add_sheet.dart').readAsStringSync();

  test(
      'add sheet relies on the system drag handle instead of rendering a duplicate one',
      () {
    expect(rootSource, contains('showDragHandle: true'));
    expect(sheetSource, isNot(contains('height: 5,')));
  });

  test(
      'add sheet avoids default close text and reuses one transition controller for collapse',
      () {
    expect(
      sheetSource,
      isNot(contains("child: Text(_action == AddAction.none ? '关闭' : '返回')")),
    );
    expect(sheetSource, isNot(contains('AnimatedSwitcher(')));
    expect(sheetSource, isNot(contains('enum _CollapsePhase')));
    expect(sheetSource, isNot(contains('_collapseContentController')));
    expect(sheetSource, contains('_transitionController.reverse('));
    expect(sheetSource,
        contains('status == AnimationStatus.dismissed && _isCollapsing'));
    expect(sheetSource, contains('_actionsRevealStart'));
    expect(sheetSource, contains('_actionsRevealOpacity'));
    expect(sheetSource, contains('_buildActionsContent('));
    expect(sheetSource, contains('_buildHeaderTransition('));
    expect(sheetSource, contains('add_sheet_header_transition'));
    expect(sheetSource, contains('add_sheet_actions_header_transition'));
    expect(sheetSource, contains('add_sheet_expanded_header_transition'));
    expect(sheetSource, contains('_ActionGridPreview'));
    expect(sheetSource, contains('ClipRect('));
    expect(sheetSource, contains('NeverScrollableScrollPhysics()'));
    expect(sheetSource, contains('add_sheet_actions_content'));
    expect(sheetSource, contains('add_sheet_actions_reveal_opacity'));
    expect(sheetSource, isNot(contains('add_sheet_actions_header_reveal')));
    expect(sheetSource, isNot(contains('add_sheet_push_back_layer')));
    expect(sheetSource, isNot(contains('add_sheet_foreground_scale')));
  });
}
