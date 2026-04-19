import 'dart:async';

import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/native_pet_photo_picker.dart';
import 'package:petnote/app/pet_photo_widgets.dart';
import 'package:petnote/state/petnote_store.dart';

import '../form_controls/adaptive_date_time_field.dart';
import '../form_controls/choice_wrap.dart';
import '../form_controls/form_scaffold.dart';
import '../form_controls/pet_selector.dart';

class RecordForm extends StatefulWidget {
  const RecordForm({
    super.key,
    required this.store,
    this.nativePetPhotoPicker,
  });

  final PetNoteStore store;
  final NativePetPhotoPicker? nativePetPhotoPicker;

  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm> {
  final _summary = TextEditingController();
  final List<String> _photoPaths = <String>[];
  late final NativePetPhotoPicker _nativePetPhotoPicker =
      widget.nativePetPhotoPicker ?? MethodChannelNativePetPhotoPicker();

  late String _petId;
  late DateTime _recordDate;
  RecordPurpose _purpose = RecordPurpose.health;
  bool _isPickingPhoto = false;
  bool _hasSubmitted = false;

  @override
  void initState() {
    super.initState();
    _petId = widget.store.pets.first.id;
    _recordDate = DateTime.now();
  }

  @override
  void dispose() {
    _summary.dispose();
    if (!_hasSubmitted) {
      for (final path in _photoPaths) {
        unawaited(_nativePetPhotoPicker.deletePetPhoto(path));
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      actionLabel: '保存记录',
      actionColor: const Color(0xFF4FB57C),
      onSubmit: () async {
        await widget.store.addRecord(
          petId: _petId,
          purpose: _purpose,
          title: '',
          recordDate: _recordDate,
          summary: _summary.text.trim(),
          note: '',
          photoPaths: List<String>.from(_photoPaths),
        );
        _hasSubmitted = true;
        if (!context.mounted) {
          return;
        }
        Navigator.pop(context);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: '记录信息',
            children: [
              const SectionLabel(text: '关联爱宠'),
              PetSelector(
                pets: widget.store.pets,
                value: _petId,
                onChanged: (value) => setState(() => _petId = value),
              ),
              const SectionLabel(text: '记录目的'),
              ChoiceWrap<RecordPurpose>(
                values: RecordPurpose.values,
                selected: _purpose,
                labelBuilder: _recordPurposeLabel,
                onChanged: (value) => setState(() => _purpose = value),
              ),
              const SectionLabel(text: '时间'),
              AdaptiveDateTimeField(
                materialFieldKey: const ValueKey('record_date_field'),
                iosDateFieldKey: const ValueKey('record_date_date_field'),
                iosTimeFieldKey: const ValueKey('record_date_time_field'),
                value: _recordDate,
                onChanged: (value) => setState(() => _recordDate = value),
              ),
            ],
          ),
          SectionCard(
            title: '记录内容',
            children: [
              _RecordPhotoAttachmentSection(
                photoPaths: List<String>.unmodifiable(_photoPaths),
                isPickingPhoto: _isPickingPhoto,
                onAddPhoto: _pickRecordPhotos,
                onRemovePhoto: _removeRecordPhoto,
              ),
              HyperTextField(
                key: const ValueKey('record_summary_field'),
                controller: _summary,
                hintText: '写点什么吧',
                maxLines: 3,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickRecordPhotos() async {
    if (_isPickingPhoto) {
      return;
    }
    setState(() => _isPickingPhoto = true);
    try {
      final result = await _nativePetPhotoPicker.pickPetPhotos();
      if (!mounted) {
        if (result.isSuccess) {
          for (final path in result.localPaths) {
            await _nativePetPhotoPicker.deletePetPhoto(path);
          }
        }
        return;
      }
      if (result.isSuccess) {
        setState(() => _photoPaths.addAll(result.localPaths));
        return;
      }
      if (result.isCancelled) {
        return;
      }
      _showPhotoError(result.errorMessage ?? '图片导入失败，请稍后再试。');
    } finally {
      if (mounted) {
        setState(() => _isPickingPhoto = false);
      }
    }
  }

  Future<void> _removeRecordPhoto(String photoPath) async {
    final index = _photoPaths.indexOf(photoPath);
    if (index == -1) {
      return;
    }
    final removedPath = _photoPaths.removeAt(index);
    setState(() {});
    await _nativePetPhotoPicker.deletePetPhoto(removedPath);
  }

  void _showPhotoError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _RecordPhotoAttachmentSection extends StatefulWidget {
  const _RecordPhotoAttachmentSection({
    required this.photoPaths,
    required this.isPickingPhoto,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  final List<String> photoPaths;
  final bool isPickingPhoto;
  final Future<void> Function() onAddPhoto;
  final Future<void> Function(String photoPath) onRemovePhoto;

  @override
  State<_RecordPhotoAttachmentSection> createState() =>
      _RecordPhotoAttachmentSectionState();
}

class _RecordPhotoAttachmentSectionState
    extends State<_RecordPhotoAttachmentSection>
    with SingleTickerProviderStateMixin {
  static const _photoTileSize = 132.0;
  static const _stripSpacing = 12.0;
  static const _transitionDuration = Duration(milliseconds: 380);

  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _heroCardKey = GlobalKey();
  final GlobalKey _tailCardKey = GlobalKey();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _transitionDuration,
  );

  Rect? _heroCardRect;
  Rect? _transitionStartRect;
  Rect? _transitionEndRect;
  bool _isAnimatingAddCard = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _isAnimatingAddCard = false;
          _transitionStartRect = null;
          _transitionEndRect = null;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _cacheHeroCardRect());
  }

  @override
  void didUpdateWidget(covariant _RecordPhotoAttachmentSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameEmpty =
        oldWidget.photoPaths.isNotEmpty && widget.photoPaths.isEmpty;
    final firstSelection =
        oldWidget.photoPaths.isEmpty && widget.photoPaths.isNotEmpty;
    if (becameEmpty) {
      _resetAddCardFlight(clearHeroRect: true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _cacheHeroCardRect());
      return;
    }
    if (firstSelection) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _startAddCardFlight());
      return;
    }
    if (widget.photoPaths.isEmpty && !_isAnimatingAddCard) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _cacheHeroCardRect());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final showStrip = widget.photoPaths.isNotEmpty || _isAnimatingAddCard;
    final disableAddAction = widget.isPickingPhoto || _isAnimatingAddCard;
    return SizedBox(
      key: _stackKey,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (!showStrip)
            Align(
              alignment: Alignment.centerLeft,
              child: _RecordAddPhotoCard(
                key: const ValueKey('record_add_photo_hero_card'),
                layoutKey: _heroCardKey,
                buttonKey: const ValueKey('record_add_photo_button'),
                variant: _RecordAddPhotoCardVariant.hero,
                isPickingPhoto: widget.isPickingPhoto,
                onAddPhoto: disableAddAction ? null : widget.onAddPhoto,
                theme: theme,
                tokens: tokens,
                width: _photoTileSize,
                height: _photoTileSize,
              ),
            )
          else
            _RecordPhotoStrip(
              photoPaths: widget.photoPaths,
              isPickingPhoto: widget.isPickingPhoto,
              disableAddAction: disableAddAction,
              tailCardKey: _tailCardKey,
              onAddPhoto: widget.onAddPhoto,
              onRemovePhoto: widget.onRemovePhoto,
              theme: theme,
              tokens: tokens,
              photoSize: _photoTileSize,
            ),
          if (_isAnimatingAddCard &&
              _transitionStartRect != null &&
              _transitionEndRect != null)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final rect = Rect.lerp(
                  _transitionStartRect,
                  _transitionEndRect,
                  Curves.easeInOutCubic.transform(_controller.value),
                );
                if (rect == null) {
                  return const SizedBox.shrink();
                }
                return Positioned.fromRect(
                  key: const ValueKey('record_add_photo_transition_card'),
                  rect: rect,
                  child: child!,
                );
              },
              child: IgnorePointer(
                child: _RecordAddPhotoCard(
                  variant: _RecordAddPhotoCardVariant.transition,
                  isPickingPhoto: widget.isPickingPhoto,
                  onAddPhoto: null,
                  theme: theme,
                  tokens: tokens,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _startAddCardFlight() async {
    if (!mounted || _isAnimatingAddCard) {
      return;
    }
    final startRect = _heroCardRect;
    final endRect = _measureRect(_tailCardKey);
    if (startRect == null || endRect == null) {
      _resetAddCardFlight();
      return;
    }
    _controller.reset();
    setState(() {
      _transitionStartRect = startRect;
      _transitionEndRect = endRect;
      _isAnimatingAddCard = true;
    });
    await _controller.forward();
  }

  void _resetAddCardFlight({bool clearHeroRect = false}) {
    _controller.stop();
    _controller.reset();
    _isAnimatingAddCard = false;
    _transitionStartRect = null;
    _transitionEndRect = null;
    if (clearHeroRect) {
      _heroCardRect = null;
    }
  }

  void _cacheHeroCardRect() {
    if (!mounted) {
      return;
    }
    _heroCardRect = _measureRect(_heroCardKey);
  }

  Rect? _measureRect(GlobalKey key) {
    final targetContext = key.currentContext;
    final stackContext = _stackKey.currentContext;
    if (targetContext == null || stackContext == null) {
      return null;
    }
    final targetBox = targetContext.findRenderObject() as RenderBox?;
    final stackBox = stackContext.findRenderObject() as RenderBox?;
    if (targetBox == null || stackBox == null) {
      return null;
    }
    final topLeft = targetBox.localToGlobal(Offset.zero, ancestor: stackBox);
    return topLeft & targetBox.size;
  }
}

class _RecordPhotoStrip extends StatelessWidget {
  const _RecordPhotoStrip({
    required this.photoPaths,
    required this.isPickingPhoto,
    required this.disableAddAction,
    required this.tailCardKey,
    required this.onAddPhoto,
    required this.onRemovePhoto,
    required this.theme,
    required this.tokens,
    required this.photoSize,
  });

  final List<String> photoPaths;
  final bool isPickingPhoto;
  final bool disableAddAction;
  final GlobalKey tailCardKey;
  final Future<void> Function() onAddPhoto;
  final Future<void> Function(String photoPath) onRemovePhoto;
  final ThemeData theme;
  final PetNoteThemeTokens tokens;
  final double photoSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('record_photo_strip'),
      height: photoSize,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photoPaths.length + 1,
        separatorBuilder: (_, __) => const SizedBox(
          width: _RecordPhotoAttachmentSectionState._stripSpacing,
        ),
        itemBuilder: (context, index) {
          if (index == photoPaths.length) {
            return _RecordAddPhotoCard(
              key: const ValueKey('record_add_photo_tail_card'),
              layoutKey: tailCardKey,
              buttonKey: const ValueKey('record_add_photo_button'),
              variant: _RecordAddPhotoCardVariant.tail,
              isPickingPhoto: isPickingPhoto,
              onAddPhoto: disableAddAction ? null : onAddPhoto,
              theme: theme,
              tokens: tokens,
              width: photoSize,
              height: photoSize,
            );
          }
          final photoPath = photoPaths[index];
          return _RecordPhotoPreviewCard(
            key: ValueKey<String>('record_photo_preview_$photoPath'),
            path: photoPath,
            size: photoSize,
            onRemove: () => onRemovePhoto(photoPath),
          );
        },
      ),
    );
  }
}

class _RecordPhotoPreviewCard extends StatefulWidget {
  const _RecordPhotoPreviewCard({
    super.key,
    required this.path,
    required this.size,
    required this.onRemove,
  });

  final String path;
  final double size;
  final Future<void> Function() onRemove;

  @override
  State<_RecordPhotoPreviewCard> createState() =>
      _RecordPhotoPreviewCardState();
}

class _RecordPhotoPreviewCardState extends State<_RecordPhotoPreviewCard> {
  static const _removeDuration = Duration(milliseconds: 190);

  bool _isRemoving = false;

  Future<void> _handleRemove() async {
    if (_isRemoving) {
      return;
    }
    setState(() => _isRemoving = true);
    await Future<void>.delayed(_removeDuration);
    await widget.onRemove();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _removeDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: ClipRect(
        child: SizedBox(
          width: _isRemoving ? 0 : widget.size,
          height: widget.size,
          child: AnimatedScale(
            duration: _removeDuration,
            curve: Curves.easeOutCubic,
            scale: _isRemoving ? 0.92 : 1,
            child: AnimatedOpacity(
              duration: _removeDuration,
              curve: Curves.easeOutCubic,
              opacity: _isRemoving ? 0 : 1,
              child: Stack(
                children: [
                  PetPhotoSquare(
                    photoPath: widget.path,
                    size: widget.size,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Semantics(
                      button: true,
                      label: '移除照片',
                      child: GestureDetector(
                        key: ValueKey<String>(
                          'record_remove_photo_${widget.path}_button',
                        ),
                        onTap: _isRemoving ? null : _handleRemove,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.38),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
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

enum _RecordAddPhotoCardVariant { hero, tail, transition }

class _RecordAddPhotoCard extends StatelessWidget {
  const _RecordAddPhotoCard({
    super.key,
    this.layoutKey,
    this.buttonKey,
    required this.isPickingPhoto,
    required this.variant,
    required this.onAddPhoto,
    required this.theme,
    required this.tokens,
    this.width,
    this.height,
  });

  final Key? layoutKey;
  final Key? buttonKey;
  final bool isPickingPhoto;
  final _RecordAddPhotoCardVariant variant;
  final Future<void> Function()? onAddPhoto;
  final ThemeData theme;
  final PetNoteThemeTokens tokens;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final resolvedHeight = height ?? 132.0;
    final borderRadius = BorderRadius.circular(28);
    final iconContainerSize = 54.0;
    final iconSize = 26.0;
    final title = switch (variant) {
      _RecordAddPhotoCardVariant.hero => isPickingPhoto ? '导入中' : '选择照片',
      _RecordAddPhotoCardVariant.tail => isPickingPhoto ? '导入中' : '继续添加',
      _RecordAddPhotoCardVariant.transition => '继续添加',
    };
    final subtitle = switch (variant) {
      _RecordAddPhotoCardVariant.hero => '添加附件',
      _RecordAddPhotoCardVariant.tail => '再选图片',
      _RecordAddPhotoCardVariant.transition => '再选图片',
    };
    return SizedBox(
      key: layoutKey,
      width: width ?? resolvedHeight,
      height: resolvedHeight,
      child: Material(
        color: tokens.secondarySurface,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: tokens.panelBorder.withValues(alpha: 0.92),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: buttonKey,
          onTap: isPickingPhoto ? null : onAddPhoto,
          borderRadius: borderRadius,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: iconContainerSize,
                  height: iconContainerSize,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    isPickingPhoto
                        ? Icons.hourglass_empty_rounded
                        : Icons.add_photo_alternate_rounded,
                    color: theme.colorScheme.primary,
                    size: iconSize,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: tokens.primaryText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.secondaryText,
                    height: 1.2,
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

String _recordPurposeLabel(RecordPurpose purpose) => switch (purpose) {
      RecordPurpose.health => '健康',
      RecordPurpose.life => '生活',
      RecordPurpose.expense => '消费',
    };
