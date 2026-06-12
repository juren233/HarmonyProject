import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first-launch intro includes device role selection page', () {
    final source =
        File('lib/app/pet_first_launch_intro.dart').readAsStringSync();
    final rootSource = File('lib/app/petnote_root.dart').readAsStringSync();

    expect(source, contains('这台设备为谁服务？'));
    expect(source, contains('intro_role_owner'));
    expect(source, contains('intro_role_pet'));
    expect(source, contains('DeviceRole.owner'));
    expect(source, contains('DeviceRole.pet'));
    expect(source, contains('onSelectRole'));
    expect(rootSource, contains('onSelectPetRoleFromIntro: _selectRoleFromIntro'));
  });
}
