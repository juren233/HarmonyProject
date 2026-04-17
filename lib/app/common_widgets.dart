import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/state/petnote_store.dart';

class HyperPageBackground extends StatelessWidget {
  const HyperPageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tokens.pageGradientTop, tokens.pageGradientBottom],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -40,
            right: -40,
            child: IgnorePointer(
              child: Container(
                height: 260,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.7),
                    radius: 0.9,
                    colors: [
                      tokens.pageGlow,
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: tokens.primaryText,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tokens.secondaryText,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.2,
                      ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class FrostedPanel extends StatelessWidget {
  const FrostedPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return RepaintBoundary(
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: tokens.panelShadow,
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: tokens.panelHighlightShadow,
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor ?? tokens.panelBackground,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: tokens.panelBorder, width: 1.2),
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class HeroPanel extends StatelessWidget {
  const HeroPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.header,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return FrostedPanel(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      backgroundColor: tokens.panelStrongBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) ...[
            header!,
            const SizedBox(height: 18),
          ],
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: tokens.primaryText,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.secondaryText,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class MetricOverview extends StatelessWidget {
  const MetricOverview({super.key, required this.metrics});

  final List<MetricItem> metrics;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: metrics
          .map(
            (item) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: item == metrics.last ? 0 : 10),
                child: Semantics(
                  button: item.onTap != null,
                  label: item.semanticLabel ?? item.label,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: item.onTap,
                      borderRadius: BorderRadius.circular(24),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: item.background,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.value,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    color: item.foreground,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.8,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.label,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color:
                                        item.foreground.withValues(alpha: 0.74),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class MetricItem {
  const MetricItem({
    required this.label,
    required this.value,
    required this.background,
    required this.foreground,
    this.onTap,
    this.semanticLabel,
  });

  final String label;
  final String value;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final String? semanticLabel;
}

class HyperSegmentedControl extends StatelessWidget {
  const HyperSegmentedControl({
    super.key,
    required this.items,
    required this.selectedKey,
    required this.onChanged,
  });

  final List<SegmentItem> items;
  final String selectedKey;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () => onChanged(item.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      color: selectedKey == item.key
                          ? tokens.segmentedSelectedBackground
                          : tokens.segmentedIdleBackground,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: selectedKey == item.key
                                ? Colors.white
                                : tokens.secondaryText,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class SegmentItem {
  const SegmentItem({required this.key, required this.label});

  final String key;
  final String label;
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final spaced = <Widget>[];
    for (var index = 0; index < children.length; index += 1) {
      spaced.add(children[index]);
      if (index != children.length - 1) {
        spaced.add(const SizedBox(height: 12));
      }
    }
    return FrostedPanel(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tokens.primaryText,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          ...spaced,
        ],
      ),
    );
  }
}

enum SettingsActionPriority {
  primary,
  secondary,
  dangerSecondary,
}

class SettingsActionButton extends StatelessWidget {
  const SettingsActionButton({
    super.key,
    this.buttonKey,
    required this.label,
    this.onPressed,
    this.priority = SettingsActionPriority.secondary,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final SettingsActionPriority priority;
  final IconData? icon;
  final Key? buttonKey;

  static const double height = 52;
  static const double minWidth = 148;
  static const double horizontalPadding = 20;

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(context, priority);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
    return switch (priority) {
      SettingsActionPriority.primary => FilledButton(
          key: buttonKey,
          onPressed: onPressed,
          style: style,
          child: child,
        ),
      SettingsActionPriority.secondary ||
      SettingsActionPriority.dangerSecondary =>
        OutlinedButton(
          key: buttonKey,
          onPressed: onPressed,
          style: style,
          child: child,
        ),
    };
  }

  ButtonStyle _styleFor(
    BuildContext context,
    SettingsActionPriority priority,
  ) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final textStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );
    final primaryColor = theme.colorScheme.primary;
    final secondaryColor = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.86)
        : const Color(0xFF8E6B34);
    final secondaryBorderColor = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.22)
        : const Color(0xFFB08D56);
    final dangerColor = theme.colorScheme.error;

    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size(minWidth, height),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 14,
        ),
      ),
      alignment: Alignment.center,
      textStyle: WidgetStatePropertyAll(textStyle),
      shape: WidgetStatePropertyAll(shape),
      side: WidgetStateProperty.resolveWith((states) {
        if (priority == SettingsActionPriority.primary) {
          return BorderSide.none;
        }
        final disabled = states.contains(WidgetState.disabled);
        final color = switch (priority) {
          SettingsActionPriority.secondary => disabled
              ? secondaryBorderColor.withValues(alpha: 0.34)
              : secondaryBorderColor,
          SettingsActionPriority.dangerSecondary => disabled
              ? dangerColor.withValues(alpha: 0.20)
              : dangerColor.withValues(alpha: 0.56),
          SettingsActionPriority.primary => Colors.transparent,
        };
        return BorderSide(color: color, width: 1.2);
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        final disabled = states.contains(WidgetState.disabled);
        return switch (priority) {
          SettingsActionPriority.primary =>
            disabled ? primaryColor.withValues(alpha: 0.32) : primaryColor,
          SettingsActionPriority.secondary ||
          SettingsActionPriority.dangerSecondary =>
            Colors.transparent,
        };
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        final disabled = states.contains(WidgetState.disabled);
        return switch (priority) {
          SettingsActionPriority.primary =>
            disabled ? Colors.white.withValues(alpha: 0.78) : Colors.white,
          SettingsActionPriority.secondary => disabled
              ? tokens.secondaryText.withValues(alpha: 0.54)
              : secondaryColor,
          SettingsActionPriority.dangerSecondary =>
            disabled ? dangerColor.withValues(alpha: 0.34) : dangerColor,
        };
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return switch (priority) {
            SettingsActionPriority.primary =>
              Colors.white.withValues(alpha: 0.08),
            SettingsActionPriority.secondary =>
              secondaryColor.withValues(alpha: 0.08),
            SettingsActionPriority.dangerSecondary =>
              dangerColor.withValues(alpha: 0.08),
          };
        }
        return null;
      }),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class SettingsActionButtonGroup extends StatelessWidget {
  const SettingsActionButtonGroup({
    super.key,
    required this.children,
    this.spacing = 12,
    this.runSpacing = 12,
    this.adaptiveTwoColumn = true,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final bool adaptiveTwoColumn;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    if (!adaptiveTwoColumn) {
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: children,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = children.length > 1 &&
            constraints.maxWidth >= SettingsActionButton.minWidth * 2 + spacing;
        final itemWidth =
            useTwoColumns ? (constraints.maxWidth - spacing) / 2 : null;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map(
                (child) => itemWidth == null
                    ? child
                    : SizedBox(width: itemWidth, child: child),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

enum PageFeedbackTone {
  success,
  error,
}

class PageFeedbackBanner extends StatelessWidget {
  const PageFeedbackBanner({
    super.key,
    required this.message,
    required this.tone,
  });

  final String message;
  final PageFeedbackTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = tone == PageFeedbackTone.error;
    final backgroundColor = isError
        ? const Color(0xFFF8E8E5)
        : theme.brightness == Brightness.dark
            ? const Color(0xFF253127)
            : const Color(0xFFEEF6EA);
    final foregroundColor = isError
        ? const Color(0xFF9D3B2D)
        : theme.brightness == Brightness.dark
            ? const Color(0xFFBEE2BF)
            : const Color(0xFF285B2A);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              color: foregroundColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PageEmptyStateBlock extends StatelessWidget {
  const PageEmptyStateBlock({
    super.key,
    this.heroTitle,
    this.heroSubtitle,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.actionLabel,
    this.onAction,
  });

  final String? heroTitle;
  final String? heroSubtitle;
  final String emptyTitle;
  final String emptySubtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final showHero = heroTitle != null && heroSubtitle != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHero)
          HeroPanel(
            title: heroTitle!,
            subtitle: heroSubtitle!,
            child: const SizedBox.shrink(),
          ),
        EmptyCard(
          title: emptyTitle,
          subtitle: emptySubtitle,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ],
    );
  }
}

class InlineLoadingMessage extends StatelessWidget {
  const InlineLoadingMessage({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                ),
          ),
        ),
      ],
    );
  }
}

