import 'package:petnote/state/petnote_store.dart';

const String otherBreedLabel = '其他';

const Map<PetType, List<String>> petBreedPresets = {
  PetType.cat: [
    '英短',
    '美短',
    '布偶',
    '缅因',
    '暹罗',
    '金吉拉',
    '异国短毛',
    '德文卷毛',
    '斯芬克斯',
    '狸花',
    '橘猫',
    '奶牛猫',
    otherBreedLabel,
  ],
  PetType.dog: [
    '柯基',
    '金毛',
    '拉布拉多',
    '边牧',
    '柴犬',
    '泰迪',
    '比熊',
    '博美',
    '法斗',
    '雪纳瑞',
    '腊肠',
    '萨摩耶',
    '马尔济斯',
    otherBreedLabel,
  ],
  PetType.rabbit: [
    '垂耳兔',
    '侏儒兔',
    '狮子兔',
    '安哥拉兔',
    otherBreedLabel,
  ],
  PetType.bird: [
    '虎皮鹦鹉',
    '玄凤鹦鹉',
    '牡丹鹦鹉',
    '文鸟',
    '金丝雀',
    otherBreedLabel,
  ],
  PetType.other: [otherBreedLabel],
};
