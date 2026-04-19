import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/intro_haptics.dart';
import 'package:petnote/app/native_pet_photo_picker.dart';
import 'package:petnote/app/pet_onboarding_overlay.dart';
import 'package:petnote/state/petnote_store.dart';

import 'add_sheet_models.dart';
import 'form_controls/form_scaffold.dart';
import 'form_controls/missing_pet_prerequisite.dart';
import 'forms/record_form.dart';
import 'forms/reminder_form.dart';
import 'forms/todo_form.dart';

enum _AddSheetStage { actions, expandedForm, petOnboarding }

class AddActionSheet extends StatefulWidget {
  const AddActionSheet({
    super.key,
    required this.store,
    this.nativePetPhotoPicker,
    this.introHapticsDriver,
  });

  final PetNoteStore store;
  final NativePetPhotoPicker? nativePetPhotoPicker;
  final IntroHapticsDriver? introHapticsDriver;

  @override
  State<AddActionSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<AddActionSheet>
    with SingleTickerProviderStateMixin {
  static const _compactSheetHeight = 448.0;
  static const _sheetRadius = 36.0;
  static const _expandedTransitionDuration = Duration(milliseconds: 360);
  static const _actionsRevealStart = 0.62;
  static const _headerOverlayHeight = 112.0;
  static const _actionsContentTopInset = 74.0;
  static const _actionsHorizontalInset = 18.0;
  static const _expandedContentTopInset = 112.0;
  static const _defaultSheetTopPadding = 4.0;
  static const _petOnboardingTopPadding = 0.0;

  late final AnimationController _transitionController;
  late final IntroHapticsDriver _introHapticsDriver =
      widget.introHapticsDriver ?? MethodChannelIntroHaptics();
  AddAction _action = AddAction.none;
  bool _isCollapsing = false;

  bool get _hasExpandedStage => _action != AddAction.none;
  AddAction get _transitionAction => _action;
  bool get _isPetOnboarding =>
      _hasExpandedStage && _transitionAction == AddAction.pet;
  Curve get _sheetMotionCurve =>
      _isCollapsing ? Curves.easeInCubic : Curves.easeOutCubic;
  double get _sheetMotionProgress =>
      _sheetMotionCurve.transform(_transitionController.value);
  double get _actionsRevealOpacity {
    if (!_isCollapsing) {
      return 0;
    }
    final progress = _transitionController.value;
    if (progress >= _actionsRevealStart) {
      return 0;
    }
    final revealProgress =
        (1 - (progress / _actionsRevealStart)).clamp(0.0, 1.0);
    return Curves.easeOutQuad.transform(revealProgress);
  }

  bool get _shouldRevealActions => _actionsRevealOpacity > 0;
  double get _sheetTopPadding => _stage == _AddSheetStage.petOnboarding
      ? _petOnboardingTopPadding
      : _defaultSheetTopPadding;
  _AddSheetStage get _stage {
    if (_isPetOnboarding) {
      return _AddSheetStage.petOnboarding;
    }
    if (!_hasExpandedStage) {
      return _AddSheetStage.actions;
    }
    return _AddSheetStage.expandedForm;
  }

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(
      vsync: this,
      duration: _expandedTransitionDuration,
      reverseDuration: _expandedTransitionDuration,
    )..addStatusListener(_handleTransitionStatus);
  }

  @override
  void dispose() {
    _transitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasExpandedStage || _isCollapsing || _isPetOnboarding,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (_isPetOnboarding) {
          return;
        }
        _beginCollapseToActions();
      },
      child: AnimatedBuilder(
        animation: _transitionController,
        builder: (context, _) {
          final mediaQuery = MediaQuery.of(context);
          final availableHeight =
              mediaQuery.size.height - mediaQuery.padding.top - 12;
          final tokens = context.petNoteTokens;
          final shellProgress = _hasExpandedStage ? _sheetMotionProgress : 0.0;
          final sheetHeight =
              lerpDouble(_compactSheetHeight, availableHeight, shellProgress)!;

          return ClipRRect(
            key: const ValueKey('add_sheet_shell'),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(_sheetRadius)),
            child: Container(
              key: const ValueKey('add_sheet_surface'),
              height: sheetHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [tokens.pageGradientTop, tokens.pageGradientBottom],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: _stage == _AddSheetStage.petOnboarding
                        ? 0
                        : _actionsHorizontalInset,
                    right: _stage == _AddSheetStage.petOnboarding
                        ? 0
                        : _actionsHorizontalInset,
                    top: _sheetTopPadding,
                    bottom: mediaQuery.viewInsets.bottom + 18,
                  ),
                  child: _buildSheetContent(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSheetContent(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBody(),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: _buildHeaderTransition(context),
        ),
      ],
    );
  }

