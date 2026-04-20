part of 'petnote_pages.dart';

class PetDetailsPage extends StatelessWidget {
  const PetDetailsPage({
    super.key,
    required this.store,
    required this.pet,
  });

  final PetNoteStore store;
  final Pet pet;

  @override
  Widget build(BuildContext context) {
    const pagePadding = EdgeInsets.fromLTRB(18, 8, 18, 20);

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final records = store.records
            .where((item) => item.petId == pet.id)
            .toList(growable: false)
          ..sort((a, b) => b.recordDate.compareTo(a.recordDate));

        return Scaffold(
          appBar: AppBar(
            title: const Text('资料记录'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: ListView(
            padding: pagePadding,
            children: [
              PageHeader(
                title: pet.name,
                subtitle:
                    '${petTypeLabel(pet.type)} · ${pet.breed} · ${pet.ageLabel}',
              ),
              const SizedBox(height: 8),
              if (records.isEmpty)
                PageEmptyStateBlock(
                  emptyTitle: '暂无资料记录',
                  emptySubtitle: '当前宠物暂无任何资料记录。',
                  actionLabel: '返回',
                  onAction: () => Navigator.pop(context),
                )
              else
                SectionCard(
                  title: '资料记录',
                  children: records
                      .map(
                        (item) => StatusListRow(
                          key: ValueKey('pet-record-row-${item.id}'),
                          title: item.title,
                          subtitle: _petRecordSubtitle(item),
                          leadingIcon: Icons.description_rounded,
                          leadingBackgroundColor: const Color(0xFFE8F7EE),
                          leadingIconColor: const Color(0xFF4FB57C),
                          leading: _RecordListLeading(record: item),
                          trailing: HyperBadge(
                            text: _petRecordPurposeLabel(
                              item.purpose,
                              customPurposeLabel: item.customPurposeLabel,
                            ),
                            foreground: const Color(0xFF2F8F5B),
                            background: const Color(0xFFE8F7EE),
                          ),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) => RecordDetailPage(
                                  store: store,
                                  recordId: item.id,
                                ),
                              ),
                            );
                          },
                        ),
                      )
                      .toList(growable: false),
                ),
            ],
          ),
        );
      },
    );
  }
}

class RecordDetailPage extends StatefulWidget {
  const RecordDetailPage({
    super.key,
    required this.store,
    required this.recordId,
    this.nativePetPhotoPicker,
  });

  final PetNoteStore store;
  final String recordId;
  final NativePetPhotoPicker? nativePetPhotoPicker;

