import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:petnote/app/app_version_info.dart';
import 'package:petnote/app/petnote_app.dart';
import 'package:petnote/app/system_ui_policy.dart';

/// Global key used by [_OhosRecoveryGuard] to rebuild the app after a
/// StackOverflowError on 32-bit ARM OHOS.
final GlobalKey<_OhosRecoveryGuardState> _recoveryKey =
    GlobalKey<_OhosRecoveryGuardState>();

void main() {
  // On OpenHarmony (32-bit ARM), deep widget trees can exhaust the Dart VM
  // stack during build/layout, producing StackOverflowError in places that
  // work fine on 64-bit platforms. Catch these gracefully instead of crashing.
  //
  // When a StackOverflowError is caught, schedule an app-level recovery
  // rebuild. By the time the rebuild fires, the framework's internal widgets
  // (Material, Navigator, Scaffold, etc.) are already initialised and cached,
  // so the second build succeeds without overflowing.
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception is StackOverflowError) {
      debugPrint(
        'OHOS-WORKAROUND: StackOverflowError caught in '
        '${details.library ?? "unknown"} — '
        '${details.context?.toString() ?? "no context"}',
      );
      // Schedule a recovery rebuild. The guard deduplicates multiple calls.
      _recoveryKey.currentState?._scheduleRecovery();
      return;
    }
    FlutterError.presentError(details);
  };

  // Replace the default red error screen with a minimal placeholder.
  // IMPORTANT: keep the tree as shallow as possible — Material/Theme/Scaffold
  // would add widget levels that can trigger a secondary StackOverflowError
  // on 32-bit ARM OHOS.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return const SizedBox.expand(
      child: ColoredBox(
        color: Color(0xFFF5F5F5),
        child: Center(
          child: Text(
            '页面加载中，请稍候…',
            style: TextStyle(fontSize: 16, color: Color(0xFF999999)),
          ),
        ),
      ),
    );
  };

  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    configureStartupSystemUi();
    lockAppToPortrait();
    AppVersionInfo.load().then(
      (appVersionInfo) {
        runApp(_OhosRecoveryGuard(
          key: _recoveryKey,
          appVersionInfo: appVersionInfo,
        ));
      },
      onError: (Object error, StackTrace stackTrace) {
        runApp(_OhosRecoveryGuard(key: _recoveryKey));
      },
    );
  }, (Object error, StackTrace stack) {
    debugPrint('OHOS-WORKAROUND: Uncaught zone error: $error');
    // Also try to recover from async zone errors.
    _recoveryKey.currentState?._scheduleRecovery();
  });
}

/// Wraps [PetNoteApp] and rebuilds it after a StackOverflowError on 32-bit
/// ARM OpenHarmony. The first build often overflows due to the deep widget
/// tree (MaterialApp → Navigator → Scaffold → …). After the overflow,
/// framework-internal widgets are cached, so a rebuild ~500 ms later
/// succeeds without overflowing.
class _OhosRecoveryGuard extends StatefulWidget {
  const _OhosRecoveryGuard({super.key, this.appVersionInfo});

  final AppVersionInfo? appVersionInfo;

  @override
  State<_OhosRecoveryGuard> createState() => _OhosRecoveryGuardState();
}

class _OhosRecoveryGuardState extends State<_OhosRecoveryGuard> {
  Key _childKey = UniqueKey();
  bool _recoveryScheduled = false;
  static const int _maxRecoveries = 3;
  int _recoveryCount = 0;

  void _scheduleRecovery() {
    if (_recoveryScheduled || _recoveryCount >= _maxRecoveries) return;
    _recoveryScheduled = true;
    debugPrint(
      'OHOS-WORKAROUND: Scheduling recovery rebuild '
      '(${_recoveryCount + 1}/$_maxRecoveries) in 500ms…',
    );
    Future<void>.delayed(const Duration(milliseconds: 500)).then((_) {
      _recoveryScheduled = false;
      if (mounted) {
        _recoveryCount += 1;
        debugPrint(
          'OHOS-WORKAROUND: Triggering recovery rebuild #'
          '$_recoveryCount',
        );
        setState(() {
          _childKey = UniqueKey();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final versionInfo = widget.appVersionInfo;
    return PetNoteApp(
      key: _childKey,
      appVersionInfo: versionInfo ?? AppVersionInfo.empty,
    );
  }
}
