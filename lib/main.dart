import 'package:flutter/widgets.dart';
import 'package:petnote/app/app_version_info.dart';
import 'package:petnote/app/petnote_app.dart';
import 'package:petnote/app/system_ui_policy.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureStartupSystemUi();
  lockAppToPortrait();
  AppVersionInfo.load().then(
    (appVersionInfo) {
      runApp(PetNoteApp(appVersionInfo: appVersionInfo));
    },
    onError: (Object error, StackTrace stackTrace) {
      runApp(const PetNoteApp());
    },
  );
}
