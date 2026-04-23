import common from '@ohos.app.ability.common';
import { hdsMaterial } from '@hms.hds.hdsMaterial';
import { HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import Any from '@ohos/flutter_ohos/src/main/ets/plugin/common/Any';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import PlatformViewFactory from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformViewFactory';

const TAG = 'PetNoteHarmonyNativeDockPlugin';
const VIEW_TYPE = 'petnote/harmony_native_dock';
const CHANNEL_PREFIX = 'petnote/harmony_native_dock_';

const LIGHT_INACTIVE_COLOR = '#7E8492';
const DARK_INACTIVE_COLOR = '#A1A8B4';
const HIDDEN_TABBAR_COLOR = '#00000000';

const CHECKLIST_ACCENT_COLOR = '#F2A65A';
const OVERVIEW_ACCENT_COLOR = '#9B84E8';
const PETS_ACCENT_COLOR = '#FFA79B';
const ME_ACCENT_COLOR = '#A5C6FF';

const LIGHT_ADD_START_COLOR = '#90CE9B';
const LIGHT_ADD_END_COLOR = '#6AB57A';
const DARK_ADD_START_COLOR = '#73B87F';
const DARK_ADD_END_COLOR = '#528F63';

const TAB_BAR_WIDTH = 340;
const TAB_BAR_HEIGHT = 78;
const TAB_BAR_BOTTOM_MARGIN = 17;
const ADD_BUTTON_SIZE = 52;
const LABEL_FONT_SIZE = 12;

interface HarmonyDockCreationParams {
  selectedTab?: string;
  brightness?: string;
  bottomInset?: number;
}

interface HarmonyDockTabConfig {
  name: string;
  label: string;
  accentColor: string;
  isAddSlot: boolean;
}

const HARMONY_DOCK_TABS: Array<HarmonyDockTabConfig> = [
  {
    name: 'checklist',
    label: '清单',
    accentColor: CHECKLIST_ACCENT_COLOR,
    isAddSlot: false,
  },
  {
    name: 'overview',
    label: '总览',
    accentColor: OVERVIEW_ACCENT_COLOR,
    isAddSlot: false,
  },
  {
    name: 'add',
    label: '',
    accentColor: LIGHT_INACTIVE_COLOR,
    isAddSlot: true,
  },
  {
    name: 'pets',
    label: '爱宠',
    accentColor: PETS_ACCENT_COLOR,
    isAddSlot: false,
  },
  {
    name: 'me',
    label: '我的',
    accentColor: ME_ACCENT_COLOR,
    isAddSlot: false,
  },
];

export default class PetNoteHarmonyNativeDockPlugin implements FlutterPlugin {
  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    binding.getPlatformViewRegistry()
      .registerViewFactory(VIEW_TYPE, new HarmonyNativeDockViewFactory(binding));
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
  }
}

class HarmonyNativeDockViewFactory extends PlatformViewFactory {
  private readonly binding: FlutterPluginBinding;

  constructor(binding: FlutterPluginBinding) {
    super(StandardMessageCodec.INSTANCE);
    this.binding = binding;
  }

  create(_context: common.Context, viewId: number, args: Any): PlatformView {
    return new HarmonyNativeDockPlatformView(this.binding, viewId, args);
  }
}

class HarmonyNativeDockPlatformView extends PlatformView implements MethodCallHandler {
  private readonly state: HarmonyNativeDockState = new HarmonyNativeDockState();
  private readonly channel: MethodChannel;

