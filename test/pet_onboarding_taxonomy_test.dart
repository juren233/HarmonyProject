import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/pet_onboarding_taxonomy.dart';
import 'package:petnote/state/petnote_store.dart';

void main() {
  test('all pet types have breed presets and keep other as custom bucket', () {
    for (final type in PetType.values) {
      expect(
        petBreedPresets[type],
        isNotNull,
        reason: '${type.name} should have onboarding presets',
      );
      expect(
        petBreedPresets[type]!.last,
        otherBreedLabel,
        reason: '${type.name} presets should end with 其他',
      );
    }

    expect(petBreedPresets[PetType.other], [otherBreedLabel]);
  });

  test('expanded animal presets use verified common names', () {
    expect(petBreedPresets[PetType.cat], containsAll(<String>[
      '英国短毛猫',
      '美国短毛猫',
      '布偶猫',
      '波斯猫',
      '暹罗猫',
    ]));
    expect(petBreedPresets[PetType.cat]!.length, greaterThanOrEqualTo(15));

    expect(petBreedPresets[PetType.dog], containsAll(<String>[
      '法国斗牛犬',
      '拉布拉多寻回犬',
      '金毛寻回犬',
      '德国牧羊犬',
      '贵宾犬',
      '彭布罗克威尔士柯基',
    ]));
    expect(petBreedPresets[PetType.dog]!.length, greaterThanOrEqualTo(20));

    expect(petBreedPresets[PetType.hamster], containsAll(<String>[
      '叙利亚仓鼠',
      '金丝熊仓鼠',
      '坎贝尔侏儒仓鼠',
      '冬白侏儒仓鼠',
      '罗伯罗夫斯基仓鼠',
      '中国仓鼠',
    ]));
    expect(petBreedPresets[PetType.fish], containsAll(<String>[
      '金鱼',
      '锦鲤',
      '斗鱼',
      '孔雀鱼',
      '小丑鱼',
    ]));
    expect(petBreedPresets[PetType.goat], containsAll(<String>[
      '努比亚山羊',
      '尼日利亚矮山羊',
      '萨能山羊',
      '拉曼查山羊',
      '波尔山羊',
    ]));
    expect(petBreedPresets[PetType.rodent], containsAll(<String>[
      '花枝鼠',
      '小鼠',
      '豚鼠',
      '沙鼠',
      '龙猫',
      '德古鼠',
    ]));
  });

  test('monkey is intentionally not available as a pet type preset', () {
    expect(PetType.values.map((type) => type.name), isNot(contains('monkey')));
    expect(PetType.values.map(petTypeLabel), isNot(contains('猴')));
  });
}
