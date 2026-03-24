import 'package:flutter/widgets.dart';

const double _pageHorizontalPadding = 18;
const double _pageTopSpacing = 8;
const double _pageBottomReserve = 122;
const double _dockShellBaseHeight = 84;
const double _dockPanelBaseHeight = 76;
const double _dockBottomSpacing = 8;

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
    shellHeight: _dockShellBaseHeight + insets.bottom,
    panelHeight: _dockPanelBaseHeight + insets.bottom,
    outerMargin: const EdgeInsets.fromLTRB(18, 0, 18, _dockBottomSpacing),
    innerPadding: EdgeInsets.fromLTRB(18, 10, 18, insets.bottom + _dockBottomSpacing),
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
