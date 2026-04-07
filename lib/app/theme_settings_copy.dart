import 'package:petnote/state/app_settings_controller.dart';

const String themeSectionTitle = '主题与外观';
const String currentThemeTitle = '当前主题';
const String themeModeSectionTitle = '主题模式';
const String themeModeSectionSubtitle = '可手动指定主题，或继续跟随系统切换。';

const String followSystemTitle = '跟随系统';
const String followSystemSubtitle = '自动跟随设备当前的外观设置。';
const String lightModeTitle = '浅色模式';
const String lightModeSubtitle = '保持明亮、清晰的日间界面效果。';
const String darkModeTitle = '深色模式';
const String darkModeSubtitle = '使用更克制、更适合 OLED 的深色界面。';

String themePreferenceLabel(AppThemePreference preference) =>
    switch (preference) {
      AppThemePreference.system => followSystemTitle,
      AppThemePreference.light => lightModeTitle,
      AppThemePreference.dark => darkModeTitle,
    };
