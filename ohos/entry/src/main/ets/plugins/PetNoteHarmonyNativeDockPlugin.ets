import common from '@ohos.app.ability.common';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import deviceInfo from '@ohos.deviceInfo';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { hdsMaterial } from '@hms.hds.hdsMaterial';
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

function detectHdsSupport(): boolean {
  try {
    return canIUse('SystemCapability.UIDesign.HDSComponent.Core') &&
      deviceInfo.sdkApiVersion >= 23;
  } catch (err) {
    hilog.warn(0x0000, TAG, 'HDS detection failed: %{public}s', JSON.stringify(err));
    return false;
  }
}

function detectNativeBlurSupport(): boolean {
  try {
    return canIUse('SystemCapability.ArkUI.ArkUI.Full') &&
      deviceInfo.sdkApiVersion >= 15;
  } catch (err) {
    return false;
  }
}

const HDS_SUPPORTED: boolean = detectHdsSupport();
const NATIVE_BLUR_SUPPORTED: boolean = detectNativeBlurSupport();

const LIGHT_INACTIVE_COLOR = '#7E8492';
const DARK_INACTIVE_COLOR = '#A1A8B4';

const LIGHT_BLUR_BACKGROUND = '#CCF5F5F7';
const DARK_BLUR_BACKGROUND = '#CC2C2C2E';
const LIGHT_SOLID_BACKGROUND = '#F5F5F7';
const DARK_SOLID_BACKGROUND = '#2C2C2E';

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
const TAB_BAR_BOTTOM_MARGIN = 6;
// The dock capsule was lowered from a 17vp bottom margin to 6vp while the
// four tab items are lifted back inside the bar, so the items ride the
// capsule only partially and rest slightly below their pre-drop position.
const TAB_ITEM_LIFT = 7;
// The selected tab item sits 2vp lower than the resting position.
const SELECTED_TAB_ITEM_DROP = 2;
const ADD_BUTTON_SIZE = 49;
const ADD_BUTTON_GLYPH_SIZE = 24;
const LABEL_FONT_SIZE = 11;
const DOCK_BORDER_RADIUS = 28;

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

  create(context: common.Context, viewId: number, args: Any): PlatformView {
    return new HarmonyNativeDockPlatformView(this.binding, context, viewId, args);
  }
}

class HarmonyNativeDockPlatformView extends PlatformView implements MethodCallHandler {
  private readonly state: HarmonyNativeDockState = new HarmonyNativeDockState();
  private readonly channel: MethodChannel;

  constructor(binding: FlutterPluginBinding, context: common.Context, viewId: number, args: Any) {
    super();
    this.state.setHostContext(context);
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
    return HDS_SUPPORTED
      ? wrapBuilder(HarmonyNativeDockBuilderHds)
      : wrapBuilder(HarmonyNativeDockBuilderNative);
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
      case 'setBottomInset':
        this.updateBottomInset(call.args);
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

  private updateBottomInset(rawInset: Any): void {
    if (typeof rawInset !== 'number') {
      return;
    }
    this.state.updateBottomInset(rawInset);
  }
}

@Observed
class HarmonyNativeDockState {
  selectedTab: string = 'checklist';
  brightness: string = 'light';
  bottomInset: number = 0;
  measuredBottomInset: number = 0;
  hdsController: HdsTabsController = new HdsTabsController();
  tabsController: TabsController = new TabsController();
  hdsMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
  private channel: MethodChannel | null = null;
  private hostContext: common.Context | null = null;

  setChannel(channel: MethodChannel | null): void {
    this.channel = channel;
  }

  setHostContext(context: common.Context): void {
    this.hostContext = context;
  }