class TitledBulletGroup extends StatelessWidget {
  const TitledBulletGroup({
    super.key,
    required this.title,
    required this.items,
    this.titleStyle,
    this.topPadding = 0,
  });

  final String title;
  final List<String> items;
  final TextStyle? titleStyle;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: titleStyle ??
              Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => BulletText(text: item)),
      ],
    );

    if (topPadding <= 0) {
      return content;
    }

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: content,
    );
  }
}

class StatusListRow extends StatelessWidget {
  const StatusListRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.leadingIcon,
    required this.leadingBackgroundColor,
    required this.leadingIconColor,
    this.trailing,
    this.leadingText,
  });

  final String title;
  final String subtitle;
  final IconData leadingIcon;
  final Color leadingBackgroundColor;
  final Color leadingIconColor;
  final Widget? trailing;
  final String? leadingText;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      title: title,
      subtitle: subtitle,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: leadingBackgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: leadingText == null
              ? Icon(leadingIcon, color: leadingIconColor)
              : Text(
                  leadingText!,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: leadingIconColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
        ),
      ),
      trailing: trailing,
    );
  }
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return FrostedPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: tokens.emptyStateBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.pets_rounded, color: tokens.emptyStateForeground),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: tokens.primaryText,
                  fontWeight: FontWeight.w800,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.secondaryText,
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class ChecklistCard extends StatelessWidget {
  const ChecklistCard({
    super.key,
    required this.item,
    this.highlighted = false,
    required this.onComplete,
    required this.onPostpone,
    required this.onSkip,
  });

  final ChecklistItemViewModel item;
  final bool highlighted;
  final VoidCallback onComplete;
  final VoidCallback onPostpone;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final overdue = item.statusLabel == '已逾期';
    final accent = _checklistAccent(item.sourceType);
    return FrostedPanel(
      key: highlighted
          ? ValueKey('highlighted_checklist_item_${item.id}')
          : null,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      backgroundColor: highlighted
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.14)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.background,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    item.petAvatarText,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: tokens.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: tokens.primaryText,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${item.petName} · ${item.kindLabel} · ${item.dueLabel}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: tokens.secondaryText,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    if (item.note.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        item.note,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: tokens.secondaryText,
                              height: 1.45,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              HyperBadge(
                text: item.statusLabel,
                foreground:
                    overdue ? tokens.badgeRedForeground : accent.foreground,
                background:
                    overdue ? tokens.badgeRedBackground : accent.background,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent.buttonColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onComplete,
                  child: const Text('完成'),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: onPostpone,
                style: TextButton.styleFrom(
                  foregroundColor: accent.buttonColor,
                ),
                child: const Text('延后'),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: accent.buttonColor,
                ),
                child: const Text('跳过'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChecklistAccent {
  const _ChecklistAccent({
    required this.background,
    required this.foreground,
    required this.buttonColor,
  });

  final Color background;
  final Color foreground;
  final Color buttonColor;
}

_ChecklistAccent _checklistAccent(String sourceType) => switch (sourceType) {
      'reminder' => const _ChecklistAccent(
          background: Color(0xFFFFF1DD),
          foreground: Color(0xFFC57A14),
          buttonColor: Color(0xFFF2A65A)),
      'record' => const _ChecklistAccent(
          background: Color(0xFFE8F7EE),
          foreground: Color(0xFF2F8F5B),
          buttonColor: Color(0xFF4FB57C)),
      _ => const _ChecklistAccent(
          background: Color(0xFFEAF0FF),
          foreground: Color(0xFF335FCA),
          buttonColor: Color(0xFF4F7BFF)),
    };

class HyperBadge extends StatelessWidget {
  const HyperBadge({
    super.key,
    required this.text,
    required this.foreground,
    required this.background,
  });

  final String text;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class BulletText extends StatelessWidget {
  const BulletText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: tokens.badgeBlueForeground,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.primaryText,
                  height: 1.55,
                ),
          ),
        ),
      ],
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.secondaryText,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.primaryText,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
          ),
        ),
      ],
    );
  }
}

class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.listRowBackground,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: tokens.primaryText,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.secondaryText,
                        height: 1.5,
                      ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class HyperTextField extends StatelessWidget {
  const HyperTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.readOnly = false,
    this.maxLines = 1,
    this.onTap,
  });

  final TextEditingController controller;
  final String? hintText;
  final bool readOnly;
  final int maxLines;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      onTap: onTap,
      decoration: InputDecoration(hintText: hintText),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: context.petNoteTokens.secondaryText,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
