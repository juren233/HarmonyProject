import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pet_care_harmony/app/pet_care_app.dart';
import 'package:pet_care_harmony/app/system_ui_policy.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureStartupSystemUi();
  runApp(const PetCareApp());
}
