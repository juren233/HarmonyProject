import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/layout_metrics.dart';
import 'package:petnote/notifications/notification_models.dart';
import 'package:petnote/app/theme_settings_copy.dart';
import 'package:petnote/state/app_settings_controller.dart';

class MePage extends StatelessWidget {
  const MePage({
    super.key,
    required this.themePreference,
    required this.onThemePreferenceChanged,
    required this.notificationPermissionState,
    required this.notificationPushToken,
    required this.onRequestNotificationPermission,
    required this.onOpenNotificationSettings,
  });

  final AppThemePreference themePreference;
  final ValueChanged<AppThemePreference> onThemePreferenceChanged;
  final NotificationPermissionState notificationPermissionState;
  final String? notificationPushToken;
  final Future<void> Function()? onRequestNotificationPermission;
  final Future<void> Function()? onOpenNotificationSettings;

  @override
  Widget build(BuildContext context) {
    final pagePadding =
        pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final sharedNotificationButtonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );
    final sharedNotificationButtonTextStyle =
        theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
    );
    final requestNotificationButtonStyle = FilledButton.styleFrom(
      minimumSize: const Size(0, 52),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      shape: sharedNotificationButtonShape,
      textStyle: sharedNotificationButtonTextStyle,
      backgroundColor: theme.colorScheme.primary,
      foregroundColor: Colors.white,
    );
    final notificationSettingsButtonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 52),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      shape: sharedNotificationButtonShape,
      textStyle: sharedNotificationButtonTextStyle,
      foregroundColor: tokens.primaryText,
      side: BorderSide(
        color: theme.brightness == Brightness.dark
            ? tokens.primaryText.withValues(alpha: 0.22)
            : const Color(0xFFB08D56),
        width: 1.2,
      ),
      backgroundColor: Colors.transparent,
    );
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
              title: currentThemeTitle,
              subtitle: themePreferenceLabel(themePreference),
            ),
            const ListRow(
              title: themeModeSectionTitle,
              subtitle: themeModeSectionSubtitle,
            ),
            _ThemePreferenceTile(
              key: const ValueKey('theme_option_system'),
              title: followSystemTitle,
              subtitle: followSystemSubtitle,
              value: AppThemePreference.system,
              groupValue: themePreference,
              onChanged: onThemePreferenceChanged,
            ),
            _ThemePreferenceTile(
              key: const ValueKey('theme_option_light'),
              title: lightModeTitle,
              subtitle: lightModeSubtitle,
              value: AppThemePreference.light,
              groupValue: themePreference,
              onChanged: onThemePreferenceChanged,
            ),
            _ThemePreferenceTile(
              key: const ValueKey('theme_option_dark'),
              title: darkModeTitle,
              subtitle: darkModeSubtitle,
              value: AppThemePreference.dark,
              groupValue: themePreference,
              onChanged: onThemePreferenceChanged,
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
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  style: requestNotificationButtonStyle,
                  onPressed: onRequestNotificationPermission == null
                      ? null
                      : () => onRequestNotificationPermission!(),
                  child: const Text('请求通知权限'),
                ),
                OutlinedButton(
                  style: notificationSettingsButtonStyle,
                  onPressed: onOpenNotificationSettings == null
                      ? null
                      : () => onOpenNotificationSettings!(),
                  child: const Text('打开系统设置'),
                ),
              ],
            ),
          ],
        ),
        SectionCard(
          title: '数据与存储',
          children: const [
            ListRow(
              title: '备份与恢复',
              subtitle: '预留本地备份、迁移与恢复入口。',
            ),
            ListRow(
              title: '导出与分享',
              subtitle: '后续支持导出宠物交接卡和记录摘要。',
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

String _notificationPermissionLabel(NotificationPermissionState state) {
  return switch (state) {
    NotificationPermissionState.authorized => '已授权，可展示系统通知与提醒。',
    NotificationPermissionState.provisional => '已临时授权，可静默展示通知。',
    NotificationPermissionState.denied => '未授权，待办和提醒不会出现在系统通知里。',
    NotificationPermissionState.unsupported => '当前平台暂未接入系统通知能力。',
    NotificationPermissionState.unknown => '尚未读取通知权限状态。',
  };
}

class _ThemePreferenceTile extends StatelessWidget {
  const _ThemePreferenceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final AppThemePreference value;
  final AppThemePreference groupValue;
  final ValueChanged<AppThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.listRowBackground,
        borderRadius: BorderRadius.circular(22),
      ),
      child: RadioListTile<AppThemePreference>(
        value: value,
        groupValue: groupValue,
        onChanged: (next) {
          if (next != null) {
            onChanged(next);
          }
        },
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.secondaryText,
                height: 1.45,
              ),
        ),
        activeColor: Theme.of(context).colorScheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
