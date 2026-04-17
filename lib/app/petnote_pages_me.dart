part of 'petnote_pages.dart';

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
          title: 'PetNote',
          subtitle: '把提醒、记录和照护总结收在一个更轻盈的系统式界面里，方便每天顺手管理。',
          child: SizedBox.shrink(),
        ),
        SectionCard(
          title: 'Theme & Appearance',
          children: [
            ListRow(
              title: 'Current theme',
              subtitle: switch (themePreference) {
                AppThemePreference.system => 'Follow system',
                AppThemePreference.light => 'Light mode',
                AppThemePreference.dark => 'Dark mode',
              },
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
                    title: 'Follow system',
                    subtitle: 'Use the device appearance setting automatically.',
                    value: AppThemePreference.system,
                    selected: themePreference == AppThemePreference.system,
                  ),
                  _ThemePreferenceTile(
                    key: const ValueKey('theme_option_light'),
                    title: 'Light mode',
                    subtitle: 'Keep the current bright interface style.',
                    value: AppThemePreference.light,
                    selected: themePreference == AppThemePreference.light,
                  ),
                  _ThemePreferenceTile(
                    key: const ValueKey('theme_option_dark'),
                    title: 'Dark mode',
                    subtitle: 'Reduce glare for low-light usage.',
                    value: AppThemePreference.dark,
                    selected: themePreference == AppThemePreference.dark,
                  ),
                ],
              ),
            ),
          ],
        ),
        SectionCard(
          title: '通知与提醒',
          children: const [
            ListRow(title: '提醒权限', subtitle: '后续可接入系统通知与提醒权限管理'),
            ListRow(title: '提醒方式', subtitle: '当前原型使用本地清单和 AI 总览来承接提醒信息'),
          ],
        ),
        SectionCard(
          title: '数据与存储',
          children: const [
            ListRow(title: '备份与恢复', subtitle: '预留本地备份、迁移与恢复入口'),
            ListRow(title: '导出与分享', subtitle: '后续支持导出宠物交接卡和记录摘要'),
          ],
        ),
        SectionCard(
          title: '隐私与关于',
          children: const [
            ListRow(title: '隐私说明', subtitle: '仅用于记录照护信息和生成日常建议'),
            ListRow(title: '关于应用', subtitle: 'AI 总览仅供照护参考，不替代兽医建议'),
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
    required this.selected,
  });

  final String title;
  final String subtitle;
  final AppThemePreference value;
  final bool selected;

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
        selected: selected,
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