  @override
  State<RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<RecordDetailPage> {
  final _titleController = TextEditingController();
  final _summaryController = TextEditingController();
  final _noteController = TextEditingController();
  final _customPurposeController = TextEditingController();
  late final NativePetPhotoPicker _nativePetPhotoPicker =
      widget.nativePetPhotoPicker ?? MethodChannelNativePetPhotoPicker();

  _RecordEditSnapshot? _editingSnapshot;
  String? _customPurposeError;
  String? _petId;
  DateTime? _recordDate;
  RecordPurpose _purpose = RecordPurpose.health;
  List<String> _editablePhotoPaths = const <String>[];
  bool _isPickingPhoto = false;

  bool get _isEditing => _editingSnapshot != null;

  @override
  void dispose() {
    _cleanupDraftPhotosIfNeeded();
    _titleController.dispose();
    _summaryController.dispose();
    _noteController.dispose();
    _customPurposeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final record = widget.store.recordById(widget.recordId);
        if (record == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('记录详情'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: PageEmptyStateBlock(
              emptyTitle: '记录已不存在',
              emptySubtitle: '这条资料记录可能已经被删除或同步更新。',
              actionLabel: '返回',
              onAction: () => Navigator.pop(context),
            ),
          );
        }
        final pet = widget.store.petById(_petId ?? record.petId) ??
            widget.store.petById(record.petId);
        if (pet == null) {
          return const SizedBox.shrink();
        }
        if (!_isEditing) {
          _syncDraftFromRecord(record);
        }

        const pagePadding = EdgeInsets.fromLTRB(18, 8, 18, 20);
        return Scaffold(
          key: ValueKey('pet-record-detail-page-${record.id}'),
          appBar: AppBar(
            title: Text(_isEditing ? '编辑记录' : '记录详情'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () async {
                if (_isEditing) {
                  await _cancelEditing();
                }
                if (mounted) {
                  Navigator.pop(context);
                }
              },
            ),
            actions: [
              if (!_isEditing)
                TextButton(
                  key: const ValueKey('pet-record-detail-edit-button'),
                  onPressed: () => _beginEditing(record),
                  child: const Text('编辑'),
                )
              else ...[
                TextButton(
                  key: const ValueKey('pet-record-detail-cancel-button'),
                  onPressed: _cancelEditing,
                  child: const Text('取消'),
                ),
                TextButton(
                  key: const ValueKey('pet-record-detail-save-button'),
                  onPressed: () => _saveChanges(record),
                  child: const Text('保存'),
                ),
              ],
            ],
          ),
          body: ListView(
            padding: pagePadding,
            children: _isEditing
                ? _buildEditChildren(context, pet)
                : _buildViewChildren(context, pet, record),
          ),
        );
      },
    );
  }

  List<Widget> _buildViewChildren(
    BuildContext context,
    Pet pet,
    PetRecord record,
  ) {
    return [
      PageHeader(
        title: record.title,
        subtitle: '${pet.name} · ${_petRecordTypeLabel(record.type)}',
      ),
      HeroPanel(
        title: '记录概览',
        subtitle: _petRecordHeroSubtitle(record),
        child: HyperBadge(
          text: _petRecordPurposeLabel(
            record.purpose,
            customPurposeLabel: record.customPurposeLabel,
          ),
          foreground: const Color(0xFF2F8F5B),
          background: const Color(0xFFE8F7EE),
        ),
      ),
      if (record.photoPaths.isNotEmpty)
        SectionCard(
          title: '记录图片',
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: record.photoPaths
                  .map(
                    (path) => _RecordDetailPhotoTile(
                      photoPaths: record.photoPaths,
                      initialIndex: record.photoPaths.indexOf(path),
                      photoPath: path,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      SectionCard(
        title: '记录信息',
        children: [
          InfoRow(label: '记录日期', value: formatDate(record.recordDate)),
          InfoRow(label: '记录类型', value: _petRecordTypeLabel(record.type)),
          InfoRow(
            label: '记录用途',
            value: _petRecordPurposeLabel(
              record.purpose,
              customPurposeLabel: record.customPurposeLabel,
            ),
          ),
        ],
      ),
      if (record.summary.trim().isNotEmpty)
        SectionCard(
          title: '记录正文',
          children: [
            Text(
              record.summary.trim(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                  ),
            ),
          ],
        ),
      if (record.note.trim().isNotEmpty)
        SectionCard(
          title: '补充备注',
          children: [
            Text(
              record.note.trim(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                  ),
            ),
          ],
        ),
    ];
  }

  List<Widget> _buildEditChildren(BuildContext context, Pet pet) {
    return [
      PageHeader(
        title: _titleController.text.trim().isEmpty
            ? '编辑资料记录'
            : _titleController.text.trim(),
        subtitle: '${pet.name} · 调整记录内容和图片',
      ),
      SectionCard(
        title: '记录信息',
        children: [
          const SectionLabel(text: '标题'),
          HyperTextField(
            key: const ValueKey('pet-record-detail-title-field'),
            controller: _titleController,
            hintText: '输入这条记录的标题',
          ),
          const SectionLabel(text: '关联爱宠'),
          PetSelector(
            pets: widget.store.pets,
            value: _petId ?? pet.id,
            onChanged: (value) => setState(() => _petId = value),
          ),
          const SectionLabel(text: '记录目的'),
          ChoiceWrap<RecordPurpose>(
            values: RecordPurpose.values,
            selected: _purpose,
            labelBuilder: _petRecordPurposeChoiceLabel,
            onChanged: (value) => setState(() {
              _purpose = value;
              if (value != RecordPurpose.other) {
                _customPurposeError = null;
              }
            }),
          ),
          if (_purpose == RecordPurpose.other) ...[
            const SizedBox(height: 10),
            HyperTextField(
              key: const ValueKey('pet-record-detail-custom-purpose-field'),
              controller: _customPurposeController,
              hintText: '输入自定义记录目的',
              onTap: () {
                if (_customPurposeError != null) {
                  setState(() => _customPurposeError = null);
                }
              },
            ),
            if (_customPurposeError != null)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 8),
                child: Text(
                  _customPurposeError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFC85B63),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
          ],
          const SectionLabel(text: '时间'),
          AdaptiveDateTimeField(
            materialFieldKey:
                const ValueKey('pet-record-detail-record-date-field'),
            iosDateFieldKey:
                const ValueKey('pet-record-detail-record-date-ios-date'),
            iosTimeFieldKey:
                const ValueKey('pet-record-detail-record-date-ios-time'),
            value: _recordDate ?? DateTime.now(),
            onChanged: (value) => setState(() => _recordDate = value),
          ),
        ],
      ),
      SectionCard(
        title: '记录内容',
        children: [
          const SectionLabel(text: '记录正文'),
          HyperTextField(
            key: const ValueKey('pet-record-detail-summary-field'),
            controller: _summaryController,
            hintText: '补充这次记录的主要情况',
            maxLines: 4,
          ),
          const SectionLabel(text: '补充备注'),
          HyperTextField(
            key: const ValueKey('pet-record-detail-note-field'),
            controller: _noteController,
            hintText: '补充更多背景或注意事项',
            maxLines: 3,
          ),
          const SectionLabel(text: '记录图片'),
          _EditableRecordPhotoSection(
            photoPaths: _editablePhotoPaths,
            isPickingPhoto: _isPickingPhoto,
            onAddPhoto: _pickPhotos,
            onRemovePhoto: _removePhoto,
          ),
        ],
      ),
    ];
  }

  void _beginEditing(PetRecord record) {
    _editingSnapshot = _RecordEditSnapshot.fromRecord(record);
    _syncDraftFromSnapshot(_editingSnapshot!);
    setState(() {});
  }

  Future<void> _cancelEditing() async {
    final snapshot = _editingSnapshot;
    if (snapshot == null) {
      return;
    }
    final addedPaths = _editablePhotoPaths
        .where((path) => !snapshot.photoPaths.contains(path))
        .toList(growable: false);
    _syncDraftFromSnapshot(snapshot);
    _editingSnapshot = null;
    _customPurposeError = null;
    setState(() {});
    for (final path in addedPaths) {
      await _nativePetPhotoPicker.deletePetPhoto(path);
    }
  }

  Future<void> _saveChanges(PetRecord record) async {
    final customPurposeLabel = _validatedCustomPurposeLabel();
    if (_purpose == RecordPurpose.other && customPurposeLabel == null) {
      setState(() {
        _customPurposeError = '请填写 1-12 个字的自定义记录目的';
      });
      return;
    }

    final snapshot = _editingSnapshot;
    final removedPaths = snapshot == null
        ? const <String>[]
        : snapshot.photoPaths
            .where((path) => !_editablePhotoPaths.contains(path))
            .toList(growable: false);
    await widget.store.updateRecord(
      recordId: record.id,
      petId: _petId ?? record.petId,
      recordDate: _recordDate ?? record.recordDate,
      purpose: _purpose,
      customPurposeLabel: customPurposeLabel,
      title: _titleController.text.trim(),
      summary: _summaryController.text.trim(),
      note: _noteController.text.trim(),
      photoPaths: List<String>.from(_editablePhotoPaths),
    );
    _editingSnapshot = null;
    _customPurposeError = null;
    if (mounted) {
      setState(() {});
    }
    for (final path in removedPaths) {
      await _nativePetPhotoPicker.deletePetPhoto(path);
    }
  }

  Future<void> _pickPhotos() async {
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
        setState(() {
          _editablePhotoPaths = [
            ..._editablePhotoPaths,
            ...result.localPaths,
          ];
        });
        return;
      }
      if (!result.isCancelled) {
        _showPhotoError(result.errorMessage ?? '图片导入失败，请稍后再试。');
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingPhoto = false);
      }
    }
  }

  Future<void> _removePhoto(String photoPath) async {
    if (!_editablePhotoPaths.contains(photoPath)) {
      return;
    }
    setState(() {
      _editablePhotoPaths = _editablePhotoPaths
          .where((path) => path != photoPath)
          .toList(growable: false);
    });
  }

  void _syncDraftFromRecord(PetRecord record) {
    _titleController.text = record.title;
    _summaryController.text = record.summary;
    _noteController.text = record.note;
    _customPurposeController.text = record.customPurposeLabel ?? '';
    _petId = record.petId;
    _recordDate = record.recordDate;
    _purpose = record.purpose ?? RecordPurpose.health;
    _editablePhotoPaths = List<String>.from(record.photoPaths);
  }

  void _syncDraftFromSnapshot(_RecordEditSnapshot snapshot) {
    _titleController.text = snapshot.title;
    _summaryController.text = snapshot.summary;
    _noteController.text = snapshot.note;
    _customPurposeController.text = snapshot.customPurposeLabel ?? '';
    _petId = snapshot.petId;
    _recordDate = snapshot.recordDate;
    _purpose = snapshot.purpose;
    _editablePhotoPaths = List<String>.from(snapshot.photoPaths);
  }

  String? _validatedCustomPurposeLabel() {
    if (_purpose != RecordPurpose.other) {
      return null;
    }
    final normalized = _customPurposeController.text.trim();
    if (normalized.isEmpty || normalized.length > 12) {
      return null;
    }
    return normalized;
  }

  void _cleanupDraftPhotosIfNeeded() {
    final snapshot = _editingSnapshot;
    if (snapshot == null) {
      return;
    }
    for (final path in _editablePhotoPaths) {
      if (!snapshot.photoPaths.contains(path)) {
        unawaited(_nativePetPhotoPicker.deletePetPhoto(path));
      }
    }
  }

  void _showPhotoError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _EditableRecordPhotoSection extends StatelessWidget {
  const _EditableRecordPhotoSection({
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
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ...photoPaths.map(
          (path) => Stack(
            clipBehavior: Clip.none,
            children: [
              _RecordDetailPhotoTile(
                photoPaths: photoPaths,
                initialIndex: photoPaths.indexOf(path),
                photoPath: path,
              ),
              Positioned(
                top: -8,
                right: -8,
                child: IconButton.filledTonal(
                  key: ValueKey('pet-record-detail-remove-photo-$path'),
                  onPressed: () => onRemovePhoto(path),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(28, 28),
                    backgroundColor: const Color(0x99000000),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        _RecordPhotoAddTile(
          isLoading: isPickingPhoto,
          onTap: onAddPhoto,
        ),
      ],
    );
  }
}

class _RecordPhotoAddTile extends StatelessWidget {
  const _RecordPhotoAddTile({
    required this.isLoading,
    required this.onTap,
  });

  final bool isLoading;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('pet-record-detail-add-photo-button'),
        borderRadius: BorderRadius.circular(18),
        onTap: isLoading ? null : () => onTap(),
        child: Ink(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: const Color(0xFFF6F7FB),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.add_photo_alternate_rounded,
                    color: Color(0xFF6C7280),
                  ),
          ),
        ),
      ),
    );
  }
}

