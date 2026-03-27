import 'package:flutter/widgets.dart';

const double _pageHorizontalPadding = 18;
const double _pageTopSpacing = 8;
const double _pageBottomReserve = 122;
const double _dockShellBaseHeight = 66;
const double _dockPanelBaseHeight = 66;
const double _dockBottomSpacing = 17;
const double dockBlurSigma = 6;

EdgeInsets pageContentPaddingForInsets(EdgeInsets insets) {
  return EdgeInsets.fromLTRB(
    _pageHorizontalPadding,
    insets.top + _pageTopSpacing,
    _pageHorizontalPadding,
    insets.bottom + _pageBottomReserve,
  );
}

DockLayoutMetrics dockLayoutForInsets(EdgeInsets insets) {
  return DockLayoutMetrics(
    shellHeight: _dockShellBaseHeight,
    panelHeight: _dockPanelBaseHeight,
    outerMargin: const EdgeInsets.fromLTRB(32, 0, 32, _dockBottomSpacing),
    innerPadding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
  );
}

class DockLayoutMetrics {
  const DockLayoutMetrics({
    required this.shellHeight,
    required this.panelHeight,
    required this.outerMargin,
    required this.innerPadding,
  });

  final double shellHeight;
  final double panelHeight;
  final EdgeInsets outerMargin;
  final EdgeInsets innerPadding;
}
