import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/ai/ai_settings_coordinator.dart';
import 'package:petnote/app/ai_settings_page.dart';
import 'package:petnote/app/app_update_checker.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/app_version_info.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/data_storage_page.dart';
import 'package:petnote/app/ios_native_update_reminder_switch.dart';
import 'package:petnote/app/layout_metrics.dart';
import 'package:petnote/app/navigation_palette.dart';
import 'package:petnote/data/data_storage_coordinator.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:url_launcher/url_launcher.dart';

const double _settingsEntrySpacing = 12;
const _androidLiquidGlassToggleViewType = 'petnote/android_liquid_glass_toggle';
const double _androidLiquidGlassToggleSlotWidth = 112;
const double _androidLiquidGlassToggleSlotHeight = 72;
const double _androidLiquidGlassToggleHostWidth = 96;
const double _androidLiquidGlassToggleHostHeight = 64;
const _androidLiquidGlassToggleCommitDelay = Duration(milliseconds: 220);
const _androidLiquidGlassTogglePrewarmRetryDelay = Duration(milliseconds: 120);
const EdgeInsets _settingsEntryPadding =
    EdgeInsets.symmetric(horizontal: 14, vertical: 13);

class MePage extends StatelessWidget {
  const MePage({
    super.key,
    required this.themePreference,
    required this.onThemePreferenceChanged,
    required this.notificationPermissionState,
    required this.notificationPushToken,
    required this.onRequestNotificationPermission,
    required this.onOpenNotificationSettings,
    required this.onOpenExactAlarmSettings,
    this.shouldOpenNotificationSettingsForRequest = false,
    required this.settingsController,
    required this.aiSettingsCoordinator,
    required this.dataStorageCoordinator,
    this.appVersionInfo = AppVersionInfo.empty,
    this.notificationCapabilities = const NotificationPlatformCapabilities(),
    this.appUpdateChecker = const GitHubAppUpdateChecker(),
    this.platformNameOverride,
  });

  final AppThemePreference themePreference;
  final ValueChanged<AppThemePreference> onThemePreferenceChanged;
  final NotificationPermissionState notificationPermissionState;
  final NotificationPlatformCapabilities notificationCapabilities;
  final String? notificationPushToken;
  final Future<void> Function()? onRequestNotificationPermission;
  final Future<void> Function()? onOpenNotificationSettings;
  final Future<void> Function()? onOpenExactAlarmSettings;
  final bool shouldOpenNotificationSettingsForRequest;
  final AppSettingsController? settingsController;
  final AiSettingsCoordinator? aiSettingsCoordinator;
  final DataStorageCoordinator? dataStorageCoordinator;
  final AppVersionInfo appVersionInfo;
  final AppUpdateChecker appUpdateChecker;
  final String? platformNameOverride;

  @override
  Widget build(BuildContext context) {
    final pagePadding =
        pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    return ListView(
      padding: pagePadding,
      children: [
        const PageHeader(
          title: '我的',
          subtitle: 'App各项设置',
        ),
        _ThemeAppearanceCard(
          themePreference: themePreference,
          onThemePreferenceChanged: onThemePreferenceChanged,
        ),
        const SizedBox(height: _settingsEntrySpacing),
        _SettingsEntrancePanel(
          children: [
            _SettingsNavigationEntry(
              key: const ValueKey('me_ai_config_entry'),
              icon: Icons.auto_awesome_rounded,
              title: 'AI配置',
              subtitle: _aiProviderSummary(
                settingsController?.activeAiProviderConfig,
              ),
              onTap: settingsController == null || aiSettingsCoordinator == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => AiSettingsPage(
                            settingsController: settingsController!,
                            coordinator: aiSettingsCoordinator!,
                          ),
                        ),
                      ),
            ),
            _SettingsNavigationEntry(
              key: const ValueKey('me_notification_entry'),
              icon: Icons.notifications_active_rounded,
              title: '通知提醒',
              subtitle: _notificationPermissionLabel(
                notificationPermissionState,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => _NotificationSettingsPage(
                    settingsController: settingsController,
                    notificationPermissionState: notificationPermissionState,
                    notificationCapabilities: notificationCapabilities,
                    notificationPushToken: notificationPushToken,
                    onRequestNotificationPermission:
                        onRequestNotificationPermission,
                    onOpenNotificationSettings: onOpenNotificationSettings,
                    onOpenExactAlarmSettings: onOpenExactAlarmSettings,
                    shouldOpenNotificationSettingsForRequest:
                        shouldOpenNotificationSettingsForRequest,
                    platformNameOverride: platformNameOverride,
                  ),
                ),
              ),
            ),
            _SettingsNavigationEntry(
              key: const ValueKey('me_data_backup_entry'),
              icon: Icons.cloud_upload_rounded,
              title: '数据备份',
              subtitle: dataStorageCoordinator?.dataSummary ?? '数据中心暂不可用。',
              onTap: dataStorageCoordinator == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => DataStoragePage(
                            coordinator: dataStorageCoordinator!,
                          ),
                        ),
                      ),
            ),
          ],
        ),
        const SizedBox(height: _settingsEntrySpacing),
        _AboutPetNoteCard(
          appVersionInfo: appVersionInfo,
          appUpdateChecker: appUpdateChecker,
        ),
      ],
    );
  }
}

