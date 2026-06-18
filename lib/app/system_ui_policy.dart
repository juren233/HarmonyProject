import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const List<DeviceOrientation> appPortraitOrientations = [
  DeviceOrientation.portraitUp,
];

class StartupSystemUiPolicy {
  const StartupSystemUiPolicy({
    required this.mode,
    required this.overlayStyle,
  });

  final SystemUiMode? mode;
  final SystemUiOverlayStyle overlayStyle;
}

const StartupSystemUiPolicy ohosStartupSystemUiPolicy = StartupSystemUiPolicy(
  mode: SystemUiMode.edgeToEdge,
  overlayStyle: SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Color(0x00000000),
    systemNavigationBarDividerColor: Color(0x00000000),
    systemNavigationBarIconBrightness: Brightness.dark,
  ),
);

Future<void> configureStartupSystemUi({
  StartupSystemUiPolicy policy = ohosStartupSystemUiPolicy,
}) async {
  if (policy.mode != null) {
    await SystemChrome.setEnabledSystemUIMode(policy.mode!);
  }
  SystemChrome.setSystemUIOverlayStyle(policy.overlayStyle);
}

Future<void> lockAppToPortrait({
  List<DeviceOrientation> orientations = appPortraitOrientations,
  String? platformName,
}) {
  final resolvedPlatformName = platformName ?? defaultTargetPlatform.name;
  if (resolvedPlatformName == 'ohos') {
    return Future<void>.value();
  }
  return SystemChrome.setPreferredOrientations(orientations);
}
