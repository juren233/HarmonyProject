import 'package:flutter/material.dart';
import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/ai/ai_settings_coordinator.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/ai_settings_page.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/data_storage_page.dart';
import 'package:petnote/app/layout_metrics.dart';
import 'package:petnote/app/log_center_page.dart';
import 'package:petnote/data/data_storage_coordinator.dart';
import 'package:petnote/logging/app_log_controller.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/app/theme_settings_copy.dart';
import 'package:petnote/state/app_settings_controller.dart';

const double _themePreferenceTileSpacing = 12;
const EdgeInsets _themePreferenceTilePadding =
    EdgeInsets.symmetric(horizontal: 14, vertical: 9);

class MePage extends StatelessWidget {
  const MePage({
    super.key,
    required this.themePreference,
    required this.onThemePreferenceChanged,
    required this.notificationPermissionState,
    required this.notificationPushToken,
    required this.onRequestNotificationPermission,
    required this.onOpenNotificationSettings,
    required this.settingsController,
    required this.aiSettingsCoordinator,
    required this.dataStorageCoordinator,
    this.notificationCapabilities = const NotificationPlatformCapabilities(),
    this.appLogController,
  });

  final AppThemePreference themePreference;
  final ValueChanged<AppThemePreference> onThemePreferenceChanged;
  final NotificationPermissionState notificationPermissionState;
  final NotificationPlatformCapabilities notificationCapabilities;
  final String? notificationPushToken;
  final Future<void> Function()? onRequestNotificationPermission;
  final Future<void> Function()? onOpenNotificationSettings;
  final AppSettingsController? settingsController;
  final AppLogController? appLogController;
  final AiSettingsCoordinator? aiSettingsCoordinator;
  final DataStorageCoordinator? dataStorageCoordinator;

  @override
  Widget build(BuildContext context) {
    final pagePadding =
        pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    return ListView(
      padding: pagePadding,
      children: [
        const PageHeader(
          title: '我的',
          subtitle: '设备与应用设置',
        ),
        const HeroPanel(
          title: 'PetNote',
          subtitle: '把提醒、记录和照护总结收在一个更轻盈的系统式界面里，方便每天顺手管理。',
          child: SizedBox.shrink(),
        ),
        SectionCard(
          title: themeSectionTitle,
          children: [
            ListRow(
              key: const ValueKey('theme_current_row'),
              title: currentThemeTitle,
              subtitle: themePreferenceLabel(themePreference),
            ),
            const ListRow(
              key: ValueKey('theme_mode_description_row'),
              title: themeModeSectionTitle,
              subtitle: themeModeSectionSubtitle,
            ),
            RadioGroup<AppThemePreference>(
              groupValue: themePreference,
              onChanged: (next) {
                if (next != null) {
                  onThemePreferenceChanged(next);
                }
              },
              child: Column(
                children: [
                  _ThemePreferenceTile(
                    key: const ValueKey('theme_option_system'),
                    indicatorKey:
                        const ValueKey('theme_option_system_indicator'),
                    title: followSystemTitle,
                    subtitle: followSystemSubtitle,
                    value: AppThemePreference.system,
                    selected: themePreference == AppThemePreference.system,
                    onTap: () =>
                        onThemePreferenceChanged(AppThemePreference.system),
                  ),
                  const SizedBox(height: _themePreferenceTileSpacing),
                  _ThemePreferenceTile(
                    key: const ValueKey('theme_option_light'),
                    indicatorKey:
                        const ValueKey('theme_option_light_indicator'),
                    title: lightModeTitle,
                    subtitle: lightModeSubtitle,
                    value: AppThemePreference.light,
                    selected: themePreference == AppThemePreference.light,
                    onTap: () =>
                        onThemePreferenceChanged(AppThemePreference.light),
                  ),
                  const SizedBox(height: _themePreferenceTileSpacing),
                  _ThemePreferenceTile(
                    key: const ValueKey('theme_option_dark'),
                    indicatorKey: const ValueKey('theme_option_dark_indicator'),
                    title: darkModeTitle,
                    subtitle: darkModeSubtitle,
                    value: AppThemePreference.dark,
                    selected: themePreference == AppThemePreference.dark,
                    onTap: () =>
                        onThemePreferenceChanged(AppThemePreference.dark),
                  ),
                ],
              ),
            ),
          ],
        ),
        SectionCard(
          title: 'AI 功能',
          children: [
            ListRow(
              title: '当前 AI 提供商',
              subtitle: _aiProviderSummary(
                  settingsController?.activeAiProviderConfig),
            ),
            const ListRow(
              title: 'AI 使用说明',
              subtitle: 'API Key 由你自行提供，仅用于调用你选择的 AI 服务。',
            ),
            const ListRow(
              title: '隐私说明',
              subtitle: '你启用 AI 后，相关记录摘要或内容可能会发送给所选服务商。',
            ),
            SettingsActionButtonGroup(
              children: [
                SettingsActionButton(
                  buttonKey: const ValueKey('me_manage_ai_button'),
                  label: '管理 AI 配置',
                  onPressed: settingsController == null ||
                          aiSettingsCoordinator == null
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
              ],
            ),
          ],
        ),
        SectionCard(
          key: const ValueKey('notification_settings_section'),
          title: '通知与提醒',
          children: [
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
                subtitle: switch (notificationCapabilities.exactAlarmStatus) {
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
                    buttonKey: const ValueKey('me_request_notification_button'),
                    priority: SettingsActionPriority.primary,
                    label: '请求通知权限',
                    onPressed: onRequestNotificationPermission == null
                        ? null
                        : () => onRequestNotificationPermission!(),
                  ),
                SettingsActionButton(
                  buttonKey:
                      const ValueKey('me_open_notification_settings_button'),
                  label: '打开系统设置',
                  onPressed: onOpenNotificationSettings == null
                      ? null
                      : () => onOpenNotificationSettings!(),
                ),
              ],
            ),
          ],
        ),
        SectionCard(
          title: '数据与存储',
          children: [
            ListRow(
              title: '本地数据概览',
              subtitle: dataStorageCoordinator?.dataSummary ?? '数据中心暂不可用。',
            ),
            const ListRow(
              title: '备份与恢复',
              subtitle: '统一管理完整备份、备份恢复和本地数据清理。',
            ),
            SettingsActionButtonGroup(
              children: [
                SettingsActionButton(
                  buttonKey: const ValueKey('me_open_data_storage_button'),
                  label: '打开数据与存储',
                  onPressed: dataStorageCoordinator == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) => DataStoragePage(
                                coordinator: dataStorageCoordinator!,
                                appLogController: appLogController,
                              ),
                            ),
                          ),
                ),
              ],
            ),
          ],
        ),
        SectionCard(
          title: '日志中心',
          children: [
            ListRow(
              title: appLogController == null
                  ? '日志中心暂不可用'
                  : '最近 ${appLogController!.entries.length} 条本地日志',
              subtitle: '统一查看 AI、数据与存储、原生桥接和通知日志，便于复制给我排查。',
            ),
            SettingsActionButtonGroup(
              children: [
                SettingsActionButton(
                  buttonKey: const ValueKey('me_open_log_center_button'),
                  label: '打开日志中心',
                  onPressed: appLogController == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) => LogCenterPage(
                                controller: appLogController!,
                              ),
                            ),
                          ),
                ),
              ],
            ),
          ],
        ),
        SectionCard(
          title: '隐私与关于',
          children: const [
            ListRow(
              title: '隐私说明',
              subtitle: '仅用于记录照护信息和生成日常建议。',
            ),
            ListRow(
              title: '关于应用',
              subtitle: 'AI 总览仅作照护参考，不替代兽医建议。',
            ),
          ],
        ),
      ],
    );
  }
}