class _ThemeAppearanceCard extends StatelessWidget {
  const _ThemeAppearanceCard({
    required this.themePreference,
    required this.onThemePreferenceChanged,
  });

  final AppThemePreference themePreference;
  final ValueChanged<AppThemePreference> onThemePreferenceChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final meAccentColor = tabAccentFor(context, AppTab.me).label;
    return FrostedPanel(
      key: const ValueKey('me_theme_appearance_card'),
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      backgroundColor: tokens.panelStrongBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SettingsIconBubble(
                icon: Icons.palette_rounded,
                backgroundColor: meAccentColor.withValues(
                  alpha: 0.12,
                ),
                foregroundColor: meAccentColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '主题外观',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: tokens.primaryText,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ThemeSlider(
            themePreference: themePreference,
            onThemePreferenceChanged: onThemePreferenceChanged,
          ),
        ],
      ),
    );
  }
}

class _ThemeSlider extends StatelessWidget {
  const _ThemeSlider({
    required this.themePreference,
    required this.onThemePreferenceChanged,
  });

  final AppThemePreference themePreference;
  final ValueChanged<AppThemePreference> onThemePreferenceChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final isDark = theme.brightness == Brightness.dark;
    final sliderSurfaceColor = isDark ? tokens.listRowBackground : Colors.white;
    final selectedPillColor =
        isDark ? const Color(0xFFF3F1EC) : const Color(0xFF171717);
    final sliderShadowColor = isDark
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.06);
    final sliderValue = _themeSliderValue(themePreference);
    final selectedIndex = sliderValue.round();
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        const outerPadding = 6.0;
        const selectedPillHeight = 48.0;
        const selectedInset = 0.0;
        final contentWidth = availableWidth - outerPadding * 2;
        final pillWidth = contentWidth / 3;
        return Container(
          key: const ValueKey('me_theme_slider'),
          height: 60,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: sliderSurfaceColor,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: sliderShadowColor,
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: selectedIndex * pillWidth,
                top: 0,
                width: pillWidth - selectedInset * 2,
                height: selectedPillHeight,
                child: DecoratedBox(
                  key: switch (themePreference) {
                    AppThemePreference.system =>
                      const ValueKey('theme_slider_selected_system'),
                    AppThemePreference.light =>
                      const ValueKey('theme_slider_selected_light'),
                    AppThemePreference.dark =>
                      const ValueKey('theme_slider_selected_dark'),
                  },
                  decoration: BoxDecoration(
                    color: selectedPillColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  _ThemeSegmentOption(
                    key: const ValueKey('theme_option_system'),
                    label: '设备',
                    icon: Icons.smartphone_rounded,
                    selected: themePreference == AppThemePreference.system,
                    useDarkSurface: isDark,
                    onTap: () =>
                        onThemePreferenceChanged(AppThemePreference.system),
                  ),
                  _ThemeSegmentOption(
                    key: const ValueKey('theme_option_light'),
                    label: '浅色',
                    icon: Icons.light_mode_rounded,
                    selected: themePreference == AppThemePreference.light,
                    useDarkSurface: isDark,
                    onTap: () =>
                        onThemePreferenceChanged(AppThemePreference.light),
                  ),
                  _ThemeSegmentOption(
                    key: const ValueKey('theme_option_dark'),
                    label: '深色',
                    icon: Icons.dark_mode_rounded,
                    selected: themePreference == AppThemePreference.dark,
                    useDarkSurface: isDark,
                    onTap: () =>
                        onThemePreferenceChanged(AppThemePreference.dark),
                  ),
                ],
              ),
              Positioned.fill(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: selectedPillHeight,
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: SliderComponentShape.noThumb,
                    tickMarkShape: SliderTickMarkShape.noTickMark,
                  ),
                  child: Slider(
                    key: const ValueKey('me_theme_slider_control'),
                    min: 0,
                    max: 2,
                    divisions: 2,
                    value: sliderValue,
                    onChanged: (value) => onThemePreferenceChanged(
                      _themePreferenceFromSliderValue(value),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeSegmentOption extends StatelessWidget {
  const _ThemeSegmentOption({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.useDarkSurface,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool useDarkSurface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = switch ((selected, useDarkSurface)) {
      (true, true) => const Color(0xFF171717),
      (true, false) => Colors.white,
      (false, true) => const Color(0xFFB7BBC5),
      (false, false) => const Color(0xFF6F6F76),
    };
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(28),
            child: SizedBox(
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: textColor),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsEntrancePanel extends StatelessWidget {
  const _SettingsEntrancePanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return FrostedPanel(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index += 1) ...[
            children[index],
            if (index != children.length - 1)
              const SizedBox(height: _settingsEntrySpacing),
          ],
        ],
      ),
    );
  }
}

class _SettingsNavigationEntry extends StatelessWidget {
  const _SettingsNavigationEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final meAccentColor = tabAccentFor(context, AppTab.me).label;
    final foregroundColor = meAccentColor;
    return Material(
      color: tokens.listRowBackground,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: _settingsEntryPadding,
          child: Row(
            children: [
              _SettingsIconBubble(
                icon: icon,
                backgroundColor: foregroundColor.withValues(alpha: 0.12),
                foregroundColor: foregroundColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: tokens.primaryText,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.secondaryText,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                color: tokens.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutPetNoteCard extends StatefulWidget {
  const _AboutPetNoteCard({
    required this.appVersionInfo,
    required this.appUpdateChecker,
  });

  final AppVersionInfo appVersionInfo;
  final AppUpdateChecker appUpdateChecker;

  @override
  State<_AboutPetNoteCard> createState() => _AboutPetNoteCardState();
}

class _AboutPetNoteCardState extends State<_AboutPetNoteCard> {
  static const String _defaultGitHubUrl = 'https://github.com/juren233/PetNote';

  String _releaseTileTitle = 'GitHub 仓库';
  String _releaseTileSubtitle = '跳转查看更新';
  String _releaseUrl = _defaultGitHubUrl;
  int _releaseInfoRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadReleaseInfo();
  }

  @override
  void didUpdateWidget(covariant _AboutPetNoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appVersionInfo.buildNumber !=
            widget.appVersionInfo.buildNumber ||
        oldWidget.appUpdateChecker != widget.appUpdateChecker) {
      _loadReleaseInfo();
    }
  }

  Future<void> _loadReleaseInfo() async {
    final requestId = ++_releaseInfoRequestId;
    final buildNumber = widget.appVersionInfo.buildNumber;
    String releaseTileTitle = 'GitHub 仓库';
    String releaseTileSubtitle = '跳转查看更新';
    String releaseUrl = _defaultGitHubUrl;

    final currentBuildNumber = int.tryParse(buildNumber);
    if (currentBuildNumber != null) {
      final latestUpdate = await widget.appUpdateChecker.fetchLatestUpdate(
        currentBuildNumber: currentBuildNumber,
      );
      if (latestUpdate != null) {
        releaseTileTitle = '🆕 当前App有新版 ${latestUpdate.versionLabel}';
        releaseTileSubtitle = '点击查看 ${latestUpdate.versionLabel} 发布说明';
        releaseUrl = latestUpdate.releaseUrl.toString();
      }
    }

    if (!mounted || requestId != _releaseInfoRequestId) {
      return;
    }

    setState(() {
      _releaseTileTitle = releaseTileTitle;
      _releaseTileSubtitle = releaseTileSubtitle;
      _releaseUrl = releaseUrl;
    });
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } on MissingPluginException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前平台暂不支持打开外部链接')),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('无法打开链接：$url')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final isDark = theme.brightness == Brightness.dark;
    final version = widget.appVersionInfo.version;
    final infoListBackground = isDark
        ? tokens.listRowBackground.withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.72);
    final logoBoxBackground = isDark ? const Color(0xFF111111) : Colors.white;
    final logoBoxBorderColor =
        isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFEAE6E0);
    final logoShadowColor =
        isDark ? Colors.black.withValues(alpha: 0.28) : const Color(0x0D000000);
    final logoColorFilter =
        isDark ? const ColorFilter.mode(Colors.white, BlendMode.srcIn) : null;
    final versionBadgeBackground =
        isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFF6F1E9);
    final versionBadgeBorderColor =
        isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE6DDD1);
    return FrostedPanel(
      key: const ValueKey('me_about_card'),
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      backgroundColor: tokens.panelStrongBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('me_about_logo_box'),
            width: 112,
            height: 112,
            padding: const EdgeInsets.all(0),
            decoration: BoxDecoration(
              color: logoBoxBackground,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: logoBoxBorderColor,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: logoShadowColor,
                  blurRadius: 16,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 110,
                  maxHeight: 110,
                ),
                child: SvgPicture.asset(
                  'assets/images/intro/first_page_hero.svg',
                  fit: BoxFit.contain,
                  colorFilter: logoColorFilter,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '宠记',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: tokens.primaryText,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            key: const ValueKey('me_about_version_badge'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: versionBadgeBackground,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: versionBadgeBorderColor,
                width: 1,
              ),
            ),
            child: Text(
              'Version ${version.isEmpty ? '--' : version}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: tokens.secondaryText,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '宠物日常关怀记录App',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.secondaryText,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              color: infoListBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _AboutInfoTile(
                  icon: Icons.code_rounded,
                  title: _releaseTileTitle,
                  subtitle: _releaseTileSubtitle,
                  onTap: () => _openExternalUrl(_releaseUrl),
                ),
                _AboutInfoDivider(color: tokens.primaryText),
                _AboutInfoTile(
                  icon: Icons.person_outline_rounded,
                  title: 'juren233',
                  subtitle: 'Developer',
                  onTap: () => _openExternalUrl(
                    'https://github.com/juren233',
                  ),
                ),
                _AboutInfoDivider(color: tokens.primaryText),
                _AboutInfoTile(
                  icon: Icons.person_outline_rounded,
                  title: 'Ebato',
                  subtitle: 'Developer',
                  onTap: () => _openExternalUrl(
                    'https://github.com/Souitou-iop',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _AboutInfoTile extends StatelessWidget {
  const _AboutInfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meAccentColor = tabAccentFor(context, AppTab.me).label;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: meAccentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: meAccentColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutInfoDivider extends StatelessWidget {
  const _AboutInfoDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 56,
      endIndent: 16,
      color: color.withValues(alpha: 0.08),
    );
  }
}

class _SettingsIconBubble extends StatelessWidget {
  const _SettingsIconBubble({
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: foregroundColor, size: 22),
    );
  }
}

class _NotificationSettingsPage extends StatelessWidget {
  const _NotificationSettingsPage({
    required this.settingsController,
    required this.notificationPermissionState,
    required this.notificationCapabilities,
    required this.notificationPushToken,
    required this.onRequestNotificationPermission,
    required this.onOpenNotificationSettings,
    required this.onOpenExactAlarmSettings,
    this.shouldOpenNotificationSettingsForRequest = false,
    this.platformNameOverride,
  });

  final AppSettingsController? settingsController;
  final NotificationPermissionState notificationPermissionState;
  final NotificationPlatformCapabilities notificationCapabilities;
  final String? notificationPushToken;
  final Future<void> Function()? onRequestNotificationPermission;
  final Future<void> Function()? onOpenNotificationSettings;
  final Future<void> Function()? onOpenExactAlarmSettings;
  final bool shouldOpenNotificationSettingsForRequest;
  final String? platformNameOverride;

  @override
  Widget build(BuildContext context) {
    final platformName = platformNameOverride ?? defaultTargetPlatform.name;
    final shouldShowUpdateReminder =
        settingsController != null && platformName != 'ohos';
    return Scaffold(
      appBar: AppBar(title: const Text('通知提醒')),
      body: HyperPageBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            const HeroPanel(
              title: '通知提醒',
              subtitle: '集中管理提醒权限、系统设置和准点提醒能力。',
              child: SizedBox.shrink(),
            ),
            SectionCard(
              key: const ValueKey('notification_settings_section'),
              title: '通知提醒',
              children: [
                if (shouldShowUpdateReminder) ...[
                  _UpdateReminderSettingsRow(
                    enabled: settingsController!.updateReminderEnabled,
                    platformName: platformName,
                    onChanged: settingsController!.setUpdateReminderEnabled,
                  ),
                  const SizedBox(height: 12),
                ],
                ListRow(
                  title: '提醒权限',
                  subtitle:
                      _notificationPermissionLabel(notificationPermissionState),
                ),
                ListRow(
                  title: '提醒方式',
                  subtitle: notificationPushToken == null
                      ? '当前使用本地提醒调度，推送 token 尚未注册。'
                      : '已记录推送 token，后续可接远程推送下发。',
                ),
                if (notificationCapabilities.supportsExactAlarms)
                  ListRow(
                    title: '准点提醒能力',
                    subtitle: switch (
                        notificationCapabilities.exactAlarmStatus) {
                      NotificationExactAlarmStatus.available =>
                        '当前设备允许精确闹钟，通知会尽量按时触达。',
                      NotificationExactAlarmStatus.unavailable =>
                        '当前设备未授予精确闹钟能力，系统可能延后提醒。',
                      NotificationExactAlarmStatus.unsupported =>
                        '当前平台无需单独配置精确闹钟能力。',
                    },
                  ),
                SettingsActionButtonGroup(
                  children: [
                    if (_isNotificationPermissionGranted(
                        notificationPermissionState))
                      _NotificationPermissionGrantedBadge(
                        state: notificationPermissionState,
                      )
                    else
                      SettingsActionButton(
                        buttonKey:
                            const ValueKey('me_request_notification_button'),
                        priority: SettingsActionPriority.primary,
                        label: shouldOpenNotificationSettingsForRequest
                            ? '前往系统设置'
                            : '请求通知权限',
                        onPressed: onRequestNotificationPermission == null
                            ? null
                            : () => onRequestNotificationPermission!(),
                      ),
                    if (notificationCapabilities.supportsExactAlarms &&
                        notificationCapabilities.exactAlarmStatus ==
                            NotificationExactAlarmStatus.unavailable)
                      SettingsActionButton(
                        buttonKey: const ValueKey(
                          'me_open_exact_alarm_settings_button',
                        ),
                        label: '开启准点提醒',
                        onPressed: onOpenExactAlarmSettings == null
                            ? null
                            : () => onOpenExactAlarmSettings!(),
                      ),
                    SettingsActionButton(
                      buttonKey: const ValueKey(
                        'me_open_notification_settings_button',
                      ),
                      label: '打开系统设置',
                      onPressed: onOpenNotificationSettings == null
                          ? null
                          : () => onOpenNotificationSettings!(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateReminderSettingsRow extends StatelessWidget {
  const _UpdateReminderSettingsRow({
    required this.enabled,
    required this.platformName,
    required this.onChanged,
  });

  final bool enabled;
  final String platformName;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final toggle = platformName == TargetPlatform.iOS.name
        ? IosNativeUpdateReminderSwitchHost(
            key: const ValueKey('notification_update_reminder_toggle'),
            value: enabled,
            onChanged: onChanged,
          )
        : _AndroidLiquidGlassToggleHost(
            key: const ValueKey('notification_update_reminder_toggle'),
            value: enabled,
            onChanged: onChanged,
          );
    return Material(
      color: tokens.listRowBackground,
      borderRadius: BorderRadius.circular(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: _androidLiquidGlassToggleSlotHeight + 16,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                18,
                17,
                _androidLiquidGlassToggleSlotWidth + 18,
                17,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '更新提醒',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: tokens.primaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '检测到新版时，启动 App 会发送更新通知提醒。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.secondaryText,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            PositionedDirectional(
              top: 8,
              end: 6,
              child: _UpdateReminderToggleSlot(
                child: toggle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateReminderToggleSlot extends StatelessWidget {
  const _UpdateReminderToggleSlot({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _androidLiquidGlassToggleSlotWidth,
      height: _androidLiquidGlassToggleSlotHeight,
      child: RepaintBoundary(
        child: Center(child: child),
      ),
    );
  }
}

class _AndroidLiquidGlassToggleHost extends StatefulWidget {
  const _AndroidLiquidGlassToggleHost({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<_AndroidLiquidGlassToggleHost> createState() =>
      _AndroidLiquidGlassToggleHostState();
}

class _AndroidLiquidGlassToggleHostState
    extends State<_AndroidLiquidGlassToggleHost> {
  MethodChannel? _channel;
  Timer? _pendingSelectionCommit;
  bool _hasRequestedFirstInteractionPrewarm = false;
  int _firstInteractionPrewarmEpoch = 0;

  @override
  void didUpdateWidget(covariant _AndroidLiquidGlassToggleHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _syncSelected();
    }
    _syncBrightness();
    _syncBackdropColor();
  }

  @override
  void dispose() {
    _pendingSelectionCommit?.cancel();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return _AndroidLiquidGlassToggleTestHandle(
        value: widget.value,
        onChanged: widget.onChanged,
      );
    }
    final tokens = context.petNoteTokens;
    final brightness = Theme.of(context).brightness;
    return SizedBox(
      width: _androidLiquidGlassToggleHostWidth,
      height: _androidLiquidGlassToggleHostHeight,
      child: PlatformViewLink(
        viewType: _androidLiquidGlassToggleViewType,
        surfaceFactory: (
          BuildContext context,
          PlatformViewController controller,
        ) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            gestureRecognizers: {
              Factory<OneSequenceGestureRecognizer>(
                EagerGestureRecognizer.new,
              ),
            },
          );
        },
        onCreatePlatformView: (PlatformViewCreationParams params) {
          final controller = PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: params.viewType,
            layoutDirection: Directionality.of(context),
            creationParams: {
              'selected': widget.value,
              'brightness': brightness.name,
              'backdropColor': tokens.listRowBackground.toARGB32(),
              'shouldPrewarmFirstInteraction': true,
            },
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          );
          controller.addOnPlatformViewCreatedListener((int viewId) {
            params.onPlatformViewCreated(viewId);
            _onPlatformViewCreated(viewId);
          });
          controller.create();
          return controller;
        },
      ),
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel(
      'petnote/android_liquid_glass_toggle_$viewId',
    );
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    _syncSelected();
    _syncBrightness();
    _syncBackdropColor();
    _maybeRequestFirstInteractionPrewarm();
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'selectedChanged') {
      final selected = call.arguments == true;
      _pendingSelectionCommit?.cancel();
      if (selected != widget.value) {
        _pendingSelectionCommit = Timer(
          _androidLiquidGlassToggleCommitDelay,
          () {
            if (!mounted || selected == widget.value) {
              return;
            }
            widget.onChanged(selected);
          },
        );
      }
    }
  }

  Future<void> _syncSelected() async {
    try {
      await _channel?.invokeMethod<void>('setSelected', widget.value);
    } on PlatformException {
      // 忽略原生视图初始化早期的瞬时同步失败。
    }
  }

  Future<void> _syncBrightness() async {
    if (!mounted) {
      return;
    }
    try {
      await _channel?.invokeMethod<void>(
        'setBrightness',
        Theme.of(context).brightness.name,
      );
    } on PlatformException {
      // 忽略原生视图初始化早期的瞬时同步失败。
    }
  }

  Future<void> _syncBackdropColor() async {
    if (!mounted) {
      return;
    }
    try {
      await _channel?.invokeMethod<void>(
        'setBackdropColor',
        context.petNoteTokens.listRowBackground.toARGB32(),
      );
    } on PlatformException {
      // 忽略原生视图初始化早期的瞬时同步失败。
    }
  }

  Future<void> _maybeRequestFirstInteractionPrewarm() async {
    final channel = _channel;
    if (channel == null || _hasRequestedFirstInteractionPrewarm) {
      return;
    }
    try {
      await channel.invokeMethod<void>('prewarmFirstInteraction');
      _hasRequestedFirstInteractionPrewarm = true;
    } on PlatformException {
      _scheduleFirstInteractionPrewarmRetry();
    }
  }

  void _scheduleFirstInteractionPrewarmRetry() {
    final retryEpoch = ++_firstInteractionPrewarmEpoch;
    Future<void>.delayed(
      _androidLiquidGlassTogglePrewarmRetryDelay,
      () {
        if (!mounted || retryEpoch != _firstInteractionPrewarmEpoch) {
          return;
        }
        _maybeRequestFirstInteractionPrewarm();
      },
    );
  }
}

class _AndroidLiquidGlassToggleTestHandle extends StatelessWidget {
  const _AndroidLiquidGlassToggleTestHandle({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: const SizedBox(
          width: _androidLiquidGlassToggleHostWidth,
          height: _androidLiquidGlassToggleHostHeight,
        ),
      ),
    );
  }
}

String _aiProviderSummary(AiProviderConfig? config) {
  if (config == null) {
    return '配置 API Key 与模型信息';
  }
  final connectionMessage = config.lastConnectionMessage ??
      aiConnectionStatusLabel(config.lastConnectionStatus);
  return '${config.displayName} · ${aiProviderLabel(config.providerType)} · ${config.model}\n$connectionMessage';
}

String _notificationPermissionLabel(NotificationPermissionState state) {
  return switch (state) {
    NotificationPermissionState.authorized => '各项通知与提醒',
    NotificationPermissionState.provisional => '已临时授权，可静默展示通知。',
    NotificationPermissionState.denied => '当前尚未授权通知权限',
    NotificationPermissionState.unsupported => '当前平台暂未接入系统通知',
    NotificationPermissionState.unknown => '尚未读取通知权限状态',
  };
}

double _themeSliderValue(AppThemePreference preference) {
  return switch (preference) {
    AppThemePreference.system => 0,
    AppThemePreference.light => 1,
    AppThemePreference.dark => 2,
  };
}

AppThemePreference _themePreferenceFromSliderValue(double value) {
  final index = value.round().clamp(0, 2);
  return switch (index) {
    0 => AppThemePreference.system,
    1 => AppThemePreference.light,
    _ => AppThemePreference.dark,
  };
}

bool _isNotificationPermissionGranted(NotificationPermissionState state) {
  return state == NotificationPermissionState.authorized ||
      state == NotificationPermissionState.provisional;
}

class _NotificationPermissionGrantedBadge extends StatelessWidget {
  const _NotificationPermissionGrantedBadge({
    required this.state,
  });

  final NotificationPermissionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = _notificationPermissionGrantedCopy(state);
    final backgroundColor = theme.brightness == Brightness.dark
        ? const Color(0xFF223127)
        : const Color(0xFFF1F8EE);
    final borderColor = theme.brightness == Brightness.dark
        ? const Color(0xFF4D6C53)
        : const Color(0xFFA3C4A3);
    final foregroundColor = theme.brightness == Brightness.dark
        ? const Color(0xFFBEE2BF)
        : const Color(0xFF285B2A);
    final textStyle = theme.textTheme.labelLarge?.copyWith(
      color: foregroundColor,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
      height: 1,
      leadingDistribution: TextLeadingDistribution.even,
    );

    return ConstrainedBox(
      key: const ValueKey('me_notification_permission_badge'),
      constraints: const BoxConstraints(
        minHeight: SettingsActionButton.height,
        minWidth: SettingsActionButton.minWidth,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        child: SizedBox(
          height: SettingsActionButton.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SettingsActionButton.horizontalPadding,
            ),
            child: Center(
              child: Text(
                copy.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
                style: textStyle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

_NotificationPermissionGrantedCopy _notificationPermissionGrantedCopy(
  NotificationPermissionState state,
) {
  return switch (state) {
    NotificationPermissionState.provisional =>
      const _NotificationPermissionGrantedCopy(
        title: '已临时授权',
      ),
    NotificationPermissionState.authorized ||
    NotificationPermissionState.denied ||
    NotificationPermissionState.unsupported ||
    NotificationPermissionState.unknown =>
      const _NotificationPermissionGrantedCopy(
        title: '已授权',
      ),
  };
}

class _NotificationPermissionGrantedCopy {
  const _NotificationPermissionGrantedCopy({
    required this.title,
  });

  final String title;
}