  Widget _buildHeaderTransition(BuildContext context) {
    final showExpandedHeader =
        (_hasExpandedStage || _isCollapsing) && !_isPetOnboarding;
    final showActionsHeader = !_hasExpandedStage || _shouldRevealActions;
    final expandedOpacity =
        _isCollapsing ? (1 - _actionsRevealOpacity).clamp(0.0, 1.0) : 1.0;
    final actionsOpacity =
        _hasExpandedStage ? _actionsRevealOpacity.clamp(0.0, 1.0) : 1.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _stage == _AddSheetStage.petOnboarding
            ? _actionsHorizontalInset
            : 0,
      ),
      child: SizedBox(
        key: const ValueKey('add_sheet_header_transition'),
        height: _headerOverlayHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showActionsHeader)
              _HeaderTransitionLayer(
                key: const ValueKey('add_sheet_actions_header_transition'),
                opacity: actionsOpacity,
                translateY: 10 * (1 - actionsOpacity),
                child: const _ActionsHeader(),
              ),
            if (showExpandedHeader)
              _HeaderTransitionLayer(
                key: const ValueKey('add_sheet_expanded_header_transition'),
                opacity: expandedOpacity,
                translateY: -8 * _actionsRevealOpacity,
                child: _ExpandedHeader(
                  title: _sheetTitle(_transitionAction),
                  onBack: _beginCollapseToActions,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedPage(BuildContext context, {Key? key}) {
    if (_isPetOnboarding) {
      return KeyedSubtree(
        key: key,
        child: PetOnboardingFlow(
          embedded: true,
          nativePetPhotoPicker: widget.nativePetPhotoPicker,
          enableEmbeddedPrimaryButtonHaptics: true,
          introHapticsDriver: _introHapticsDriver,
          onSubmit: _submitPetOnboarding,
          onDefer: _closePetOnboarding,
          onReturnToActions: _beginCollapseToActions,
        ),
      );
    }

    return KeyedSubtree(
      key: key,
      child: RepaintBoundary(
        key: const ValueKey('add_form_boundary'),
        child: ExpandedFormShell(
          topInset: _expandedContentTopInset,
          child: KeyedSubtree(
            key: ValueKey(
              '${_transitionAction.name}_${widget.store.pets.isEmpty}',
            ),
            child: _buildExpandedFormBody(_transitionAction),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_stage == _AddSheetStage.petOnboarding) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_stage == _AddSheetStage.actions || _shouldRevealActions)
            _buildActionsContent(
              interactive: false,
              opacity: _actionsRevealOpacity,
              opacityKey: const ValueKey('add_sheet_actions_reveal_opacity'),
              ignorePointerKey:
                  const ValueKey('add_sheet_actions_reveal_ignore_pointer'),
            ),
          _buildExpandedTransition(
            key: const ValueKey('manual_onboarding_sheet_transition'),
            child: _buildExpandedPage(
              context,
              key: const ValueKey('expanded_pet_page'),
            ),
          ),
        ],
      );
    }

    if (_stage == _AddSheetStage.actions) {
      return _buildActionsContent(
        interactive: true,
        opacity: 1,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_stage == _AddSheetStage.actions || _shouldRevealActions)
          _buildActionsContent(
            interactive: false,
            opacity: _actionsRevealOpacity,
            opacityKey: const ValueKey('add_sheet_actions_reveal_opacity'),
            ignorePointerKey:
                const ValueKey('add_sheet_actions_reveal_ignore_pointer'),
          ),
        _buildExpandedTransition(
          key: const ValueKey('manual_expanded_form_transition'),
          child: _buildExpandedPage(
            context,
            key: ValueKey('expanded_page_${_transitionAction.name}'),
          ),
        ),
      ],
    );
  }

