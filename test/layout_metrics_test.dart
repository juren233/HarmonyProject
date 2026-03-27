import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_care_harmony/app/layout_metrics.dart';

void main() {
  test('page padding uses a single set of explicit system insets', () {
    const insets = EdgeInsets.only(top: 44, bottom: 24);
    final padding = pageContentPaddingForInsets(insets);

    expect(padding.left, 18);
    expect(padding.right, 18);
    expect(padding.top, 52);
    expect(padding.bottom, 146);
  });

  test('dock layout reserves gesture area inside the dock instead of outside it', () {
    const insets = EdgeInsets.only(bottom: 24);
    final layout = dockLayoutForInsets(insets);

    expect(layout.shellHeight, 66);
    expect(layout.panelHeight, 66);
    expect(layout.outerMargin.left, 32);
    expect(layout.outerMargin.right, 32);
    expect(layout.outerMargin.bottom, 17);
    expect(layout.innerPadding.top, 8);
    expect(layout.innerPadding.bottom, 8);
  });

  test('dock blur sigma stays at the softer tuned value', () {
    expect(dockBlurSigma, 6);
  });
}
