import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/layout_metrics.dart';
import 'package:petnote/app/pet_onboarding_taxonomy.dart';
import 'package:petnote/state/petnote_store.dart';

class PetOnboardingResult {
  const PetOnboardingResult({
    required this.name,
    required this.type,
    required this.breed,
    required this.sex,
    required this.birthday,
    required this.weightKg,
    required this.neuterStatus,
    required this.feedingPreferences,
    required this.allergies,
    required this.note,
  });

  final String name;
  final PetType type;
  final String breed;
  final String sex;
  final String birthday;
  final double weightKg;
  final PetNeuterStatus neuterStatus;
  final String feedingPreferences;
  final String allergies;
  final String note;
}

class PetOnboardingOverlay extends StatefulWidget {
  const PetOnboardingOverlay({
    super.key,
    required this.onSubmit,
    required this.onDefer,
    this.animateInitialEntry = true,
    this.externalRevealProgress,
    this.onReturnToIntro,
  });

  final Future<void> Function(PetOnboardingResult result) onSubmit;
  final Future<void> Function() onDefer;
  final bool animateInitialEntry;
  final double? externalRevealProgress;
  final VoidCallback? onReturnToIntro;

  @override
  State<PetOnboardingOverlay> createState() => _PetOnboardingOverlayState();
}

class _PetOnboardingOverlayState extends State<PetOnboardingOverlay> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final isDark = theme.brightness == Brightness.dark;
    final transitionOpacity = _transitionOpacity();

    return SizedBox.expand(
      child: Material(
        key: const ValueKey('first_launch_onboarding_overlay'),
        color: theme.scaffoldBackgroundColor.withValues(
          alpha: isDark ? 0.92 : 0.80,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [tokens.pageGradientTop, tokens.pageGradientBottom],
            ),
          ),
          child: Opacity(
            key: const ValueKey('onboarding_transition_opacity'),
            opacity: transitionOpacity,
            child: PetOnboardingFlow(
              animateInitialEntry: widget.animateInitialEntry,
              externalRevealProgress: widget.externalRevealProgress,
              onSubmit: widget.onSubmit,
              onDefer: widget.onDefer,
              onReturnToIntro: widget.onReturnToIntro,
            ),
          ),
        ),
      ),
    );
  }

  double _transitionOpacity() {
    final progress = widget.externalRevealProgress;
    if (progress == null) {
      return 1.0;
    }
    if (progress <= 0.58) {
      return 0.0;
    }
    return Curves.easeOutCubic.transform(
      ((progress - 0.58) / 0.22).clamp(0.0, 1.0),
    );
  }
}

class PetOnboardingFlow extends StatefulWidget {
  const PetOnboardingFlow({
    super.key,
    required this.onSubmit,
    required this.onDefer,
    this.animateInitialEntry = true,
    this.externalRevealProgress,
    this.embedded = false,
    this.onReturnToActions,
    this.onReturnToIntro,
  });

  final Future<void> Function(PetOnboardingResult result) onSubmit;
  final Future<void> Function() onDefer;
  final bool animateInitialEntry;
  final double? externalRevealProgress;
  final bool embedded;
  final VoidCallback? onReturnToActions;
  final VoidCallback? onReturnToIntro;

  @override
  State<PetOnboardingFlow> createState() => _PetOnboardingFlowState();
}