  refreshMeasuredBottomInset(): void {
    window.getLastWindow(getContext(this) as common.UIAbilityContext)
      .then((win: window.Window) => {
        const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        const sysArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const navHeight = navArea.bottomRect.height;
        const sysHeight = sysArea.bottomRect.height;
        this.measuredBottomInset = Math.max(px2vp(navHeight), px2vp(sysHeight));

        win.on('avoidAreaChange', (data) => {
          if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR ||
              data.type === window.AvoidAreaType.TYPE_SYSTEM) {
            const h = data.area.bottomRect.height;
            const measured = Math.max(this.measuredBottomInset, px2vp(h));
            if (measured !== this.measuredBottomInset) {
              this.measuredBottomInset = measured;
              this.channel?.invokeMethod('bottomInsetMeasured', this.measuredBottomInset);
            }
          }
        });
      })
      .catch((err: Error) => {
        hilog.warn(0x0000, TAG, 'Failed to get window: %{public}s', err.message);
      });
  }

  updateSelectedTab(tab: string): void {
    this.selectedTab = tab;
    if (HDS_SUPPORTED) {
      this.hdsController.changeIndex(this.currentTabIndex());
    } else {
      this.tabsController.changeIndex(this.currentTabIndex());
    }
  }

  currentTabIndex(): number {
    for (let i = 0; i < HARMONY_DOCK_TABS.length; i++) {
      if (HARMONY_DOCK_TABS[i].name === this.selectedTab) {
        return i;
      }
    }
    return 0;
  }

  updateBrightness(brightness: string): void {
    this.brightness = brightness;
    // HDS materials, default masks and other native components follow the
    // application color mode, not the Flutter theme. Sync it so the dock
    // (and every other native surface) matches the app's brightness.
    try {
      this.hostContext?.getApplicationContext().setColorMode(
        brightness === 'dark'
          ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT,
      );
    } catch (err) {
      hilog.warn(0x0000, TAG, 'setColorMode failed: %{public}s', JSON.stringify(err));
    }
  }

  updateBottomInset(bottomInset: number): void {
    this.bottomInset = bottomInset;
  }

  effectiveBottomInset(): number {
    return Math.max(this.bottomInset, this.measuredBottomInset);
  }