  constructor(binding: FlutterPluginBinding, viewId: number, args: Any) {
    super();
    this.applyCreationParams(args);
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      CHANNEL_PREFIX + viewId.toString(),
      StandardMethodCodec.INSTANCE,
    );
    this.channel.setMethodCallHandler(this);
    this.state.setChannel(this.channel);
  }

  getType(): string {
    return VIEW_TYPE;
  }

  getView(): WrappedBuilder<[Params]> {
    return wrapBuilder(HarmonyNativeDockBuilder);
  }

  getState(): HarmonyNativeDockState {
    return this.state;
  }

  dispose(): void {
    this.channel.setMethodCallHandler(null);
    this.state.setChannel(null);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'setSelectedTab':
        this.updateSelectedTab(call.args);
        result.success(null);
        break;
      case 'setBrightness':
        this.updateBrightness(call.args);
        result.success(null);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private applyCreationParams(args: Any): void {
    const params = args as HarmonyDockCreationParams;
    if (params == null) {
      return;
    }
    if (typeof params.selectedTab === 'string') {
      this.state.updateSelectedTab(params.selectedTab);
    }
    if (typeof params.brightness === 'string') {
      this.state.updateBrightness(params.brightness);
    }
    if (typeof params.bottomInset === 'number') {
      this.state.updateBottomInset(params.bottomInset);
    }
  }

  private updateSelectedTab(rawTab: Any): void {
    if (typeof rawTab !== 'string') {
      return;
    }
    this.state.updateSelectedTab(rawTab);
  }

  private updateBrightness(rawBrightness: Any): void {
    if (typeof rawBrightness !== 'string') {
      return;
    }
    this.state.updateBrightness(rawBrightness);
  }
}

@Observed
class HarmonyNativeDockState {
  tabsController: HdsTabsController = new HdsTabsController();
  selectedTab: string = 'checklist';
  brightness: string = 'light';
  bottomInset: number = 0;
  materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.EXQUISITE;
  private channel: MethodChannel | null = null;

  setChannel(channel: MethodChannel | null): void {
    this.channel = channel;
  }

  updateSelectedTab(tab: string): void {
    this.selectedTab = tab;
    this.syncControllerIndex();
  }

  updateBrightness(brightness: string): void {
    this.brightness = brightness;
  }

  updateBottomInset(bottomInset: number): void {
    this.bottomInset = bottomInset;
  }

  syncMaterialEffectByCapability(): void {
    const materialTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
    if (materialTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) < 0) {
      this.materialLevel = hdsMaterial.MaterialLevel.SMOOTH;
      return;
    }
    this.materialLevel = hdsMaterial.MaterialLevel.EXQUISITE;
  }

  handleNativeTabChange(index: number): void {
    const tab = HARMONY_DOCK_TABS[index];
    if (tab == null) {
      return;
    }
    if (tab.isAddSlot) {
      this.handleAddTapped();
      this.syncControllerIndex();
      return;
    }
    this.selectedTab = tab.name;
    this.channel?.invokeMethod('tabSelected', tab.name);
  }

  handleAddTapped(): void {
    this.channel?.invokeMethod('addTapped', null);
  }

  currentInactiveColor(): string {
    return this.isDarkMode() ? DARK_INACTIVE_COLOR : LIGHT_INACTIVE_COLOR;
  }

  currentAddButtonStartColor(): string {
    return this.isDarkMode() ? DARK_ADD_START_COLOR : LIGHT_ADD_START_COLOR;
  }

  currentAddButtonEndColor(): string {
    return this.isDarkMode() ? DARK_ADD_END_COLOR : LIGHT_ADD_END_COLOR;
  }

  currentShadowColor(): string {
    return this.isDarkMode() ? '#33528F63' : '#336AB57A';
  }

  private syncControllerIndex(): void {
    this.tabsController.changeIndex(this.currentTabIndex());
  }

  private currentTabIndex(): number {
    for (let index = 0; index < HARMONY_DOCK_TABS.length; index++) {
      if (HARMONY_DOCK_TABS[index].name === this.selectedTab) {
        return index;
      }
    }
    return 0;
  }

  private isDarkMode(): boolean {
    return this.brightness === 'dark';
  }
}

@Builder
function HarmonyNativeDockBuilder(params: Params): void {
  HarmonyNativeDockView({
    state: (params.platformView as HarmonyNativeDockPlatformView).getState()
  })
}

@Component
struct HarmonyNativeDockView {
  @ObjectLink state: HarmonyNativeDockState;

