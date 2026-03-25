import 'package:flutter/material.dart';
import 'package:pet_care_harmony/app/app_theme.dart';
import 'package:pet_care_harmony/app/common_widgets.dart';
import 'package:pet_care_harmony/app/layout_metrics.dart';
import 'package:pet_care_harmony/app/theme_settings_copy.dart';
import 'package:pet_care_harmony/state/app_settings_controller.dart';

class MePage extends StatelessWidget {
  const MePage({
    super.key,
    required this.themePreference,
    required this.onThemePreferenceChanged,
  });

  final AppThemePreference themePreference;
  final ValueChanged<AppThemePreference> onThemePreferenceChanged;

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
          title: 'Pet Care',
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
          title: '通知与提醒',
          children: const [
            ListRow(
              title: '提醒权限',
              subtitle: '后续可接入系统通知与提醒权限管理。',
            ),
            ListRow(
              title: '提醒方式',
              subtitle: '当前原型使用本地清单和 AI 总览来承接提醒信息。',
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
    final tokens = context.petCareTokens;
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