class _RecordEditSnapshot {
  const _RecordEditSnapshot({
    required this.petId,
    required this.recordDate,
    required this.purpose,
    required this.customPurposeLabel,
    required this.title,
    required this.summary,
    required this.note,
    required this.photoPaths,
  });

  final String petId;
  final DateTime recordDate;
  final RecordPurpose purpose;
  final String? customPurposeLabel;
  final String title;
  final String summary;
  final String note;
  final List<String> photoPaths;

  factory _RecordEditSnapshot.fromRecord(PetRecord record) {
    return _RecordEditSnapshot(
      petId: record.petId,
      recordDate: record.recordDate,
      purpose: record.purpose ?? RecordPurpose.health,
      customPurposeLabel: record.customPurposeLabel,
      title: record.title,
      summary: record.summary,
      note: record.note,
      photoPaths: List<String>.from(record.photoPaths),
    );
  }
}

class _RecordDetailPhotoTile extends StatelessWidget {
  const _RecordDetailPhotoTile({
    required this.photoPaths,
    required this.initialIndex,
    required this.photoPath,
  });

  final List<String> photoPaths;
  final int initialIndex;
  final String photoPath;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('pet-record-detail-photo-tile-$photoPath'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showRecordPhotoPreview(
          context,
          photoPaths,
          initialIndex,
        ),
        child: PetPhotoSquare(
          key: ValueKey('pet-record-detail-photo-$photoPath'),
          photoPath: photoPath,
          size: 96,
          borderRadius: BorderRadius.circular(18),
          fallback: _buildRecordIconFallback(),
        ),
      ),
    );
  }
}

