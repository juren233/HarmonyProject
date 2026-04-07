import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/app/pet_onboarding_overlay.dart';
import 'package:petnote/state/petnote_store.dart';

enum AddAction { none, todo, reminder, record, pet }

enum _AddSheetStage { actions, expandedForm, petOnboarding }

class AddActionSheet extends StatefulWidget {
  const AddActionSheet({
    super.key,
    required this.store,
  });

  final PetNoteStore store;

  @override
  State<AddActionSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<AddActionSheet>
    with SingleTickerProviderStateMixin {
  static const _compactSheetHeight = 448.0;
  static const _sheetRadius = 36.0;
  static const _expandedTransitionDuration = Duration(milliseconds: 360);
  static const _actionsRevealStart = 0.24;
  static const _headerOverlayHeight = 112.0;
  static const _actionsContentTopInset = 74.0;
  static const _expandedContentTopInset = 112.0;

  late final AnimationController _transitionController;
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
    return AnimatedBuilder(
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
                  left: 18,
                  right: 18,
                  top: 4,
                  bottom: mediaQuery.viewInsets.bottom + 18,
                ),
                child: _buildSheetContent(context),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSheetContent(BuildContext context) {
    if (_stage == _AddSheetStage.petOnboarding) {
      return _buildBody();
    }
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
    final showExpandedHeader = _hasExpandedStage || _isCollapsing;
    final showActionsHeader = !_hasExpandedStage || _shouldRevealActions;
    final expandedOpacity =
        _isCollapsing ? (1 - _actionsRevealOpacity).clamp(0.0, 1.0) : 1.0;
    final actionsOpacity =
        _hasExpandedStage ? _actionsRevealOpacity.clamp(0.0, 1.0) : 1.0;

    return SizedBox(
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
              child: _ActionsHeader(),
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
    );
  }

  Widget _buildExpandedPage(BuildContext context, {Key? key}) {
    if (_isPetOnboarding) {
      return KeyedSubtree(
        key: key,
        child: PetOnboardingFlow(
          embedded: true,
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
        child: _ExpandedFormShell(
          child: KeyedSubtree(
            key: ValueKey(
                '${_transitionAction.name}_${widget.store.pets.isEmpty}'),
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
              child: actionsContent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedFormBody(AddAction action) {
    if (widget.store.pets.isEmpty) {
      return _MissingPetPrerequisite(
        action: action,
        onAddPet: _openPetOnboarding,
      );
    }

    return switch (action) {
      AddAction.todo =>
        _TodoForm(key: const ValueKey('todo'), store: widget.store),
      AddAction.reminder =>
        _ReminderForm(key: const ValueKey('reminder'), store: widget.store),
      AddAction.record =>
        _RecordForm(key: const ValueKey('record'), store: widget.store),
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

class _TodoForm extends StatefulWidget {
  const _TodoForm({super.key, required this.store});

  final PetNoteStore store;

  @override
  State<_TodoForm> createState() => _TodoFormState();
}

class _TodoFormState extends State<_TodoForm> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  late String _petId;
  late DateTime _dueAt;
  late final TextEditingController _dueAtText;
  NotificationLeadTime _notificationLeadTime = NotificationLeadTime.none;

  @override
  void initState() {
    super.initState();
    _petId = widget.store.pets.first.id;
    _dueAt = _defaultFutureDateTime();
    _dueAtText = TextEditingController(text: formatDate(_dueAt));
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _dueAtText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ExpandedFormContent(
      actionLabel: '保存待办',
      actionColor: const Color(0xFF4F7BFF),
      onSubmit: () async {
        await widget.store.addTodo(
          title: _title.text.trim(),
          petId: _petId,
          dueAt: _dueAt,
          notificationLeadTime: _notificationLeadTime,
          note: _note.text.trim(),
        );
        if (!context.mounted) {
          return;
        }
        Navigator.pop(context);
      },
      child: SectionCard(
        title: '基础信息',
        children: [
          const SectionLabel(text: '标题'),
          HyperTextField(controller: _title, hintText: '例如：补货主粮'),
          const SectionLabel(text: '关联爱宠'),
          _PetSelector(
              pets: widget.store.pets,
              value: _petId,
              onChanged: (value) => setState(() => _petId = value)),
          const SectionLabel(text: '时间'),
          _AdaptiveDateTimeField(
            materialFieldKey: const ValueKey('todo_due_at_field'),
            iosDateFieldKey: const ValueKey('todo_due_date_field'),
            iosTimeFieldKey: const ValueKey('todo_due_time_field'),
            value: _dueAt,
            onPickDateTime: _pickDueAt,
            onPickDate: _pickDueDateOnIos,
            onPickTime: _pickDueTimeOnIos,
          ),
          const SectionLabel(text: '提前通知'),
          _ChoiceWrap<NotificationLeadTime>(
            values: NotificationLeadTime.values,
            selected: _notificationLeadTime,
            labelBuilder: notificationLeadTimeLabel,
            onChanged: (value) => setState(() => _notificationLeadTime = value),
          ),
          const SectionLabel(text: '备注'),
          HyperTextField(controller: _note, hintText: '记录一下补货偏好', maxLines: 3),
        ],
      ),
    );
  }

  Future<void> _pickDueAt() async {
    final nextDateTime = await _pickDateTime(context, initialValue: _dueAt);
    if (nextDateTime == null || !mounted) {
      return;
    }
    setState(() {
      _dueAt = nextDateTime;
      _dueAtText.text = formatDate(_dueAt);
    });
  }

  Future<void> _pickDueDateOnIos() async {
    final nextDate = await _pickCupertinoDate(context, initialValue: _dueAt);
    if (nextDate == null || !mounted) {
      return;
    }
    setState(() {
      _dueAt = DateTime(
        nextDate.year,
        nextDate.month,
        nextDate.day,
        _dueAt.hour,
        _dueAt.minute,
      );
      _dueAtText.text = formatDate(_dueAt);
    });
  }

  Future<void> _pickDueTimeOnIos() async {
    final nextDateTime =
        await _pickCupertinoTime(context, initialValue: _dueAt);
    if (nextDateTime == null || !mounted) {
      return;
    }
    setState(() {
      _dueAt = DateTime(
        _dueAt.year,
        _dueAt.month,
        _dueAt.day,
        nextDateTime.hour,
        nextDateTime.minute,
      );
      _dueAtText.text = formatDate(_dueAt);
    });
  }
}

class _ReminderForm extends StatefulWidget {
  const _ReminderForm({super.key, required this.store});

  final PetNoteStore store;

  @override
  State<_ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<_ReminderForm> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _recurrence = TextEditingController(text: '单次');
  late String _petId;
  ReminderKind _kind = ReminderKind.custom;
  late DateTime _scheduledAt;
  late final TextEditingController _scheduledAtText;
  NotificationLeadTime _notificationLeadTime = NotificationLeadTime.none;

  @override
  void initState() {
    super.initState();
    _petId = widget.store.pets.first.id;
    _scheduledAt = _defaultFutureDateTime();
    _scheduledAtText = TextEditingController(text: formatDate(_scheduledAt));
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _recurrence.dispose();
    _scheduledAtText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ExpandedFormContent(
      actionLabel: '保存提醒',
      actionColor: const Color(0xFFF2A65A),
      onSubmit: () async {
        await widget.store.addReminder(
          title: _title.text.trim(),
          petId: _petId,
          scheduledAt: _scheduledAt,
          notificationLeadTime: _notificationLeadTime,
          kind: _kind,
          recurrence: _recurrence.text.trim(),
          note: _note.text.trim(),
        );
        if (!context.mounted) {
          return;
        }
        Navigator.pop(context);
      },
      child: SectionCard(
        title: '提醒信息',
        children: [
          const SectionLabel(text: '标题'),
          HyperTextField(controller: _title, hintText: '例如：体内驱虫'),
          const SectionLabel(text: '关联爱宠'),
          _PetSelector(
              pets: widget.store.pets,
              value: _petId,
              onChanged: (value) => setState(() => _petId = value)),
          const SectionLabel(text: '提醒类型'),
          _ChoiceWrap<ReminderKind>(
            values: ReminderKind.values,
            selected: _kind,
            labelBuilder: _reminderKindLabel,
            onChanged: (value) => setState(() => _kind = value),
          ),
          const SectionLabel(text: '时间'),
          _AdaptiveDateTimeField(
            materialFieldKey: const ValueKey('reminder_scheduled_at_field'),
            iosDateFieldKey: const ValueKey('reminder_scheduled_date_field'),
            iosTimeFieldKey: const ValueKey('reminder_scheduled_time_field'),
            value: _scheduledAt,
            onPickDateTime: _pickScheduledAt,
            onPickDate: _pickScheduledDateOnIos,
            onPickTime: _pickScheduledTimeOnIos,
          ),
          const SectionLabel(text: '提前通知'),
          _ChoiceWrap<NotificationLeadTime>(
            values: NotificationLeadTime.values,
            selected: _notificationLeadTime,
            labelBuilder: notificationLeadTimeLabel,
            onChanged: (value) => setState(() => _notificationLeadTime = value),
          ),
          const SectionLabel(text: '重复规则'),
          HyperTextField(controller: _recurrence),
          const SectionLabel(text: '备注'),
          HyperTextField(controller: _note, maxLines: 3),
        ],
      ),
    );
  }

  Future<void> _pickScheduledAt() async {
    final nextDateTime =
        await _pickDateTime(context, initialValue: _scheduledAt);
    if (nextDateTime == null || !mounted) {
      return;
    }
    setState(() {
      _scheduledAt = nextDateTime;
      _scheduledAtText.text = formatDate(_scheduledAt);
    });
  }

  Future<void> _pickScheduledDateOnIos() async {
    final nextDate =
        await _pickCupertinoDate(context, initialValue: _scheduledAt);
    if (nextDate == null || !mounted) {
      return;
    }
    setState(() {
      _scheduledAt = DateTime(
        nextDate.year,
        nextDate.month,
        nextDate.day,
        _scheduledAt.hour,
        _scheduledAt.minute,
      );
      _scheduledAtText.text = formatDate(_scheduledAt);
    });
  }

  Future<void> _pickScheduledTimeOnIos() async {
    final nextDateTime =
        await _pickCupertinoTime(context, initialValue: _scheduledAt);
    if (nextDateTime == null || !mounted) {
      return;
    }
    setState(() {
      _scheduledAt = DateTime(
        _scheduledAt.year,
        _scheduledAt.month,
        _scheduledAt.day,
        nextDateTime.hour,
        nextDateTime.minute,
      );
      _scheduledAtText.text = formatDate(_scheduledAt);
    });
  }
}

class _RecordForm extends StatefulWidget {
  const _RecordForm({super.key, required this.store});

  final PetNoteStore store;

  @override
  State<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<_RecordForm> {
  final _title = TextEditingController();
  final _summary = TextEditingController();
  final _note = TextEditingController();
  late String _petId;
  PetRecordType _type = PetRecordType.other;
  late DateTime _recordDate;
  late final TextEditingController _recordDateText;

  @override
  void initState() {
    super.initState();
    _petId = widget.store.pets.first.id;
    _recordDate = DateTime.now();
    _recordDateText = TextEditingController(text: formatDate(_recordDate));
  }

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _note.dispose();
    _recordDateText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ExpandedFormContent(
      actionLabel: '保存记录',
      actionColor: const Color(0xFF4FB57C),
      onSubmit: () async {
        await widget.store.addRecord(
          petId: _petId,
          type: _type,
          title: _title.text.trim(),
          recordDate: _recordDate,
          summary: _summary.text.trim(),
          note: _note.text.trim(),
        );
        if (!context.mounted) {
          return;
        }
        Navigator.pop(context);
      },
      child: SectionCard(
        title: '资料信息',
        children: [
          const SectionLabel(text: '关联爱宠'),
          _PetSelector(
              pets: widget.store.pets,
              value: _petId,
              onChanged: (value) => setState(() => _petId = value)),
          const SectionLabel(text: '记录类型'),
          _ChoiceWrap<PetRecordType>(
            values: PetRecordType.values,
            selected: _type,
            labelBuilder: _recordTypeLabel,
            onChanged: (value) => setState(() => _type = value),
          ),
          const SectionLabel(text: '标题'),
          HyperTextField(controller: _title, hintText: '例如：体检结果'),
          const SectionLabel(text: '时间'),
          _AdaptiveDateTimeField(
            materialFieldKey: const ValueKey('record_date_field'),
            iosDateFieldKey: const ValueKey('record_date_date_field'),
            iosTimeFieldKey: const ValueKey('record_date_time_field'),
            value: _recordDate,
            onPickDateTime: _pickRecordDate,
            onPickDate: _pickRecordDateOnIos,
            onPickTime: _pickRecordTimeOnIos,
          ),
          const SectionLabel(text: '摘要'),
          HyperTextField(controller: _summary, maxLines: 3),
          const SectionLabel(text: '备注'),
          HyperTextField(controller: _note, maxLines: 3),
        ],
      ),
    );
  }

  Future<void> _pickRecordDate() async {
    final nextDateTime =
        await _pickDateTime(context, initialValue: _recordDate);
    if (nextDateTime == null || !mounted) {
      return;
    }
    setState(() {
      _recordDate = nextDateTime;
      _recordDateText.text = formatDate(_recordDate);
    });
  }

  Future<void> _pickRecordDateOnIos() async {
    final nextDate =
        await _pickCupertinoDate(context, initialValue: _recordDate);
    if (nextDate == null || !mounted) {
      return;
    }
    setState(() {
      _recordDate = DateTime(
        nextDate.year,
        nextDate.month,
        nextDate.day,
        _recordDate.hour,
        _recordDate.minute,
      );
      _recordDateText.text = formatDate(_recordDate);
    });
  }

  Future<void> _pickRecordTimeOnIos() async {
    final nextDateTime =
        await _pickCupertinoTime(context, initialValue: _recordDate);
    if (nextDateTime == null || !mounted) {
      return;
    }
    setState(() {
      _recordDate = DateTime(
        _recordDate.year,
        _recordDate.month,
        _recordDate.day,
        nextDateTime.hour,
        nextDateTime.minute,
      );
      _recordDateText.text = formatDate(_recordDate);
    });
  }
}

class _PetForm extends StatefulWidget {
  const _PetForm({required this.store});

  final PetNoteStore store;

  @override
  State<_PetForm> createState() => _PetFormState();
}

class _PetFormState extends State<_PetForm> {
  final _name = TextEditingController();
  final _breed = TextEditingController();
  final _sex = TextEditingController(text: '未填写');
  final _birthday = TextEditingController(text: '2026-03-24');
  final _weight = TextEditingController(text: '3.5');
  final _feeding = TextEditingController();
  final _allergies = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _sex.dispose();
    _birthday.dispose();
    _weight.dispose();
    _feeding.dispose();
    _allergies.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FormShell(
      title: '新增爱宠',
      child: Column(
        children: [
          SectionCard(
            title: '档案信息',
            children: [
              const SectionLabel(text: '名字'),
              HyperTextField(controller: _name),
              const SectionLabel(text: '品种'),
              HyperTextField(controller: _breed),
              const SectionLabel(text: '性别'),
              HyperTextField(controller: _sex),
              const SectionLabel(text: '生日'),
              HyperTextField(controller: _birthday),
              const SectionLabel(text: '体重'),
              HyperTextField(controller: _weight),
              const SectionLabel(text: '喂养偏好'),
              HyperTextField(controller: _feeding, maxLines: 3),
              const SectionLabel(text: '过敏/禁忌'),
              HyperTextField(controller: _allergies, maxLines: 3),
              const SectionLabel(text: '备注'),
              HyperTextField(controller: _note, maxLines: 3),
            ],
          ),
          FilledButton(
            onPressed: () async {
              await widget.store.addPet(
                name: _name.text.trim(),
                type: PetType.other,
                breed: _breed.text.trim(),
                sex: _sex.text.trim(),
                birthday: _birthday.text.trim(),
                weightKg: double.tryParse(_weight.text.trim()) ?? 0,
                neuterStatus: PetNeuterStatus.unknown,
                feedingPreferences: _feeding.text.trim(),
                allergies: _allergies.text.trim(),
                note: _note.text.trim(),
              );
              if (!context.mounted) {
                return;
              }
              Navigator.pop(context);
            },
            child: const Text('保存爱宠'),
          ),
        ],
      ),
    );
  }
}

class _FormShell extends StatelessWidget {
  const _FormShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF17181C),
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _ExpandedFormShell extends StatelessWidget {
  const _ExpandedFormShell({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.only(top: _AddSheetState._expandedContentTopInset),
      child: child,
    );
  }
}

class _ExpandedFormContent extends StatelessWidget {
  const _ExpandedFormContent({
    required this.child,
    required this.actionLabel,
    required this.onSubmit,
    required this.actionColor,
  });

  final Widget child;
  final String actionLabel;
  final Future<void> Function() onSubmit;
  final Color actionColor;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottomInset + 24),
            child: child,
          ),
        ),
        const SizedBox(height: 16),
        SafeArea(
          top: false,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: actionColor,
              foregroundColor: Colors.white,
            ),
            onPressed: onSubmit,
            child: Text(actionLabel),
          ),
        ),
      ],
    );
  }
}