String _aiProviderSummary(AiProviderConfig? config) {
  if (config == null) {
    return '尚未配置 AI 服务，配置后可用于周报、记录整理等 AI 功能。';
  }
  final connectionMessage = config.lastConnectionMessage ??
      aiConnectionStatusLabel(config.lastConnectionStatus);
  return '${config.displayName} · ${aiProviderLabel(config.providerType)} · ${config.model}\n$connectionMessage';
}

String _notificationPermissionLabel(NotificationPermissionState state) {
  return switch (state) {
    NotificationPermissionState.authorized => '已授权，可展示系统通知与提醒。',
    NotificationPermissionState.provisional => '已临时授权，可静默展示通知。',
    NotificationPermissionState.denied => '未授权，待办和提醒不会出现在系统通知里。',
    NotificationPermissionState.unsupported => '当前平台暂未接入系统通知能力。',
    NotificationPermissionState.unknown => '尚未读取通知权限状态。',
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

class _ThemePreferenceTile extends StatelessWidget {
  const _ThemePreferenceTile({
    super.key,
    required this.indicatorKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final Key indicatorKey;
  final String title;
  final String subtitle;
  final AppThemePreference value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    return MergeSemantics(
      child: Semantics(
        checked: selected,
        inMutuallyExclusiveGroup: true,
        child: Material(
          color: tokens.listRowBackground,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: _themePreferenceTilePadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _ThemePreferenceIndicator(
                    key: indicatorKey,
                    selected: selected,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: selected
                                ? theme.colorScheme.primary
                                : tokens.primaryText,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.secondaryText,
                            height: 1.5,
                          ),
                        ),
                      ],
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

class _ThemePreferenceIndicator extends StatelessWidget {
  const _ThemePreferenceIndicator({
    super.key,
    required this.selected,
  });

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final borderColor =
        selected ? theme.colorScheme.primary : tokens.secondaryText;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
        color: tokens.listRowBackground,
      ),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: selected ? 8 : 0,
          height: selected ? 8 : 0,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
