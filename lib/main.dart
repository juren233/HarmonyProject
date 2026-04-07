import 'package:flutter/widgets.dart';
import 'package:petnote/app/petnote_app.dart';
import 'package:petnote/app/system_ui_policy.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureStartupSystemUi();
  runApp(const PetNoteApp());
}