class _AdaptiveDateTimeField extends StatelessWidget {
  const _AdaptiveDateTimeField({
    required this.materialFieldKey,
    required this.iosDateFieldKey,
    required this.iosTimeFieldKey,
    required this.value,
    required this.onPickDateTime,
    required this.onPickDate,
    required this.onPickTime,
  });

  final Key materialFieldKey;
  final Key iosDateFieldKey;
  final Key iosTimeFieldKey;
  final DateTime value;
  final Future<void> Function() onPickDateTime;
  final Future<void> Function() onPickDate;
  final Future<void> Function() onPickTime;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.iOS) {
      final tokens = context.petNoteTokens;
      return InkWell(
        key: materialFieldKey,
        borderRadius: BorderRadius.circular(22),
        onTap: onPickDateTime,
        child: InputDecorator(
          decoration: const InputDecoration(),
          child: Text(
            formatDate(value),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: tokens.primaryText,
                ),
          ),
        ),
      );
    }

    final tokens = context.petNoteTokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.panelBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tokens.panelBorder, width: 1.1),
      ),
      child: Column(
        children: [
          _IosPickerRow(
            key: iosDateFieldKey,
            icon: CupertinoIcons.calendar,
            label: '日期',
            value: _formatIosDate(value),
            onTap: onPickDate,
          ),
          Divider(height: 1, color: tokens.panelBorder),
          _IosPickerRow(
            key: iosTimeFieldKey,
            icon: CupertinoIcons.time,
            label: '时间',
            value: _formatIosTime(value),
            onTap: onPickTime,
          ),
        ],
      ),
    );
  }
}