  aboutToAppear(): void {
    this.state.syncMaterialEffectByCapability();
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Bottom }) {
        HdsTabs({ controller: this.state.tabsController }) {
          ForEach(HARMONY_DOCK_TABS, (tab: HarmonyDockTabConfig) => {
            TabContent() {
              Column() {}
                .width('100%')
                .height('100%')
            }
            .tabBar(this.tabBarStyle(tab))
          }, (tab: HarmonyDockTabConfig) => tab.name)
        }
        .barOverlap(true)
        .barPosition(BarPosition.End)
        .vertical(false)
        .barHeight(TAB_BAR_HEIGHT)
        .barBackgroundColor(Color.Transparent)
        .animationDuration(0)
        .onChange((index: number) => {
          this.state.handleNativeTabChange(index);
        })
        .barFloatingStyle({
          barWidth: { smallWidth: TAB_BAR_WIDTH, mediumWidth: TAB_BAR_WIDTH, largeWidth: TAB_BAR_WIDTH },
          barBottomMargin: TAB_BAR_BOTTOM_MARGIN + this.state.bottomInset,
          gradientMask: { maskColor: '#66F1F3F5', maskHeight: 92 },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: this.state.materialLevel
          }
        })

        this.buildCenteredAddButton()
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
  }

  tabBarStyle(tab: HarmonyDockTabConfig): BottomTabBarStyle {
    if (tab.name === 'checklist') {
      return this.visibleTabBarStyle($r('app.media.ic_tab_checklist'), tab);
    }
    if (tab.name === 'overview') {
      return this.visibleTabBarStyle($r('app.media.ic_tab_overview'), tab);
    }
    if (tab.name === 'pets') {
      return this.visibleTabBarStyle($r('app.media.ic_tab_pets'), tab);
    }
    if (tab.name === 'me') {
      return this.visibleTabBarStyle($r('app.media.ic_tab_me'), tab);
    }
    return this.addPlaceholderTabBarStyle();
  }

  visibleTabBarStyle(icon: ResourceStr, tab: HarmonyDockTabConfig): BottomTabBarStyle {
    return new BottomTabBarStyle(icon, tab.label)
      .labelStyle({
        selectedColor: tab.accentColor,
        unselectedColor: this.state.currentInactiveColor(),
        font: { size: LABEL_FONT_SIZE }
      })
      .iconStyle({
        selectedColor: tab.accentColor,
        unselectedColor: this.state.currentInactiveColor(),
      })
      .layoutMode(LayoutMode.VERTICAL)
      .verticalAlign(VerticalAlign.Center)
      .symmetricExtensible(true);
  }

  addPlaceholderTabBarStyle(): BottomTabBarStyle {
    return new BottomTabBarStyle($r('app.media.ic_tab_add_placeholder'), '')
      .labelStyle({
        selectedColor: HIDDEN_TABBAR_COLOR,
        unselectedColor: HIDDEN_TABBAR_COLOR,
        font: { size: LABEL_FONT_SIZE }
      })
      .iconStyle({
        selectedColor: HIDDEN_TABBAR_COLOR,
        unselectedColor: HIDDEN_TABBAR_COLOR,
      })
      .layoutMode(LayoutMode.VERTICAL)
      .verticalAlign(VerticalAlign.Center)
      .symmetricExtensible(true);
  }

  @Builder
  buildCenteredAddButton(): void {
    Row() {
      Button() {
        Text('+')
          .fontSize(26)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
      .type(ButtonType.Capsule)
      .width(ADD_BUTTON_SIZE)
      .height(ADD_BUTTON_SIZE)
      .backgroundColor(this.state.currentAddButtonStartColor())
      .linearGradient({
        angle: 315,
        colors: [
          [this.state.currentAddButtonStartColor(), 0],
          [this.state.currentAddButtonEndColor(), 1]
        ]
      })
      .border({
        width: 1.4,
        color: '#AAFFFFFF'
      })
      .shadow({
        radius: 18,
        color: this.state.currentShadowColor(),
        offsetX: 0,
        offsetY: 8
      })
      .onClick(() => {
        this.state.handleAddTapped();
      })
    }
    .width(ADD_BUTTON_SIZE)
    .height(TAB_BAR_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: TAB_BAR_BOTTOM_MARGIN + this.state.bottomInset })
  }
}