class _PetOnboardingFlowState extends State<PetOnboardingFlow>
    with TickerProviderStateMixin {
  final _name = TextEditingController();
  final _customBreed = TextEditingController();
  final _feeding = TextEditingController();
  final _allergies = TextEditingController();
  final _note = TextEditingController();
  final _weight = TextEditingController();
  late final PageController _stepPageController;
  late final AnimationController _entryController;

  int _stepIndex = 0;
  PetType? _type;
  String? _breed;
  String? _sex;
  DateTime? _birthday;
  late DateTime _birthdayDisplayedMonth;
  PetNeuterStatus? _neuterStatus;
  bool _isSubmitting = false;

  static const List<_StepCopy> _steps = [
    _StepCopy('先认识一下', '先给爱宠起个名字，并告诉我它是什么类型。'),
    _StepCopy('选择品种', '根据类型给你准备了常见品种，也可以直接自填。'),
    _StepCopy('记录性别', '完善基础档案，让后续信息更准确。'),
    _StepCopy('选择生日', '用日期选择器记录生日，后续更方便查看成长阶段。'),
    _StepCopy('补充体重', '体重用 kg 记录，先填当前最接近的一次就可以。'),
    _StepCopy('绝育状态', '这一步可以跳过，后面随时还能再补。'),
    _StepCopy('喂养偏好', '饮食习惯、主粮口味和喂养方式都可以记下来。'),
    _StepCopy('过敏 / 禁忌', '已知过敏原或需要回避的食物、药物都可以先补充。'),
    _StepCopy('最后备注', '把容易忘的小提醒留在这里，保存后就会生成第一份档案。'),
  ];

  @override
  void initState() {
    super.initState();
    _stepPageController = PageController();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
      value: widget.animateInitialEntry ? 0 : 1,
    );
    _birthdayDisplayedMonth = _monthDate(DateTime.now());
    if (widget.animateInitialEntry) {
      _entryController.forward();
    }
    for (final controller in [
      _name,
      _customBreed,
      _feeding,
      _allergies,
      _note,
      _weight
    ]) {
      controller.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _customBreed,
      _feeding,
      _allergies,
      _note,
      _weight
    ]) {
      controller.removeListener(_onFieldChanged);
    }
    _name.dispose();
    _customBreed.dispose();
    _feeding.dispose();
    _allergies.dispose();
    _note.dispose();
    _weight.dispose();
    _stepPageController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  bool get _canContinue => _canContinueFor(_stepIndex);

  bool _canContinueFor(int stepIndex) {
    switch (stepIndex) {
      case 0:
        return _name.text.trim().isNotEmpty && _type != null;
      case 1:
        if (_breed == null) {
          return false;
        }
        if (_breed == otherBreedLabel) {
          return _customBreed.text.trim().isNotEmpty;
        }
        return true;
      case 2:
        return _sex != null;
      case 3:
        return _birthday != null;
      case 4:
        final parsed = double.tryParse(_weight.text.trim());
        return parsed != null && parsed > 0;
      case 5:
      case 6:
      case 7:
      case 8:
        return true;
      default:
        return false;
    }
  }

  bool _showSkipButtonFor(int stepIndex) {
    return stepIndex >= 5 && stepIndex <= 7;
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewPaddingOf(context);
    final topInset = widget.embedded ? 20.0 : insets.top + 12;
    final bottomInset = widget.embedded ? 8.0 : insets.bottom + 20;

    final externalRevealProgress = _externalRevealProgress();

    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: AnimatedBuilder(
        animation: _entryController,
        builder: (context, _) {
          return SizedBox.expand(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    onboardingPageHorizontalPadding,
                    topInset,
                    onboardingPageHorizontalPadding,
                    0,
                  ),
                  child: _buildEntranceReveal(
                    key: const ValueKey('onboarding_top_bar_reveal'),
                    progress: widget.animateInitialEntry
                        ? _stageProgress(_entryController.value, 0.02, 0.54)
                        : externalRevealProgress,
                    offsetY: 0,
                    child: _buildTopBar(context),
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: PageView.builder(
                    key: const ValueKey('onboarding_step_page_view'),
                    controller: _stepPageController,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _steps.length,
                    itemBuilder: (context, index) {
                      return _buildStepPage(context, index, bottomInset);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final isDark = theme.brightness == Brightness.dark;
    final progressFrameBorderColor = isDark
        ? tokens.primaryText.withValues(alpha: 0.24)
        : const Color(0xFFDCCDBA);
    final progressFrameBackground =
        isDark ? const Color(0xFF0E1014) : const Color(0xFFFCF8F2);
    final progressTrackColor =
        isDark ? const Color(0xFF181C22) : const Color(0xFFECE3D7);
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: _stepIndex > 0
                ? IconButton(
                    onPressed: _isSubmitting ? null : _goBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: tokens.secondaryText,
                  )
                : (widget.embedded && widget.onReturnToActions != null)
                    ? IconButton(
                        key: const ValueKey(
                            'onboarding_return_to_actions_button'),
                        onPressed:
                            _isSubmitting ? null : widget.onReturnToActions,
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: tokens.secondaryText,
                      )
                    : (widget.onReturnToIntro != null)
                        ? IconButton(
                            key: const ValueKey(
                                'onboarding_return_to_intro_button'),
                            onPressed:
                                _isSubmitting ? null : widget.onReturnToIntro,
                            icon: const Icon(Icons.arrow_back_rounded),
                            color: tokens.secondaryText,
                          )
                        : null,
          ),
          Expanded(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: DecoratedBox(
                    key: const ValueKey('onboarding_progress_frame'),
                    decoration: BoxDecoration(
                      color: progressFrameBackground,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: progressFrameBorderColor,
                        width: 2.2,
                      ),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: const Color(0xFFEDD7B8)
                                    .withValues(alpha: 0.24),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: _AnimatedPipelineProgressBar(
                          key: const ValueKey('onboarding_progress_bar'),
                          progress: (_stepIndex + 1) / _steps.length,
                          height: 8,
                          trackColor: progressTrackColor,
                          fillColor: theme.colorScheme.primary,
                          glowColor: isDark
                              ? Colors.white.withValues(alpha: 0.16)
                              : Colors.white.withValues(alpha: 0.38),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: TextButton(
              key: const ValueKey('onboarding_defer_button'),
              onPressed: _isSubmitting ? null : widget.onDefer,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '稍后',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: tokens.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCardFor(BuildContext context, int stepIndex) {
    if (stepIndex == 3) {
      return _buildBirthdayStepCard(context, stepIndex);
    }
    return SectionCard(
      title: '步骤 ${stepIndex + 1}',
      children: switch (stepIndex) {
        0 => _identityStep(),
        1 => _breedStep(),
        2 => _sexStep(),
        3 => _birthdayStep(),
        4 => _weightStep(),
        5 => _neuterStep(),
        6 => _textAreaStep(
            label: '喂养偏好',
            controller: _feeding,
            hintText: '比如主粮口味、喂食频率、零食偏好',
          ),
        7 => _textAreaStep(
            label: '过敏 / 禁忌',
            controller: _allergies,
            hintText: '比如鸡肉敏感、对某些零食不耐受',
          ),
        _ => _textAreaStep(
            label: '备注',
            controller: _note,
            hintText: '比如洗澡会紧张、外出需要安抚等',
          ),
      },
    );
  }

  Widget _buildBirthdayStepCard(BuildContext context, int stepIndex) {
    return SectionCard(
      title: '步骤 ${stepIndex + 1}',
      trailing: _buildBirthdayYearButton(context),
      children: _birthdayStep(),
    );
  }

  Widget _buildStepPage(BuildContext context, int index, double bottomInset) {
    final step = _steps[index];
    final isFirstStep = index == 0;
    final isCurrentStep = index == _stepIndex;
    final externalRevealProgress = _externalRevealProgress();
    final contentProgress = isFirstStep
        ? widget.animateInitialEntry
            ? _stageProgress(_entryController.value, 0.08, 0.72)
            : externalRevealProgress
        : 1.0;
    final actionProgress = isFirstStep
        ? widget.animateInitialEntry
            ? _stageProgress(_entryController.value, 0.22, 0.84)
            : externalRevealProgress
        : 1.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        onboardingPageHorizontalPadding,
        0,
        onboardingPageHorizontalPadding,
        bottomInset,
      ),
      child: Column(
        key: ValueKey('onboarding_step_page_$index'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEntranceReveal(
            key: isFirstStep
                ? const ValueKey('onboarding_first_step_content_reveal')
                : ValueKey('onboarding_step_${index}_content_reveal'),
            progress: contentProgress,
            offsetY: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: context.petNoteTokens.primaryText,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  step.subtitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: context.petNoteTokens.secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          Expanded(
            child: _buildEntranceReveal(
              progress: contentProgress,
              offsetY: 18,
              child: SingleChildScrollView(
                child: _buildStepCardFor(context, index),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildEntranceReveal(
            key: isFirstStep
                ? const ValueKey('onboarding_first_step_actions_reveal')
                : ValueKey('onboarding_step_${index}_actions_reveal'),
            progress: actionProgress,
            offsetY: 20,
            child: Column(
              children: [
                if (_showSkipButtonFor(index))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        key: isCurrentStep
                            ? const ValueKey('onboarding_skip_button')
                            : null,
                        onPressed: !isCurrentStep || _isSubmitting
                            ? null
                            : _skipCurrentStep,
                        child: const Text('跳过'),
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: isCurrentStep
                        ? ValueKey(
                            index == _steps.length - 1
                                ? 'onboarding_save_button'
                                : 'onboarding_continue_button',
                          )
                        : null,
                    onPressed: !isCurrentStep || _isSubmitting
                        ? null
                        : index == _steps.length - 1
                            ? _save
                            : (_canContinue ? _goNext : null),
                    child: Text(index == _steps.length - 1 ? '保存爱宠' : '继续'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _identityStep() {
    return [
      const SectionLabel(text: '名字'),
      HyperTextField(
        key: const ValueKey('onboarding_name_field'),
        controller: _name,
        hintText: '给爱宠起个名字',
      ),
      const SectionLabel(text: '宠物类型'),
      _OptionWrap<PetType>(
        values: PetType.values,
        selected: _type,
        labelBuilder: petTypeLabel,
        onTap: (value) => setState(() {
          _type = value;
          _breed = null;
          _customBreed.clear();
        }),
      ),
    ];
  }

  List<Widget> _breedStep() {
    final type = _type ?? PetType.other;
    final presets = petBreedPresets[type] ?? const [otherBreedLabel];
    return [
      SectionLabel(text: '${petTypeLabel(type)}的常见品种'),
      _OptionWrap<String>(
        values: presets,
        selected: _breed,
        labelBuilder: (value) => value,
        onTap: (value) => setState(() => _breed = value),
      ),
      if (_breed == otherBreedLabel) ...[
        const SectionLabel(text: '自定义品种'),
        HyperTextField(
          key: const ValueKey('onboarding_custom_breed_field'),
          controller: _customBreed,
          hintText: '输入具体品种或描述',
        ),
      ],
    ];
  }

  List<Widget> _sexStep() {
    return [
      const SectionLabel(text: '性别'),
      _OptionWrap<String>(
        values: const ['公', '母'],
        selected: _sex,
        labelBuilder: (value) => value,
        onTap: (value) => setState(() => _sex = value),
      ),
    ];
  }

  List<Widget> _birthdayStep() {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 25);
    final latestBirthday = DateTime(now.year + 25, 12, 31);
    final calendarTheme = theme.copyWith(
      datePickerTheme: DatePickerThemeData(
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return theme.colorScheme.secondary;
          }
          return tokens.primaryText;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return Colors.transparent;
        }),
        todayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return theme.colorScheme.secondary;
          }
          return tokens.primaryText;
        }),
        todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return Colors.transparent;
        }),
        todayBorder: BorderSide.none,
      ),
    );
    return [
      Text(
        _birthday == null
            ? '请选择生日'
            : '已选择 ${_formatBirthdayDisplay(_birthday!)}',
        style: TextStyle(
          color: tokens.primaryText,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 12),
      Theme(
        data: calendarTheme,
        child: _VerticalDragLock(
          child: _OnboardingBirthdayCalendar(
            key: const ValueKey('onboarding_birthday_calendar'),
            selectedDate: _birthday,
            displayedMonth: _birthdayDisplayedMonth,
            currentDate: now,
            firstDate: firstDate,
            lastDate: latestBirthday,
            onDateChanged: _setBirthday,
            onDisplayedMonthChanged: _setBirthdayDisplayedMonth,
          ),
        ),
      ),
    ];
  }

  Widget _buildBirthdayYearButton(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final displayedYear = (_birthday ?? _birthdayDisplayedMonth).year;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('onboarding_birthday_year_button'),
        borderRadius: BorderRadius.circular(16),
        onTap: _isSubmitting ? null : _pickBirthdayYear,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: tokens.secondarySurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.panelBorder, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '年份',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: tokens.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$displayedYear',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.unfold_more_rounded,
                size: 18,
                color: tokens.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _weightStep() {
    return [
      const SectionLabel(text: '当前体重（kg）'),
      TextField(
        key: const ValueKey('onboarding_weight_field'),
        controller: _weight,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(hintText: '例如 4.2'),
      ),
    ];
  }

  List<Widget> _neuterStep() {
    return [
      const SectionLabel(text: '绝育状态'),
      _OptionWrap<PetNeuterStatus>(
        values: const [
          PetNeuterStatus.neutered,
          PetNeuterStatus.notNeutered,
        ],
        selected: _neuterStatus,
        labelBuilder: petNeuterStatusLabel,
        onTap: (value) => setState(() => _neuterStatus = value),
      ),
    ];
  }

  List<Widget> _textAreaStep({
    required String label,
    required TextEditingController controller,
    required String hintText,
  }) {
    return [
      SectionLabel(text: label),
      HyperTextField(
        controller: controller,
        hintText: hintText,
        maxLines: 4,
      ),
    ];
  }

  void _goNext() {
    if (_stepIndex >= _steps.length - 1) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final nextStep = _stepIndex + 1;
    setState(() => _stepIndex = nextStep);
    _animateToStep(nextStep);
  }

  void _skipCurrentStep() {
    if (_stepIndex == _steps.length - 1) {
      _save();
      return;
    }
    if (_stepIndex < _steps.length - 1) {
      final nextStep = _stepIndex + 1;
      setState(() => _stepIndex = nextStep);
      _animateToStep(nextStep);
    }
  }

  Future<void> _save() async {
    setState(() => _isSubmitting = true);
    try {
      final result = PetOnboardingResult(
        name: _name.text.trim(),
        type: _type ?? PetType.other,
        breed: _breed == otherBreedLabel
            ? _customBreed.text.trim()
            : (_breed ?? otherBreedLabel),
        sex: _sex ?? '未填写',
        birthday: _formatBirthday(_birthday!),
        weightKg: double.parse(_weight.text.trim()),
        neuterStatus: _neuterStatus ?? PetNeuterStatus.unknown,
        feedingPreferences: _textOrDefault(_feeding.text),
        allergies: _textOrDefault(_allergies.text),
        note: _textOrDefault(_note.text),
      );
      await widget.onSubmit(result);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _textOrDefault(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '未填写' : trimmed;
  }

  String _formatBirthday(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _formatBirthdayDisplay(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}年$month月$day日';
  }

  Future<void> _pickBirthdayYear() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 25);
    final lastDate = DateTime(now.year + 25, 12, 31);
    final referenceDate = _birthday ?? _birthdayDisplayedMonth;
    final pickedYear = await _showMaterialBirthdayYearPicker(
      initialYear: referenceDate.year,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (pickedYear == null || !mounted) {
      return;
    }

    setState(() {
      if (_birthday != null) {
        _birthday = _birthdayWithUpdatedYear(_birthday!, pickedYear);
        _birthdayDisplayedMonth = _monthDate(_birthday!);
      } else {
        _birthdayDisplayedMonth = DateTime(
          pickedYear,
          _birthdayDisplayedMonth.month,
        );
      }
    });
  }

  Future<int?> _showMaterialBirthdayYearPicker({
    required int initialYear,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    return showDialog<int>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final tokens = dialogContext.petNoteTokens;
        final localizations = MaterialLocalizations.of(dialogContext);
        final isDark = theme.brightness == Brightness.dark;
        return Dialog(
          key: const ValueKey('onboarding_birthday_year_dialog'),
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            decoration: BoxDecoration(
              color: isDark
                  ? tokens.panelStrongBackground
                  : tokens.pageGradientTop,
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: tokens.panelBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: tokens.panelShadow,
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '选择年份',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: tokens.primaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 360,
                    child: _OnboardingBirthdayYearGrid(
                      key: const ValueKey('onboarding_birthday_year_grid'),
                      firstYear: firstDate.year,
                      lastYear: lastDate.year,
                      selectedYear: initialYear,
                      currentYear: DateTime.now().year,
                      onYearSelected: (year) {
                        Navigator.of(dialogContext).pop(year);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(localizations.cancelButtonLabel),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _setBirthday(DateTime value) {
    setState(() {
      _birthday = value;
      _birthdayDisplayedMonth = _monthDate(value);
    });
  }

  void _setBirthdayDisplayedMonth(DateTime value) {
    final month = _monthDate(value);
    if (_isSameMonth(month, _birthdayDisplayedMonth)) {
      return;
    }
    setState(() => _birthdayDisplayedMonth = month);
  }

  DateTime _birthdayWithUpdatedYear(DateTime value, int year) {
    final clampedDay = math.min(
      value.day,
      DateUtils.getDaysInMonth(year, value.month),
    );
    return DateTime(year, value.month, clampedDay);
  }

  DateTime _monthDate(DateTime value) {
    return DateTime(value.year, value.month);
  }

  bool _isSameMonth(DateTime left, DateTime right) {
    return left.year == right.year && left.month == right.month;
  }

  void _onFieldChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<bool> _handleSystemBack() async {
    if (_isSubmitting) {
      return false;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    if (_stepIndex > 0) {
      _goBack();
      return false;
    }

    if (widget.embedded && widget.onReturnToActions != null) {
      widget.onReturnToActions!.call();
      return false;
    }

    if (widget.onReturnToIntro != null) {
      widget.onReturnToIntro!.call();
      return false;
    }

    await widget.onDefer();
    return false;
  }

  void _goBack() {
    if (_stepIndex <= 0) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final previousStep = _stepIndex - 1;
    setState(() => _stepIndex = previousStep);
    _animateToStep(previousStep, reverse: true);
  }

  void _animateToStep(int stepIndex, {bool reverse = false}) {
    if (!_stepPageController.hasClients) {
      return;
    }
    _stepPageController.animateToPage(
      stepIndex,
      duration: Duration(milliseconds: reverse ? 340 : 380),
      curve: Curves.easeOutCubic,
    );
  }

  double _stageProgress(double value, double start, double end) {
    if (value <= start) {
      return 0;
    }
    if (value >= end) {
      return 1;
    }
    return Curves.easeOutCubic.transform((value - start) / (end - start));
  }

  double _externalRevealProgress() {
    final progress = widget.externalRevealProgress;
    if (progress == null) {
      return 1.0;
    }
    if (progress <= 0.64) {
      return 0.0;
    }
    return Curves.easeOutCubic.transform(
      ((progress - 0.64) / 0.24).clamp(0.0, 1.0),
    );
  }

  Widget _buildEntranceReveal({
    Key? key,
    required double progress,
    required Widget child,
    required double offsetY,
  }) {
    final clamped = progress.clamp(0.0, 1.0);
    return IgnorePointer(
      ignoring: clamped <= 0,
      child: Opacity(
        key: key,
        opacity: clamped,
        child: Transform.translate(
          offset: Offset(0, (1 - clamped) * offsetY),
          child: child,
        ),
      ),
    );
  }
}

class _OnboardingBirthdayCalendar extends StatefulWidget {
  const _OnboardingBirthdayCalendar({
    super.key,
    required this.selectedDate,
    required this.displayedMonth,
    required this.currentDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDateChanged,
    required this.onDisplayedMonthChanged,
  });

  final DateTime? selectedDate;
  final DateTime displayedMonth;
  final DateTime currentDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<DateTime> onDisplayedMonthChanged;

  @override
  State<_OnboardingBirthdayCalendar> createState() =>
      _OnboardingBirthdayCalendarState();
}

class _OnboardingBirthdayCalendarState
    extends State<_OnboardingBirthdayCalendar> {
  static const double _calendarHeight = 360;

  late final PageController _pageController;

  DateTime get _firstMonth =>
      DateTime(widget.firstDate.year, widget.firstDate.month);
  DateTime get _lastMonth =>
      DateTime(widget.lastDate.year, widget.lastDate.month);

  @override
  void initState() {
    super.initState();
    _pageController =
        PageController(initialPage: _pageForMonth(widget.displayedMonth));
  }

  @override
  void didUpdateWidget(covariant _OnboardingBirthdayCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isSameMonth(oldWidget.displayedMonth, widget.displayedMonth)) {
      return;
    }
    final targetPage = _pageForMonth(widget.displayedMonth);
    if (_pageController.hasClients &&
        (_pageController.page?.round() ?? _pageController.initialPage) !=
            targetPage) {
      _pageController.jumpToPage(targetPage);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int _pageForMonth(DateTime month) => DateUtils.monthDelta(_firstMonth, month);

  DateTime _monthForPage(int page) =>
      DateUtils.addMonthsToMonthDate(_firstMonth, page);

  bool _isSameMonth(DateTime left, DateTime right) {
    return left.year == right.year && left.month == right.month;
  }

  bool get _isDisplayingFirstMonth =>
      _isSameMonth(widget.displayedMonth, _firstMonth);

  bool get _isDisplayingLastMonth =>
      _isSameMonth(widget.displayedMonth, _lastMonth);

  void _showMonth(DateTime month) {
    _pageController.animateToPage(
      _pageForMonth(month),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final localizations = MaterialLocalizations.of(context);
    final datePickerTheme = DatePickerTheme.of(context);
    final datePickerDefaults = DatePickerTheme.defaults(context);
    final monthTitle = localizations.formatMonthYear(widget.displayedMonth);
    final buttonColor = datePickerTheme.subHeaderForegroundColor ??
        datePickerDefaults.subHeaderForegroundColor ??
        tokens.secondaryText;

    return SizedBox(
      height: _calendarHeight,
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('onboarding_birthday_prev_month_button'),
                  onPressed: _isDisplayingFirstMonth
                      ? null
                      : () => _showMonth(
                            DateUtils.addMonthsToMonthDate(
                              widget.displayedMonth,
                              -1,
                            ),
                          ),
                  icon: const Icon(Icons.chevron_left),
                  color: buttonColor,
                ),
                Expanded(
                  child: Text(
                    monthTitle,
                    key: const ValueKey('onboarding_birthday_month_title'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: tokens.primaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('onboarding_birthday_next_month_button'),
                  onPressed: _isDisplayingLastMonth
                      ? null
                      : () => _showMonth(
                            DateUtils.addMonthsToMonthDate(
                              widget.displayedMonth,
                              1,
                            ),
                          ),
                  icon: const Icon(Icons.chevron_right),
                  color: buttonColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: PageView.builder(
              key: const ValueKey('onboarding_birthday_page_view'),
              controller: _pageController,
              itemCount: DateUtils.monthDelta(_firstMonth, _lastMonth) + 1,
              onPageChanged: (page) {
                widget.onDisplayedMonthChanged(_monthForPage(page));
              },
              itemBuilder: (context, index) {
                final month = _monthForPage(index);
                return _OnboardingBirthdayMonthPage(
                  month: month,
                  selectedDate: widget.selectedDate,
                  currentDate: widget.currentDate,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  onDateChanged: widget.onDateChanged,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingBirthdayMonthPage extends StatelessWidget {
  const _OnboardingBirthdayMonthPage({
    required this.month,
    required this.selectedDate,
    required this.currentDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDateChanged,
  });

  final DateTime month;
  final DateTime? selectedDate;
  final DateTime currentDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final localizations = MaterialLocalizations.of(context);
    final weekdayLabels = List<String>.generate(
      DateTime.daysPerWeek,
      (index) => localizations.narrowWeekdays[
          (localizations.firstDayOfWeekIndex + index) % DateTime.daysPerWeek],
    );
    final days = _daysForMonth(localizations.firstDayOfWeekIndex);

    return Column(
      children: [
        Row(
          children: weekdayLabels
              .map(
                (label) => Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: tokens.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Column(
            children: List<Widget>.generate(6, (rowIndex) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: rowIndex == 5 ? 0 : 6),
                  child: Row(
                    children: List<Widget>.generate(DateTime.daysPerWeek,
                        (columnIndex) {
                      final slot =
                          days[rowIndex * DateTime.daysPerWeek + columnIndex];
                      return Expanded(
                        child: Padding(
                          padding:
                              EdgeInsets.only(right: columnIndex == 6 ? 0 : 6),
                          child: slot == null
                              ? const SizedBox.expand()
                              : _OnboardingBirthdayDayCell(
                                  date: slot,
                                  selectedDate: selectedDate,
                                  currentDate: currentDate,
                                  firstDate: firstDate,
                                  lastDate: lastDate,
                                  onTap: () => onDateChanged(slot),
                                ),
                        ),
                      );
                    }),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  List<DateTime?> _daysForMonth(int firstDayOfWeekIndex) {
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final firstDay = DateTime(month.year, month.month, 1);
    final weekdayFromSunday = firstDay.weekday % DateTime.daysPerWeek;
    final leadingOffset =
        (weekdayFromSunday - firstDayOfWeekIndex) % DateTime.daysPerWeek;
    final slots = List<DateTime?>.filled(42, null);

    for (var day = 1; day <= daysInMonth; day += 1) {
      slots[leadingOffset + day - 1] = DateTime(month.year, month.month, day);
    }

    return slots;
  }
}

class _OnboardingBirthdayDayCell extends StatelessWidget {
  const _OnboardingBirthdayDayCell({
    required this.date,
    required this.selectedDate,
    required this.currentDate,
    required this.firstDate,
    required this.lastDate,
    required this.onTap,
  });

  final DateTime date;
  final DateTime? selectedDate;
  final DateTime currentDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final VoidCallback onTap;

  bool get _isDisabled => date.isBefore(firstDate) || date.isAfter(lastDate);

  bool get _isSelected => DateUtils.isSameDay(date, selectedDate);

  bool get _isToday => DateUtils.isSameDay(date, currentDate);

  String get _dayKeyValue {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final datePickerTheme = DatePickerTheme.of(context);
    final defaults = DatePickerTheme.defaults(context);
    final states = <WidgetState>{
      if (_isSelected) WidgetState.selected,
      if (_isDisabled) WidgetState.disabled,
    };

    Color resolveForeground() {
      final todayForeground = _resolveStateColor(
        datePickerTheme: datePickerTheme,
        defaults: defaults,
        getter: (theme) => theme.todayForegroundColor,
        states: states,
      );
      final dayForeground = _resolveStateColor(
        datePickerTheme: datePickerTheme,
        defaults: defaults,
        getter: (theme) => theme.dayForegroundColor,
        states: states,
      );
      if (_isToday && todayForeground != null) {
        return todayForeground;
      }
      return dayForeground ?? tokens.primaryText;
    }

    Color resolveBackground() {
      final todayBackground = _resolveStateColor(
        datePickerTheme: datePickerTheme,
        defaults: defaults,
        getter: (theme) => theme.todayBackgroundColor,
        states: states,
      );
      final dayBackground = _resolveStateColor(
        datePickerTheme: datePickerTheme,
        defaults: defaults,
        getter: (theme) => theme.dayBackgroundColor,
        states: states,
      );
      if (_isToday && todayBackground != null) {
        return todayBackground;
      }
      return dayBackground ?? Colors.transparent;
    }

    final textColor = resolveForeground().withValues(
      alpha: _isDisabled ? 0.38 : 1,
    );
    final backgroundColor = resolveBackground();
    final borderSide =
        _isToday ? (datePickerTheme.todayBorder ?? defaults.todayBorder) : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('onboarding_birthday_day_$_dayKeyValue'),
        onTap: _isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(18),
            border:
                borderSide == null ? null : Border.fromBorderSide(borderSide),
          ),
          alignment: Alignment.center,
          child: Text(
            '${date.day}',
            style: (datePickerTheme.dayStyle ??
                    defaults.dayStyle ??
                    theme.textTheme.bodyMedium)
                ?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Color? _resolveStateColor({
    required DatePickerThemeData datePickerTheme,
    required DatePickerThemeData defaults,
    required WidgetStateProperty<Color?>? Function(DatePickerThemeData theme)
        getter,
    required Set<WidgetState> states,
  }) {
    return getter(datePickerTheme)?.resolve(states) ??
        getter(defaults)?.resolve(states);
  }
}

class _OnboardingBirthdayYearGrid extends StatefulWidget {
  const _OnboardingBirthdayYearGrid({
    super.key,
    required this.firstYear,
    required this.lastYear,
    required this.selectedYear,
    required this.currentYear,
    required this.onYearSelected,
  });

  final int firstYear;
  final int lastYear;
  final int selectedYear;
  final int currentYear;
  final ValueChanged<int> onYearSelected;

  @override
  State<_OnboardingBirthdayYearGrid> createState() =>
      _OnboardingBirthdayYearGridState();
}

class _OnboardingBirthdayYearGridState
    extends State<_OnboardingBirthdayYearGrid> {
  static const int _columnCount = 3;
  static const double _rowHeight = 52;
  static const double _rowSpacing = 10;

  late final ScrollController _scrollController = ScrollController(
    initialScrollOffset: _scrollOffsetForYear(widget.selectedYear),
  );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _OnboardingBirthdayYearGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedYear == widget.selectedYear) {
      return;
    }
    final targetOffset = _scrollOffsetForYear(widget.selectedYear);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(targetOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columnCount,
        mainAxisExtent: _rowHeight,
        mainAxisSpacing: _rowSpacing,
        crossAxisSpacing: 10,
      ),
      itemCount: widget.lastYear - widget.firstYear + 1,
      itemBuilder: (context, index) {
        final year = widget.firstYear + index;
        return _OnboardingBirthdayYearCell(
          year: year,
          isSelected: year == widget.selectedYear,
          isCurrentYear: year == widget.currentYear,
          onTap: () => widget.onYearSelected(year),
        );
      },
    );
  }

  double _scrollOffsetForYear(int year) {
    final safeYear = year.clamp(widget.firstYear, widget.lastYear);
    final row = (safeYear - widget.firstYear) ~/ _columnCount;
    return math.max(0, (row - 2) * (_rowHeight + _rowSpacing));
  }
}

class _OnboardingBirthdayYearCell extends StatelessWidget {
  const _OnboardingBirthdayYearCell({
    required this.year,
    required this.isSelected,
    required this.isCurrentYear,
    required this.onTap,
  });

  final int year;
  final bool isSelected;
  final bool isCurrentYear;
  final VoidCallback onTap;

  static const double _capsuleHeight = 38;
  static const double _capsuleMinWidth = 74;
  static const double _textOpticalOffsetY = -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final selectedColor = theme.colorScheme.primary;
    final textColor = isSelected
        ? Colors.white
        : (isCurrentYear ? selectedColor : tokens.primaryText);
    final yearTextStyle = theme.textTheme.titleMedium?.copyWith(
      color: textColor,
      fontSize: 18,
      height: 1,
      leadingDistribution: TextLeadingDistribution.even,
      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('onboarding_birthday_year_$year'),
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            key: ValueKey('onboarding_birthday_year_capsule_$year'),
            height: _capsuleHeight,
            constraints: const BoxConstraints(
              minWidth: _capsuleMinWidth,
            ),
            decoration: BoxDecoration(
              color: isSelected ? selectedColor : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: !isSelected && isCurrentYear
                  ? Border.all(
                      color: selectedColor.withValues(alpha: 0.32),
                      width: 1,
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: Transform.translate(
              offset: const Offset(0, _textOpticalOffsetY),
              child: Text(
                '$year年',
                key: ValueKey('onboarding_birthday_year_label_$year'),
                textAlign: TextAlign.center,
                style: yearTextStyle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerticalDragLock extends StatelessWidget {
  const _VerticalDragLock({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) {},
      onVerticalDragUpdate: (_) {},
      onVerticalDragEnd: (_) {},
      onVerticalDragCancel: () {},
      child: child,
    );
  }
}

class _StepCopy {
  const _StepCopy(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

class _AnimatedPipelineProgressBar extends StatefulWidget {
  const _AnimatedPipelineProgressBar({
    super.key,
    required this.progress,
    required this.height,
    required this.trackColor,
    required this.fillColor,
    required this.glowColor,
  });

  final double progress;
  final double height;
  final Color trackColor;
  final Color fillColor;
  final Color glowColor;

  @override
  State<_AnimatedPipelineProgressBar> createState() =>
      _AnimatedPipelineProgressBarState();
}

class _AnimatedPipelineProgressBarState
    extends State<_AnimatedPipelineProgressBar> with TickerProviderStateMixin {
  late final AnimationController _progressController = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 420),
  )..addListener(() => setState(() {}));

  late double _startProgress = widget.progress;
  late double _targetProgress = widget.progress;
  late double _displayedProgress = widget.progress;
  int _flowDirection = 1;

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AnimatedPipelineProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.progress - _targetProgress).abs() < 0.0001) {
      return;
    }
    _flowDirection = widget.progress >= _targetProgress ? 1 : -1;
    _startProgress = _displayedProgress;
    _targetProgress = widget.progress;
    _progressController.duration = Duration(
      milliseconds: _flowDirection > 0 ? 460 : 520,
    );
    _progressController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final easedProgress =
        Curves.easeOutCubic.transform(_progressController.value);
    _displayedProgress =
        lerpDouble(_startProgress, _targetProgress, easedProgress)!;
    final flowPhase = _progressController.isAnimating
        ? (easedProgress * 0.82).clamp(0.0, 1.0)
        : 1.0;
    final shimmerOpacity = _progressController.isAnimating
        ? (1 - Curves.easeOutQuad.transform(_progressController.value)) * 0.92
        : 0.28;

    return SizedBox(
      key: const ValueKey('onboarding_progress_bar_paint'),
      height: widget.height,
      child: CustomPaint(
        painter: _PipelineProgressPainter(
          progress: _displayedProgress.clamp(0.0, 1.0),
          flowPhase: flowPhase,
          shimmerOpacity: shimmerOpacity,
          flowDirection: _flowDirection,
          trackColor: widget.trackColor,
          fillColor: widget.fillColor,
          glowColor: widget.glowColor,
        ),
      ),
    );
  }
}

class _PipelineProgressPainter extends CustomPainter {
  const _PipelineProgressPainter({
    required this.progress,
    required this.flowPhase,
    required this.shimmerOpacity,
    required this.flowDirection,
    required this.trackColor,
    required this.fillColor,
    required this.glowColor,
  });

  final double progress;
  final double flowPhase;
  final double shimmerOpacity;
  final int flowDirection;
  final Color trackColor;
  final Color fillColor;
  final Color glowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final track = RRect.fromRectAndRadius(Offset.zero & size, radius);

    final trackPaint = Paint()..color = trackColor;
    canvas.drawRRect(track, trackPaint);

    if (progress <= 0) {
      return;
    }

    final fillWidth = math.max(size.height, size.width * progress);
    final fillRect =
        Rect.fromLTWH(0, 0, fillWidth.clamp(0, size.width), size.height);
    final fill = RRect.fromRectAndRadius(fillRect, radius);
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color.lerp(fillColor, Colors.white, 0.1)!,
          fillColor,
          Color.lerp(fillColor, Colors.black, 0.04)!,
        ],
      ).createShader(fillRect);
    canvas.drawRRect(fill, fillPaint);

    canvas.save();
    canvas.clipRRect(fill);

    if (shimmerOpacity > 0.001) {
      final directionPhase = _normalizePhase(flowPhase,
          animateWithDirection: shimmerOpacity > 0.3);
      final shimmerWidth = math.max(22.0, size.width * 0.14);
      final shimmerTravel = fillRect.width + shimmerWidth;
      final shimmerX = (directionPhase * shimmerTravel) - shimmerWidth;
      final shimmerRect = Rect.fromLTWH(
        shimmerX,
        0,
        shimmerWidth,
        size.height,
      );
      final shimmerPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white.withValues(alpha: 0),
            glowColor.withValues(alpha: 0.32 * shimmerOpacity),
            glowColor.withValues(alpha: 0.88 * shimmerOpacity),
            glowColor.withValues(alpha: 0.32 * shimmerOpacity),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.28, 0.5, 0.72, 1.0],
        ).createShader(shimmerRect);
      canvas.drawRect(shimmerRect, shimmerPaint);
    }

    final headWidth = math.min(18.0, fillRect.width);
    final headRect = Rect.fromLTWH(
      math.max(0, fillRect.right - headWidth),
      0,
      headWidth,
      size.height,
    );
    final headPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withValues(alpha: 0),
          glowColor.withValues(alpha: 0.72),
        ],
      ).createShader(headRect);
    canvas.drawRect(headRect, headPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PipelineProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.flowPhase != flowPhase ||
        oldDelegate.shimmerOpacity != shimmerOpacity ||
        oldDelegate.flowDirection != flowDirection ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.glowColor != glowColor;
  }

  double _normalizePhase(double phase, {required bool animateWithDirection}) {
    if (!animateWithDirection) {
      return 1.0;
    }
    return flowDirection >= 0 ? phase : 1 - phase;
  }
}

class _OptionWrap<T> extends StatelessWidget {
  const _OptionWrap({
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onTap,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: values.map((value) {
        final isSelected = selected == value;
        return GestureDetector(
          onTap: () => onTap(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? tokens.segmentedSelectedBackground
                  : tokens.secondarySurface,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              labelBuilder(value),
              style: theme.textTheme.labelLarge?.copyWith(
                color: isSelected ? Colors.white : tokens.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
