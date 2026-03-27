import 'package:flutter/material.dart';
import 'package:pet_care_harmony/app/app_theme.dart';
import 'package:pet_care_harmony/state/pet_care_store.dart';

class NavigationAccent {
  const NavigationAccent(this.fill, this.label);

  final Color fill;
  final Color label;

  @override
  bool operator ==(Object other) {
    return other is NavigationAccent &&
        other.fill == fill &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(fill, label);
}

NavigationAccent tabAccentFor(BuildContext context, AppTab tab) {
  final scheme = Theme.of(context).colorScheme;
  final tokens = context.petCareTokens;
  return switch (tab) {
    AppTab.checklist => NavigationAccent(scheme.primary, scheme.primary),
    AppTab.overview =>
      NavigationAccent(tokens.badgeBlueForeground, tokens.badgeBlueForeground),
    AppTab.pets =>
      NavigationAccent(tokens.badgeRedForeground, tokens.badgeRedForeground),
    AppTab.me =>
      NavigationAccent(tokens.badgeGoldForeground, tokens.badgeGoldForeground),
  };
}
