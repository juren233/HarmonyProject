part of 'petnote_pages.dart';

const double _themePreferenceTileSpacing = 12;
const EdgeInsets _themePreferenceTilePadding =
    EdgeInsets.symmetric(horizontal: 14, vertical: 9);

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
              key: const ValueKey('theme_current_row'),
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
                    indicatorKey:
                        const ValueKey('theme_option_system_indicator'),
                    title: 'Follow system',
                    subtitle:
                        'Use the device appearance setting automatically.',
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
                    title: 'Light mode',
                    subtitle: 'Keep the current bright interface style.',
                    value: AppThemePreference.light,
                    selected: themePreference == AppThemePreference.light,
                    onTap: () =>
                        onThemePreferenceChanged(AppThemePreference.light),
                  ),
                  const SizedBox(height: _themePreferenceTileSpacing),
                  _ThemePreferenceTile(
                    key: const ValueKey('theme_option_dark'),
                    indicatorKey: const ValueKey('theme_option_dark_indicator'),
                    title: 'Dark mode',
                    subtitle: 'Reduce glare for low-light usage.',
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