  Widget _buildActionsContent({
    required bool interactive,
    required double opacity,
    ValueKey<String>? opacityKey,
    ValueKey<String>? ignorePointerKey,
  }) {
    final useReducedEffects = !interactive;
    final actionsContent = useReducedEffects
        ? ClipRect(
            child: SingleChildScrollView(
              key: const ValueKey('add_sheet_actions_content'),
              physics: const NeverScrollableScrollPhysics(),
              child: const Padding(
                padding: EdgeInsets.only(top: _actionsContentTopInset),
                child: _ActionGridPreview(),
              ),
            ),
          )
        : SingleChildScrollView(
            key: const ValueKey('add_sheet_actions_content'),
            child: Padding(
              padding: const EdgeInsets.only(top: _actionsContentTopInset),
              child: _ActionGrid(
                key: const ValueKey('actions'),
                onSelect: _selectAction,
              ),
            ),
          );

    return IgnorePointer(
      key: ignorePointerKey,
      ignoring: !interactive,
      child: KeyedSubtree(
        key: opacityKey,
        child: Opacity(
          opacity: opacity,
          child: Align(
            key: const ValueKey('add_actions_boundary'),
            alignment: Alignment.topCenter,
            child: RepaintBoundary(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _stage == _AddSheetStage.petOnboarding
                      ? _actionsHorizontalInset
                      : 0,
                ),
                child: actionsContent,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedFormBody(AddAction action) {
    if (widget.store.pets.isEmpty) {
      return MissingPetPrerequisite(
        action: action,
        onAddPet: () {
          _playPrimaryButtonTapHaptics();
          _openPetOnboarding();
        },
      );
    }

    return switch (action) {
      AddAction.todo =>
        TodoForm(key: const ValueKey('todo'), store: widget.store),
      AddAction.reminder =>
        ReminderForm(key: const ValueKey('reminder'), store: widget.store),
      AddAction.record => RecordForm(
          key: const ValueKey('record'),
          store: widget.store,
          nativePetPhotoPicker: widget.nativePetPhotoPicker,
        ),
      AddAction.pet => const SizedBox.shrink(),
      AddAction.none => const SizedBox.shrink(),
    };
  }

  Widget _buildExpandedTransition({
    required Key key,
    required Widget child,
  }) {
    return AnimatedBuilder(
      key: key,
      animation: _transitionController,
      child: child,
      builder: (context, expandedChild) {
        final progress = _sheetMotionProgress;
        final tokens = context.petNoteTokens;
        final foregroundOffset = 40.0 * (1 - progress);
        final foregroundSurfaceOpacity =
            _isCollapsing ? 1 - _actionsRevealOpacity : 1.0;

        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              ignoring: _isCollapsing || progress < 0.999,
              child: Transform.translate(
                offset: Offset(0, foregroundOffset),
                child: Opacity(
                  key: const ValueKey('add_sheet_foreground_surface_opacity'),
                  opacity: foregroundSurfaceOpacity.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    key: const ValueKey('add_sheet_foreground_surface'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          tokens.pageGradientTop,
                          tokens.pageGradientBottom,
                        ],
                      ),
                    ),
                    child: expandedChild,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submitPetOnboarding(PetOnboardingResult result) async {
    await widget.store.addPet(
      name: result.name,
      type: result.type,
      photoPath: result.photoPath,
      breed: result.breed,
      sex: result.sex,
      birthday: result.birthday,
      weightKg: result.weightKg,
      neuterStatus: result.neuterStatus,
      feedingPreferences: result.feedingPreferences,
      allergies: result.allergies,
      note: result.note,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _closePetOnboarding() async {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  void _handleTransitionStatus(AnimationStatus status) {
    if (!mounted) {
      return;
    }
    if (status == AnimationStatus.dismissed && _isCollapsing) {
      setState(() {
        _isCollapsing = false;
        _action = AddAction.none;
      });
    }
  }

  void _selectAction(AddAction action) {
    if (action == AddAction.none) {
      _beginCollapseToActions();
      return;
    }

    _transitionController.stop();
    setState(() {
      _isCollapsing = false;
      _action = action;
    });
    _transitionController.forward(from: 0);
  }

  void _beginCollapseToActions() {
    if (!_hasExpandedStage || _isCollapsing) {
      return;
    }
    setState(() {
      _isCollapsing = true;
    });
    if (_transitionController.value >= 1.0) {
      _transitionController.reverse();
      return;
    }
    _transitionController.reverse(from: _transitionController.value);
  }

  void _openPetOnboarding() {
    _transitionController.stop();
    setState(() {
      _isCollapsing = false;
      _action = AddAction.pet;
    });
  }

  void _playPrimaryButtonTapHaptics() {
    unawaited(_introHapticsDriver.playIntroPrimaryButtonTap());
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    super.key,
    required this.onSelect,
  });

  final ValueChanged<AddAction> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                title: '新增待办',
                subtitle: '补货、清洁和轻任务',
                icon: Icons.check_circle_outline_rounded,
                color: tokens.badgeBlueBackground,
                iconColor: tokens.badgeBlueForeground,
                onTap: () => onSelect(AddAction.todo),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                title: '新增提醒',
                subtitle: '疫苗、驱虫和复诊',
                icon: Icons.notifications_active_rounded,
                color: tokens.badgeGoldBackground,
                iconColor: tokens.badgeGoldForeground,
                onTap: () => onSelect(AddAction.reminder),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                title: '新增记录',
                subtitle: '病历、票据和照片',
                icon: Icons.description_rounded,
                color:
                    isDark ? const Color(0xFF271F3B) : const Color(0xFFF4EEFF),
                iconColor:
                    isDark ? const Color(0xFFD2BEFF) : const Color(0xFF7250D0),
                onTap: () => onSelect(AddAction.record),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                title: '新增爱宠',
                subtitle: '新建宠物完整档案',
                icon: Icons.pets_rounded,
                color:
                    isDark ? const Color(0xFF173126) : const Color(0xFFEAF8EF),
                iconColor:
                    isDark ? const Color(0xFF9EDBBC) : const Color(0xFF2F8B63),
                onTap: () => onSelect(AddAction.pet),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionGridPreview extends StatelessWidget {
  const _ActionGridPreview();

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionPreviewCard(
                title: '新增待办',
                subtitle: '补货、清洁和轻任务',
                icon: Icons.check_circle_outline_rounded,
                color: tokens.badgeBlueBackground,
                iconColor: tokens.badgeBlueForeground,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionPreviewCard(
                title: '新增提醒',
                subtitle: '疫苗、驱虫和复诊',
                icon: Icons.notifications_active_rounded,
                color: tokens.badgeGoldBackground,
                iconColor: tokens.badgeGoldForeground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionPreviewCard(
                title: '新增记录',
                subtitle: '病历、票据和照片',
                icon: Icons.description_rounded,
                color:
                    isDark ? const Color(0xFF271F3B) : const Color(0xFFF4EEFF),
                iconColor:
                    isDark ? const Color(0xFFD2BEFF) : const Color(0xFF7250D0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionPreviewCard(
                title: '新增爱宠',
                subtitle: '新建宠物完整档案',
                icon: Icons.pets_rounded,
                color:
                    isDark ? const Color(0xFF173126) : const Color(0xFFEAF8EF),
                iconColor:
                    isDark ? const Color(0xFF9EDBBC) : const Color(0xFF2F8B63),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderTransitionLayer extends StatelessWidget {
  const _HeaderTransitionLayer({
    super.key,
    required this.opacity,
    required this.translateY,
    required this.child,
  });

  final double opacity;
  final double translateY;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: opacity < 0.999,
      child: Transform.translate(
        offset: Offset(0, translateY),
        child: Opacity(
          opacity: opacity,
          child: child,
        ),
      ),
    );
  }
}

class _ActionsHeader extends StatelessWidget {
  const _ActionsHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    return Padding(
      key: const ValueKey('add_actions_header_boundary'),
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '新增内容',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: tokens.primaryText,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '今天要给毛孩子加点什么新内容？',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandedHeader extends StatelessWidget {
  const _ExpandedHeader({
    required this.title,
    required this.onBack,
  });

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  key: const ValueKey('expanded_form_back_button'),
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: tokens.secondaryText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: theme.textTheme.displaySmall?.copyWith(
            color: tokens.primaryText,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    return FrostedPanel(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icon, color: iconColor),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: tokens.primaryText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
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
        ),
      ),
    );
  }
}

class _ActionPreviewCard extends StatelessWidget {
  const _ActionPreviewCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.iconColor,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.panelBackground,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: tokens.panelBorder, width: 1.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: tokens.primaryText,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
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
    );
  }
}

String _sheetTitle(AddAction action) => switch (action) {
      AddAction.todo => '新增待办',
      AddAction.reminder => '新增提醒',
      AddAction.record => '新增记录',
      AddAction.pet => '新增爱宠',
      AddAction.none => '新增内容',
    };