class _IosPickerRow extends StatelessWidget {
  const _IosPickerRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: tokens.secondaryText, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: tokens.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

DateTime _defaultFutureDateTime() {
  final now = DateTime.now().add(const Duration(hours: 1));
  final nextMinute = ((now.minute / 5).ceil() * 5) % 60;
  final nextHour = nextMinute == 0 ? now.hour + 1 : now.hour;
  return DateTime(
    now.year,
    now.month,
    now.day,
    nextHour,
    nextMinute,
  );
}

Future<DateTime?> _pickDateTime(
  BuildContext context, {
  required DateTime initialValue,
}) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initialValue,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );
  if (date == null || !context.mounted) {
    return null;
  }

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initialValue),
  );
  if (time == null) {
    return null;
  }

  return DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
}

Future<DateTime?> _pickCupertinoDate(
  BuildContext context, {
  required DateTime initialValue,
}) {
  return _showCupertinoPickerSheet(
    context,
    initialValue: initialValue,
    mode: CupertinoDatePickerMode.date,
  );
}

Future<DateTime?> _pickCupertinoTime(
  BuildContext context, {
  required DateTime initialValue,
}) {
  return _showCupertinoPickerSheet(
    context,
    initialValue: initialValue,
    mode: CupertinoDatePickerMode.time,
  );
}