  handleNativeTabChange(index: number): void {
    const tab = HARMONY_DOCK_TABS[index];
    if (tab == null) {
      return;
    }
    if (tab.isAddSlot) {
      this.handleAddTapped();
      return;
    }
    if (tab.name === this.selectedTab) {
      // Already on this tab — skip redundant notification to Flutter.
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

  currentBackgroundColor(): string {
    return this.isDarkMode() ? '#CC2C2C2E' : '#CCF5F5F7';
  }

  currentBorderColor(): string {
    return this.isDarkMode() ? '#33FFFFFF' : '#22000000';
  }

  currentDockShadowColor(): string {
    return this.isDarkMode() ? '#66000000' : '#33000000';
  }

  currentScaffoldBackgroundColor(): string {
    return this.isDarkMode() ? '#FF020304' : '#FFF5F2EC';
  }

  private isDarkMode(): boolean {
    return this.brightness === 'dark';
  }
}

@Builder
function HarmonyNativeDockBuilderHds(params: Params): void {
  HarmonyNativeDockViewHds({
    state: (params.platformView as HarmonyNativeDockPlatformView).getState()
  })
}

@Builder
function HarmonyNativeDockBuilderNative(params: Params): void {
  HarmonyNativeDockViewNative({
    state: (params.platformView as HarmonyNativeDockPlatformView).getState()
  })
}

@Component
struct HarmonyNativeDockViewHds {
  @ObjectLink state: HarmonyNativeDockState;

  aboutToAppear(): void {
    try {
      const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      this.state.hdsMaterialLevel = types.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0
        ? hdsMaterial.MaterialLevel.EXQUISITE
        : hdsMaterial.MaterialLevel.SMOOTH;
    } catch (err) {
      this.state.hdsMaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
    }
    this.state.hdsController.changeIndex(this.state.currentTabIndex());
    this.state.refreshMeasuredBottomInset();
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Bottom }) {
        HdsTabs({
          barPosition: BarPosition.End,
          controller: this.state.hdsController,
        }) {
          ForEach(HARMONY_DOCK_TABS, (tab: HarmonyDockTabConfig) => {
            TabContent() {
              Column() {}
                .width('100%')
                .height('100%')
            }
            .tabBar(this.buildTabBarItem(tab))
          }, (tab: HarmonyDockTabConfig) => tab.name)
        }
        .barOverlap(true)
        .vertical(false)
        .scrollable(false)
        .animationDuration(0)
        // The floating capsule defaults to the HDS spec height (~48vp), which
        // is shorter than the 78vp custom tab items — labels would overflow
        // below the capsule. Grow the capsule to match the item height.
        .barHeight(TAB_BAR_HEIGHT)
        .barBackgroundColor(Color.Transparent)
        .onTabBarClick((index: number) => {
          this.state.handleNativeTabChange(index);
        })
        .barFloatingStyle({
          barBottomMargin: TAB_BAR_BOTTOM_MARGIN + this.state.effectiveBottomInset(),
          // The floating bar keeps its own side margin by default, leaving
          // the capsule narrower than the host; the Flutter host already
          // provides the 17vp screen margins, so let the capsule fill it.
          barSideMargin: 0,
          // The floating bar draws a bottom gradient scrim by default
          // (maskHeight = component height + 32vp) that follows the system
          // color mode — over the Flutter content it shows up as a dirty
          // dark band. The dock floats above app content, so kill the mask.
          gradientMask: {
            maskColor: Color.Transparent,
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: this.state.hdsMaterialLevel,
          },
        })
        this.buildCenteredAddButton()
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  buildTabBarItem(tab: HarmonyDockTabConfig): void {
    if (tab.isAddSlot) {
      Column() {}
        .width(60)
        .height(TAB_BAR_HEIGHT)
    } else {
      Column() {
        Column() {
          Image(this.tabIconResource(tab))
            .width(19)
            .height(19)
            .fillColor(this.isSelected(tab) ? '#FFFFFF' : this.state.currentInactiveColor())
        }
        .width(32)
        .height(32)
        .borderRadius(15)
        .backgroundColor(this.isSelected(tab) ? tab.accentColor : '#00000000')
        .justifyContent(FlexAlign.Center)
        Text(tab.label)
          .fontSize(11)
          .fontWeight(this.isSelected(tab) ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.isSelected(tab) ? tab.accentColor : this.state.currentInactiveColor())
          .margin({ top: 3 })
      }
      .width('100%')
      .height(TAB_BAR_HEIGHT)
      .offset({
        y: -TAB_ITEM_LIFT + (this.isSelected(tab) ? SELECTED_TAB_ITEM_DROP : 0)
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  isSelected(tab: HarmonyDockTabConfig): boolean {
    return this.state.selectedTab === tab.name;
  }

  tabIconResource(tab: HarmonyDockTabConfig): ResourceStr {
    if (tab.name === 'checklist') return $r('app.media.ic_tab_checklist');
    if (tab.name === 'overview') return $r('app.media.ic_tab_overview');
    if (tab.name === 'pets') return $r('app.media.ic_tab_pets');
    if (tab.name === 'me') return $r('app.media.ic_tab_me');
    return $r('app.media.ic_tab_add_placeholder');
  }

  @Builder
  buildCenteredAddButton(): void {
    Row() {
      Button() {
        Text('+')
          .fontSize(ADD_BUTTON_GLYPH_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
      .type(ButtonType.Capsule)
      .width(ADD_BUTTON_SIZE)
      .height(ADD_BUTTON_SIZE)
      .backgroundColor(this.state.currentAddButtonStartColor())
      .linearGradient({
        direction: GradientDirection.RightBottom,
        colors: [
          [this.state.currentAddButtonStartColor(), 0],
          [this.state.currentAddButtonEndColor(), 1]
        ]
      })
      .border({ width: 1.4, color: '#AAFFFFFF' })
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
    .justifyContent(FlexAlign.Center)
    // Vertically center the button within the 78vp bar (matches the Flutter
    // fallback dock where the add button sits at the panel's center).
    .margin({
      bottom: TAB_BAR_BOTTOM_MARGIN + this.state.effectiveBottomInset() +
        (TAB_BAR_HEIGHT - ADD_BUTTON_SIZE) / 2
    })
  }
}

@Component
struct HarmonyNativeDockViewNative {
  @ObjectLink state: HarmonyNativeDockState;

  aboutToAppear(): void {
    this.state.tabsController.changeIndex(this.state.currentTabIndex());
    this.state.refreshMeasuredBottomInset();
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Bottom }) {
        Tabs({
          barPosition: BarPosition.End,
          controller: this.state.tabsController,
        }) {
          ForEach(HARMONY_DOCK_TABS, (tab: HarmonyDockTabConfig) => {
            TabContent() {
              Column() {}
                .width('100%')
                .height('100%')
            }
            .tabBar(this.buildTabBarItem(tab))
          }, (tab: HarmonyDockTabConfig) => tab.name)
        }
        .barOverlap(true)
        .vertical(false)
        .scrollable(false)
        .animationDuration(0)
        .barHeight(TAB_BAR_HEIGHT)
        .barBackgroundColor(Color.Transparent)
        .onTabBarClick((index: number) => {
          this.state.handleNativeTabChange(index);
        })
        .barBackgroundBlurStyle(
          NATIVE_BLUR_SUPPORTED ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE
        )
        .backgroundColor(
          NATIVE_BLUR_SUPPORTED
            ? (this.state.brightness === 'dark' ? DARK_BLUR_BACKGROUND : LIGHT_BLUR_BACKGROUND)
            : (this.state.brightness === 'dark' ? DARK_SOLID_BACKGROUND : LIGHT_SOLID_BACKGROUND)
        )
        .margin({ bottom: TAB_BAR_BOTTOM_MARGIN + this.state.effectiveBottomInset() })

        this.buildCenteredAddButton()
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  buildTabBarItem(tab: HarmonyDockTabConfig): void {
    if (tab.isAddSlot) {
      Column() {}
        .width(60)
        .height(TAB_BAR_HEIGHT)
    } else {
      Column() {
        Image(this.tabIconResource(tab))
          .width(23)
          .height(23)
          .fillColor(this.isSelected(tab) ? tab.accentColor : this.state.currentInactiveColor())
        Text(tab.label)
          .fontSize(LABEL_FONT_SIZE)
          .fontColor(this.isSelected(tab) ? tab.accentColor : this.state.currentInactiveColor())
          .margin({ top: 2 })
      }
      .width('100%')
      .height(TAB_BAR_HEIGHT)
      .offset({
        y: -TAB_ITEM_LIFT + (this.isSelected(tab) ? SELECTED_TAB_ITEM_DROP : 0)
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  isSelected(tab: HarmonyDockTabConfig): boolean {
    return this.state.selectedTab === tab.name;
  }

  tabIconResource(tab: HarmonyDockTabConfig): ResourceStr {
    if (tab.name === 'checklist') return $r('app.media.ic_tab_checklist');
    if (tab.name === 'overview') return $r('app.media.ic_tab_overview');
    if (tab.name === 'pets') return $r('app.media.ic_tab_pets');
    if (tab.name === 'me') return $r('app.media.ic_tab_me');
    return $r('app.media.ic_tab_add_placeholder');
  }

  @Builder
  buildCenteredAddButton(): void {
    Row() {
      Button() {
        Text('+')
          .fontSize(ADD_BUTTON_GLYPH_SIZE)
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
    .justifyContent(FlexAlign.Center)
    // Vertically center the button within the 78vp bar (matches the Flutter
    // fallback dock where the add button sits at the panel's center).
    .margin({
      bottom: TAB_BAR_BOTTOM_MARGIN + this.state.effectiveBottomInset() +
        (TAB_BAR_HEIGHT - ADD_BUTTON_SIZE) / 2
    })
  }
}