class _RecordListLeading extends StatelessWidget {
  const _RecordListLeading({
    required this.record,
  });

  final PetRecord record;

  @override
  Widget build(BuildContext context) {
    final primaryPhotoPath =
        record.photoPaths.isEmpty ? null : record.photoPaths.first;
    if (primaryPhotoPath == null) {
      return _buildRecordIconFallback();
    }

    return PetPhotoSquare(
      photoPath: primaryPhotoPath,
      size: 42,
      borderRadius: BorderRadius.circular(16),
      fallback: _buildRecordIconFallback(),
    );
  }
}

Future<void> _showRecordPhotoPreview(
  BuildContext context,
  List<String> photoPaths,
  int initialIndex,
) async {
  await showGeneralDialog<void>(
    context: context,
    barrierLabel: '关闭图片预览',
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => _PetPhotoPreviewDialog(
      photoPaths: photoPaths,
      initialIndex: initialIndex,
    ),
    transitionBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _PetPhotoPreviewDialog extends StatefulWidget {
  const _PetPhotoPreviewDialog({
    required this.photoPaths,
    required this.initialIndex,
  });

  final List<String> photoPaths;
  final int initialIndex;

  @override
  State<_PetPhotoPreviewDialog> createState() => _PetPhotoPreviewDialogState();
}

class _PetPhotoPreviewDialogState extends State<_PetPhotoPreviewDialog> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _currentIndex = widget.initialIndex;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showPrevious() {
    if (_currentIndex <= 0) {
      return;
    }
    _pageController.animateToPage(
      _currentIndex - 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _showNext() {
    if (_currentIndex >= widget.photoPaths.length - 1) {
      return;
    }
    _pageController.animateToPage(
      _currentIndex + 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final dialogWidth = maxWidth >= 900 ? maxWidth * 0.92 : maxWidth * 0.94;
        final dialogHeight =
            maxHeight >= 900 ? maxHeight * 0.88 : maxHeight * 0.84;
        final showDesktopControls =
            maxWidth >= 900 && widget.photoPaths.length > 1;
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.arrowLeft): _showPrevious,
            const SingleActivator(LogicalKeyboardKey.arrowRight): _showNext,
            const SingleActivator(LogicalKeyboardKey.escape):
                Navigator.of(context).pop,
          },
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('pet-photo-preview-backdrop'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.84),
                    ),
                  ),
                ),
                Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: dialogWidth.clamp(280.0, 1440.0),
                        maxHeight: dialogHeight.clamp(260.0, 1100.0),
                      ),
                      child: Material(
                        key: const ValueKey('pet-photo-preview-dialog'),
                        color: Colors.transparent,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(24, 28, 24, 56),
                                child: PageView.builder(
                                  key: const ValueKey('pet-photo-preview-pager'),
                                  controller: _pageController,
                                  physics: const BouncingScrollPhysics(),
                                  onPageChanged: (value) {
                                    setState(() => _currentIndex = value);
                                  },
                                  itemCount: widget.photoPaths.length,
                                  itemBuilder: (context, index) {
                                    return Center(
                                      child: PetPhotoContainFrame(
                                        photoPath: widget.photoPaths[index],
                                        borderRadius:
                                            BorderRadius.circular(26),
                                        fallback: const Center(
                                          child: Icon(
                                            Icons.broken_image_rounded,
                                            size: 36,
                                            color: Color(0xFFB8BEC8),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton.filledTonal(
                                key: const ValueKey(
                                  'pet-photo-preview-close-button',
                                ),
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close_rounded),
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.14),
                                  foregroundColor:
                                      Colors.white.withValues(alpha: 0.94),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Center(
                                child: Container(
                                  key: const ValueKey(
                                    'pet-photo-preview-index-indicator',
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${_currentIndex + 1} / ${widget.photoPaths.length}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: Colors.white
                                              .withValues(alpha: 0.82),
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                            if (showDesktopControls)
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                child: _PreviewNavButton(
                                  key: const ValueKey(
                                    'pet-photo-preview-previous-button',
                                  ),
                                  icon: Icons.chevron_left_rounded,
                                  enabled: _currentIndex > 0,
                                  onTap: _showPrevious,
                                ),
                              ),
                            if (showDesktopControls)
                              Positioned(
                                right: 0,
                                top: 0,
                                bottom: 0,
                                child: _PreviewNavButton(
                                  key: const ValueKey(
                                    'pet-photo-preview-next-button',
                                  ),
                                  icon: Icons.chevron_right_rounded,
                                  enabled: _currentIndex <
                                      widget.photoPaths.length - 1,
                                  onTap: _showNext,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PreviewNavButton extends StatelessWidget {
  const _PreviewNavButton({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: IconButton.filled(
          onPressed: enabled ? onTap : null,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            disabledBackgroundColor: Colors.white.withValues(alpha: 0.04),
            foregroundColor: Colors.white.withValues(alpha: 0.92),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.28),
          ),
        ),
      ),
    );
  }
}

Widget _buildRecordIconFallback() {
  return Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: const Color(0xFFE8F7EE),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Center(
      child: Icon(
        Icons.description_rounded,
        color: Color(0xFF4FB57C),
      ),
    ),
  );
}

String _petRecordSubtitle(PetRecord item) {
  final segments = <String>[
    formatDate(item.recordDate, withTime: false),
    _petRecordTypeLabel(item.type),
    if (item.summary.trim().isNotEmpty) item.summary.trim(),
  ];
  return segments.join(' · ');
}

String _petRecordHeroSubtitle(PetRecord item) {
  final segments = <String>[
    formatDate(item.recordDate, withTime: false),
    _petRecordTypeLabel(item.type),
    if (item.photoPaths.isNotEmpty) '${item.photoPaths.length} 张图片',
  ];
  return segments.join(' · ');
}

String _petRecordTypeLabel(PetRecordType type) {
  switch (type) {
    case PetRecordType.medical:
      return '就诊';
    case PetRecordType.testResult:
      return '检查';
    case PetRecordType.receipt:
      return '收据';
    case PetRecordType.image:
      return '图片';
    case PetRecordType.other:
      return '其他';
  }
}

String _petRecordPurposeChoiceLabel(RecordPurpose purpose) {
  switch (purpose) {
    case RecordPurpose.health:
      return '健康';
    case RecordPurpose.life:
      return '生活';
    case RecordPurpose.expense:
      return '消费';
    case RecordPurpose.other:
      return '其他';
  }
}

String _petRecordPurposeLabel(
  RecordPurpose? purpose, {
  String? customPurposeLabel,
}) {
  final customLabel = customPurposeLabel?.trim();
  switch (purpose) {
    case RecordPurpose.health:
      return '健康';
    case RecordPurpose.life:
      return '生活';
    case RecordPurpose.expense:
      return '消费';
    case RecordPurpose.other:
      return customLabel?.isNotEmpty ?? false ? customLabel! : '其他';
    case null:
      return '未分类';
  }
}

String _petReminderKindLabel(ReminderKind kind) {
  switch (kind) {
    case ReminderKind.medication:
      return '用药';
    case ReminderKind.review:
      return '就诊';
    case ReminderKind.vaccine:
      return '疫苗';
    case ReminderKind.grooming:
      return '美容';
    case ReminderKind.deworming:
      return '驱虫';
    case ReminderKind.custom:
      return '其他';
  }
}

String _petReminderStatusLabel(ReminderStatus status) {
  switch (status) {
    case ReminderStatus.pending:
      return '待提醒';
    case ReminderStatus.done:
      return '已完成';
    case ReminderStatus.skipped:
      return '已跳过';
    case ReminderStatus.postponed:
      return '已延后';
    case ReminderStatus.overdue:
      return '已逾期';
  }
}