Future<DateTime?> _showCupertinoPickerSheet(
  BuildContext context, {
  required DateTime initialValue,
  required CupertinoDatePickerMode mode,
}) {
  var pickedValue = initialValue;
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (popupContext) {
      final brightness = Theme.of(context).brightness;
      final backgroundColor = brightness == Brightness.dark
          ? const Color(0xFF1C1C1E)
          : Colors.white;
      return Container(
        height: 320,
        padding: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(popupContext).pop(),
                    child: const Text('取消'),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () =>
                        Navigator.of(popupContext).pop(pickedValue),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: mode,
                use24hFormat: false,
                initialDateTime: initialValue,
                onDateTimeChanged: (value) {
                  pickedValue = value;
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

String _formatIosDate(DateTime value) {
  final now = DateTime.now();
  final isToday = value.year == now.year &&
      value.month == now.month &&
      value.day == now.day;
  if (isToday) {
    return '今天';
  }
  return '${value.year}年${value.month}月${value.day}日';
}

String _formatIosTime(DateTime value) {
  final period = value.hour < 12 ? '上午' : '下午';
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  return '$period $hour:$minute';
}

class _MissingPetPrerequisite extends StatelessWidget {
  const _MissingPetPrerequisite({
    required this.action,
    required this.onAddPet,
  });

  final AddAction action;
  final VoidCallback onAddPet;

  @override
  Widget build(BuildContext context) {
    final message = switch (action) {
      AddAction.todo => '待办需要先关联一只爱宠，建好第一份档案后再安排补货、清洁和轻任务。',
      AddAction.reminder => '提醒需要先关联一只爱宠，建好第一份档案后再安排疫苗、驱虫和复诊。',
      AddAction.record => '记录需要先关联一只爱宠，建好第一份档案后再保存病历、票据和照片。',
      AddAction.pet => '先完成第一只爱宠建档。',
      AddAction.none => '先添加第一只爱宠。',
    };

    return EmptyCard(
      title: '先添加第一只爱宠',
      subtitle: message,
      actionLabel: '开始添加宠物',
      onAction: onAddPet,
    );
  }
}

class _PetSelector extends StatelessWidget {
  const _PetSelector({
    required this.pets,
    required this.value,
    required this.onChanged,
  });

  final List<Pet> pets;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: pets
          .map(
            (pet) => GestureDetector(
              onTap: () => onChanged(pet.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: value == pet.id
                      ? tokens.segmentedSelectedBackground
                      : tokens.secondarySurface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  pet.name,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: value == pet.id
                            ? Colors.white
                            : tokens.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ChoiceWrap<T> extends StatelessWidget {
  const _ChoiceWrap({
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: values
          .map(
            (value) => GestureDetector(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected == value
                      ? tokens.segmentedSelectedBackground
                      : tokens.secondarySurface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  labelBuilder(value),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected == value
                            ? Colors.white
                            : tokens.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          )
          .toList(),
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

String _reminderKindLabel(ReminderKind kind) => switch (kind) {
      ReminderKind.vaccine => '疫苗',
      ReminderKind.deworming => '驱虫',
      ReminderKind.medication => '用药',
      ReminderKind.review => '复诊',
      ReminderKind.grooming => '洗护',
      ReminderKind.custom => '自定义',
    };

String _recordTypeLabel(PetRecordType type) => switch (type) {
      PetRecordType.medical => '病历',
      PetRecordType.receipt => '票据',
      PetRecordType.image => '图片',
      PetRecordType.testResult => '检查结果',
      PetRecordType.other => '其他',
    };
