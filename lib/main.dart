import 'package:flutter/widgets.dart';
import 'package:pet_care_harmony/app/pet_care_app.dart';
import 'package:pet_care_harmony/app/system_ui_policy.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureStartupSystemUi();
  runApp(const PetCareApp());
}
