import 'dart:async';

import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/data/data_package_file_access.dart';
import 'package:petnote/data/data_storage_coordinator.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/logging/app_log_controller.dart';

class DataStoragePage extends StatefulWidget {
  const DataStoragePage({
    super.key,
    required this.coordinator,
    this.appLogController,
    this.fileAccess,
  });

  final DataStorageCoordinator coordinator;
  final AppLogController? appLogController;
  final DataPackageFileAccess? fileAccess;

  @override
  State<DataStoragePage> createState() => _DataStoragePageState();
}

class _DataStoragePageState extends State<DataStoragePage> {
  _FileActivitySummary? _fileActivity;
  _PageFeedbackState? _feedbackState;
  Timer? _feedbackDismissTimer;

  late final DataPackageFileAccess _fileAccess = widget.fileAccess ??
      MethodChannelDataPackageFileAccess(
        appLogController: widget.appLogController,
      );

  @override
  void dispose() {
    _feedbackDismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.coordinator,
      builder: (context, _) {
        final latest = widget.coordinator.latestOperationResult;
        return Scaffold(
          appBar: AppBar(title: const Text('数据与存储')),
          body: HyperPageBackground(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    HeroPanel(
                      title: '本地数据中心',
                      subtitle: '通过系统文件管理器导入导出数据包，恢复和危险操作都会先走保护流程。',
                      child: Text(
                        widget.coordinator.dataSummary,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: context.petNoteTokens.secondaryText,
                              height: 1.5,
                            ),
                      ),
                    ),
                    SectionCard(
                      title: '最近状态',
                      children: [
                        ListRow(
                          title: latest?.message ?? '尚未执行数据操作',
                          subtitle: latest == null
                              ? '导出备份、恢复备份或清空本地数据后，这里会显示最近一次结果。'
                              : '宠物 ${latest.petsCount} 只 · 待办 ${latest.todosCount} 条 · '
                                  '提醒 ${latest.remindersCount} 条 · 记录 ${latest.recordsCount} 条',
                        ),
                        if (latest?.kind == DataOperationKind.importedReplace)
                          ListRow(
                            title: latest!.restoredSettings
                                ? '本次同时恢复了普通设置'
                                : '本次仅恢复业务数据',
                            subtitle: latest.restoredSettings
                                ? '主题偏好和 AI 配置等非敏感设置已经一起恢复。'
                                : '当前主题偏好和 AI 配置等普通设置保持本地现状。',
                          ),
                        if (_fileActivity != null) ...[
                          const SizedBox(height: 12),
                          ListRow(
                            title: _fileActivity!.title,
                            subtitle:
                                '${_fileActivity!.displayName} · ${_fileActivity!.locationLabel} · ${_fileActivity!.byteLength} bytes',
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    SectionCard(
                      title: '备份与恢复',
                      children: [
                        SettingsActionButtonGroup(
                          children: [
                            SettingsActionButton(
                              buttonKey:
                                  const ValueKey('data_storage_export_button'),
                              priority: SettingsActionPriority.primary,
                              label: '导出完整备份',
                              onPressed: _handleExportBackup,
                            ),
                            SettingsActionButton(
                              buttonKey: const ValueKey(
                                'data_storage_export_ai_button',
                              ),
                              label: '导出 AI 摘要 JSON',
                              onPressed: _handleExportAiSummary,
                            ),
                            SettingsActionButton(
                              buttonKey:
                                  const ValueKey('data_storage_restore_button'),
                              label: '从备份文件恢复',
                              onPressed: _handleRestoreBackup,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SectionCard(
                      title: '危险操作',
                      children: [
                        SettingsActionButtonGroup(
                          children: [
                            SettingsActionButton(
                              buttonKey:
                                  const ValueKey('data_storage_clear_button'),
                              label: '清空本地数据',
                              priority: SettingsActionPriority.dangerSecondary,
                              onPressed: _handleClearAllData,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                if (_feedbackState != null)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: MediaQuery.viewPaddingOf(context).bottom + 24,
                    child: PageFeedbackBanner(
                      key: const ValueKey('data_storage_feedback_banner'),
                      message: _feedbackState!.message,
                      tone: _feedbackState!.isError
                          ? PageFeedbackTone.error
                          : PageFeedbackTone.success,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleExportBackup() async {
    try {
      final includeSensitiveSettings = await _confirmExportBackup(
        context,
        supportsSensitiveSettings:
            await widget.coordinator.secretStore.isAvailable(),
      );
      if (!mounted || includeSensitiveSettings == null) {
        return;
      }
      final package = await widget.coordinator.createBackupPackage(
        packageName: 'PetNote 完整备份',
        description: '手动生成的完整备份包',
        options: DataExportOptions(
          includeSensitiveSettings: includeSensitiveSettings,
        ),
      );
      final saved = await _fileAccess.saveBackupFile(
        suggestedFileName: _backupFileName(package.createdAt),
        rawJson: package.toPrettyJson(),
      );
      if (!mounted || saved == null) {
        return;
      }
      setState(() {
        _fileActivity = _FileActivitySummary(
          title: '备份文件已保存',
          displayName: saved.displayName,
          locationLabel: saved.locationLabel,
          byteLength: saved.byteLength,
        );
      });
      _showFeedback(
        '备份已保存到 ${saved.locationLabel} · ${saved.displayName}',
      );
    } on DataPackageFileException catch (error) {
      _showFileError(error);
    }
  }

  Future<void> _handleRestoreBackup() async {
    try {
      final picked = await _fileAccess.pickBackupFile();
      if (!mounted || picked == null) {
        return;
      }
      await _openPickedFile(picked);
    } on DataPackageFileException catch (error) {
      _showFileError(error);
    }
  }

  Future<void> _handleExportAiSummary() async {
    try {
      final package = widget.coordinator.createAiSummaryPackage();
      final saved = await _fileAccess.saveBackupFile(
        suggestedFileName: _aiSummaryFileName(),
        rawJson: package.toPrettyJson(),
      );
      if (!mounted || saved == null) {
        return;
      }
      setState(() {
        _fileActivity = _FileActivitySummary(
          title: 'AI 摘要文件已保存',
          displayName: saved.displayName,
          locationLabel: saved.locationLabel,
          byteLength: saved.byteLength,
        );
      });
      _showFeedback(
        'AI 摘要已保存到 ${saved.locationLabel} · ${saved.displayName}',
      );
    } on DataPackageFileException catch (error) {
      _showFileError(error);
    }
  }

  Future<void> _openPickedFile(PickedDataPackageFile picked) async {
    final package = _parsePickedPackage(picked);
    if (package == null || !mounted) {
      return;
    }
    final reviewResult = await Navigator.of(context).push<_ReviewPageResult>(
      MaterialPageRoute<_ReviewPageResult>(
        builder: (_) => DataPackageReviewPage(
          coordinator: widget.coordinator,
          pickedFile: picked,
          package: package,
        ),
      ),
    );
    if (!mounted || reviewResult == null) {
      return;
    }
    setState(() {
      _fileActivity = _FileActivitySummary(
        title: reviewResult.fileTitle,
        displayName: picked.displayName,
        locationLabel: picked.locationLabel,
        byteLength: picked.byteLength,
      );
    });
    _showFeedback(reviewResult.message);
  }

  PetNoteDataPackage? _parsePickedPackage(PickedDataPackageFile picked) {
    try {
      final package = widget.coordinator.parsePackageJson(picked.rawJson);
      final validationError = widget.coordinator.validatePackage(package);
      if (validationError != null) {
        _showFeedback(validationError, isError: true);
        return null;
      }
      return package;
    } on FormatException catch (error) {
      _showFeedback(error.message, isError: true);
      return null;
    } catch (_) {
      _showFeedback('文件内容解析失败，请检查 JSON 格式。', isError: true);
      return null;
    }
  }

  Future<void> _handleClearAllData() async {
    final confirmed = await _confirmDanger(
      context,
      action: DataDangerAction.clearLocalData,
    );
    if (!confirmed) {
      return;
    }
    final result = await widget.coordinator.clearAllData();
    if (!mounted) {
      return;
    }
    _showFeedback(result.message);
  }

  void _showFileError(DataPackageFileException error) {
    if (error.code == DataPackageFileErrorCode.cancelled) {
      return;
    }
    _showFeedback(_fileErrorMessage(error), isError: true);
  }

  void _showFeedback(String message, {bool isError = false}) {
    _feedbackDismissTimer?.cancel();
    setState(() {
      _feedbackState = _PageFeedbackState(
        message: message,
        isError: isError,
      );
    });
    _feedbackDismissTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _feedbackState = null;
      });
    });
  }
}

class DataPackageReviewPage extends StatefulWidget {
  const DataPackageReviewPage({
    super.key,
    required this.coordinator,
    required this.pickedFile,
    required this.package,
  });

  final DataStorageCoordinator coordinator;
  final PickedDataPackageFile pickedFile;
  final PetNoteDataPackage package;

  @override
  State<DataPackageReviewPage> createState() => _DataPackageReviewPageState();
}

class _DataPackageReviewPageState extends State<DataPackageReviewPage> {
  bool _submitting = false;
  String? _errorMessage;
  bool _restoreSettings = false;
  bool _restoreSensitiveSettings = false;

  bool get _hasSensitiveSettings =>
      widget.package.sensitiveSettings?.hasSecrets ?? false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入预览')),
      body: HyperPageBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            HeroPanel(
              title: '导入预览',
              subtitle: '恢复前先确认覆盖范围和风险提示。',
              child: const SizedBox.shrink(),
            ),
            SectionCard(
              title: '文件信息',
              children: [
                ListRow(
                  title: widget.pickedFile.displayName,
                  subtitle:
                      '${widget.pickedFile.locationLabel} · ${widget.pickedFile.byteLength} bytes',
                ),
              ],
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: '数据包内容',
              children: [
                ListRow(
                  title: widget.package.packageName,
                  subtitle:
                      '${widget.package.packageType.name} · 宠物 ${widget.package.data.pets.length} 只 · '
                      '待办 ${widget.package.data.todos.length} 条 · '
                      '提醒 ${widget.package.data.reminders.length} 条 · '
                      '记录 ${widget.package.data.records.length} 条',
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.red.shade700,
                        ),
                  ),
                ],
                if (widget.package.settings != null) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const ValueKey('data_package_restore_settings_toggle'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('恢复设置内容'),
                    subtitle: Text(
                      _restoreSettings
                          ? '会额外恢复主题偏好和 AI 配置等普通设置。'
                          : '默认仅恢复宠物、待办、提醒和记录，当前设置保持不变。',
                    ),
                    value: _restoreSettings,
                    onChanged: (value) {
                      setState(() {
                        _restoreSettings = value;
                      });
                    },
                  ),
                ],
                if (_hasSensitiveSettings) ...[
                  const SizedBox(height: 12),
                  const ListRow(
                    title: '检测到敏感信息',
                    subtitle: '该备份文件包含 API Key，恢复前需要再次确认。',
                  ),
                  SwitchListTile(
                    key:
                        const ValueKey('data_package_restore_sensitive_toggle'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('同时恢复 API Key'),
                    subtitle: Text(
                      _restoreSettings
                          ? '开启后会在恢复业务数据与普通设置后，再次确认是否写回 API Key。'
                          : '需要先开启“恢复设置内容”，才能决定是否恢复 API Key。',
                    ),
                    value: _restoreSensitiveSettings,
                    onChanged: !_restoreSettings
                        ? null
                        : (value) {
                            setState(() {
                              _restoreSensitiveSettings = value;
                            });
                          },
                  ),
                ],
                const SizedBox(height: 12),
                SettingsActionButtonGroup(
                  children: [
                    SettingsActionButton(
                      buttonKey:
                          const ValueKey('data_package_execute_restore_button'),
                      priority: SettingsActionPriority.primary,
                      label: _submitting ? '处理中...' : '从备份文件恢复',
                      onPressed: _submitting ? null : _submit,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final confirmed = await _confirmDanger(
      context,
      action: DataDangerAction.restoreFromBackupFile,
      restoreSettings: _restoreSettings,
    );
    if (!confirmed) {
      return;
    }
    var restoreSensitiveSettings = false;
    if (_restoreSettings &&
        _restoreSensitiveSettings &&
        _hasSensitiveSettings &&
        mounted) {
      restoreSensitiveSettings = await _confirmSensitiveRestore(context);
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final result = await widget.coordinator.importPackage(
      package: widget.package,
      options: DataImportOptions(
        restoreSettings: _restoreSettings,
        restoreSensitiveSettings: restoreSensitiveSettings,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _errorMessage = result.isSuccess ? null : result.message;
    });
    if (!result.isSuccess) {
      return;
    }
    Navigator.of(context).pop(
      _ReviewPageResult(
        message: result.message,
        fileTitle: '备份文件已恢复',
      ),
    );
  }
}

enum DataDangerAction {
  restoreFromBackupFile,
  clearLocalData,
}

class BackupExportDialog extends StatefulWidget {
  const BackupExportDialog({
    super.key,
    required this.supportsSensitiveSettings,
  });

  final bool supportsSensitiveSettings;

  @override
  State<BackupExportDialog> createState() => _BackupExportDialogState();
}

class _BackupExportDialogState extends State<BackupExportDialog> {
  bool _includeSensitiveSettings = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '确认导出备份',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 14),
              const Text('默认会导出业务数据与普通设置，不包含 API Key。'),
              const SizedBox(height: 12),
              SwitchListTile(
                key: const ValueKey('backup_export_include_sensitive_toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('同时导出 API Key'),
                subtitle: Text(
                  widget.supportsSensitiveSettings
                      ? '启用后，导出的 JSON 会包含敏感信息，请妥善保管文件。'
                      : '当前平台安全存储不可用，无法导出 API Key。',
                ),
                value: _includeSensitiveSettings,
                onChanged: !widget.supportsSensitiveSettings
                    ? null
                    : (value) {
                        setState(() {
                          _includeSensitiveSettings = value;
                        });
                      },
              ),
              const SizedBox(height: 16),
              _DangerDialogActionBar(
                confirmLabel: '继续导出',
                cancelButtonKey: const ValueKey('backup_export_cancel_button'),
                confirmButtonKey:
                    const ValueKey('backup_export_confirm_button'),
                onCancel: () => Navigator.of(context).pop(),
                onConfirm: () async {
                  if (_includeSensitiveSettings) {
                    final confirmed = await _showSensitiveExportConfirmDialog(
                      context,
                    );
                    if (!context.mounted || !confirmed) {
                      return;
                    }
                  }
                  if (!context.mounted) {
                    return;
                  }
                  Navigator.of(context).pop(_includeSensitiveSettings);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DangerConfirmDialog extends StatelessWidget {
  const DangerConfirmDialog({
    super.key,
    this.action,
    this.restoreSettings = false,
    this.titleOverride,
    this.descriptionOverride,
    this.impactOverride,
    this.snapshotNoticeOverride,
    this.confirmLabelOverride,
    this.cancelButtonKeyOverride,
    this.confirmButtonKeyOverride,
  }) : assert(
          action != null ||
              (titleOverride != null &&
                  descriptionOverride != null &&
                  impactOverride != null &&
                  snapshotNoticeOverride != null &&
                  confirmLabelOverride != null),
        );

  final DataDangerAction? action;
  final bool restoreSettings;
  final String? titleOverride;
  final String? descriptionOverride;
  final String? impactOverride;
  final String? snapshotNoticeOverride;
  final String? confirmLabelOverride;
  final Key? cancelButtonKeyOverride;
  final Key? confirmButtonKeyOverride;

  @override
  Widget build(BuildContext context) {
    final copy = titleOverride == null
        ? _dangerCopy(
            action!,
            restoreSettings: restoreSettings,
          )
        : _DangerCopy(
            title: titleOverride!,
            description: descriptionOverride!,
            impact: impactOverride!,
            snapshotNotice: snapshotNoticeOverride!,
            confirmLabel: confirmLabelOverride!,
          );
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    copy.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: tokens.primaryText,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    copy.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.primaryText,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    copy.impact,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.secondaryText,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    copy.snapshotNotice,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.secondaryText,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: _DangerDialogActionBar(
                confirmLabel: copy.confirmLabel,
                onCancel: () => Navigator.of(context).pop(false),
                onConfirm: () => Navigator.of(context).pop(true),
                cancelButtonKey: cancelButtonKeyOverride ??
                    const ValueKey('danger_confirm_cancel_button'),
                confirmButtonKey: confirmButtonKeyOverride ??
                    const ValueKey('danger_confirm_action_button'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DangerDialogActionBar extends StatelessWidget {
  const _DangerDialogActionBar({
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.cancelButtonKey = const ValueKey('danger_confirm_cancel_button'),
    this.confirmButtonKey = const ValueKey('danger_confirm_action_button'),
  });

  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final Key cancelButtonKey;
  final Key confirmButtonKey;

  @override
  Widget build(BuildContext context) {
    final shouldStack = MediaQuery.textScalerOf(context).scale(1) > 1.15;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackVertically = shouldStack || constraints.maxWidth < 320;
        if (stackVertically) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DangerDialogActionButton(
                buttonKey: cancelButtonKey,
                label: '取消',
                onPressed: onCancel,
              ),
              const SizedBox(height: 12),
              _DangerDialogActionButton(
                buttonKey: confirmButtonKey,
                label: confirmLabel,
                priority: SettingsActionPriority.primary,
                onPressed: onConfirm,
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: _DangerDialogActionButton(
                buttonKey: cancelButtonKey,
                label: '取消',
                onPressed: onCancel,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DangerDialogActionButton(
                buttonKey: confirmButtonKey,
                label: confirmLabel,
                priority: SettingsActionPriority.primary,
                onPressed: onConfirm,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DangerDialogActionButton extends StatelessWidget {
  const _DangerDialogActionButton({
    required this.buttonKey,
    required this.label,
    required this.onPressed,
    this.priority = SettingsActionPriority.secondary,
  });

  final Key buttonKey;
  final String label;
  final VoidCallback onPressed;
  final SettingsActionPriority priority;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final isPrimary = priority == SettingsActionPriority.primary;
    final borderColor = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.22)
        : const Color(0xFFB08D56);
    final foregroundColor = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.86)
        : const Color(0xFF8E6B34);
    final textStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );

    final child = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size(double.infinity, SettingsActionButton.height),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      shape: WidgetStatePropertyAll(shape),
      textStyle: WidgetStatePropertyAll(textStyle),
      alignment: Alignment.center,
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: WidgetStatePropertyAll(
        isPrimary
            ? BorderSide.none
            : BorderSide(color: borderColor, width: 1.2),
      ),
      backgroundColor: WidgetStatePropertyAll(
        isPrimary ? theme.colorScheme.primary : Colors.transparent,
      ),
      foregroundColor: WidgetStatePropertyAll(
        isPrimary ? Colors.white : foregroundColor,
      ),
      overlayColor: WidgetStatePropertyAll(
        isPrimary
            ? Colors.white.withValues(alpha: 0.08)
            : tokens.secondaryText.withValues(alpha: 0.08),
      ),
    );

    return isPrimary
        ? FilledButton(
            key: buttonKey,
            onPressed: onPressed,
            style: style,
            child: child,
          )
        : OutlinedButton(
            key: buttonKey,
            onPressed: onPressed,
            style: style,
            child: child,
          );
  }
}

Future<bool> _confirmDanger(
  BuildContext context, {
  required DataDangerAction action,
  bool restoreSettings = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => DangerConfirmDialog(
      action: action,
      restoreSettings: restoreSettings,
    ),
  );
  return confirmed ?? false;
}

Future<bool?> _confirmExportBackup(
  BuildContext context, {
  required bool supportsSensitiveSettings,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => BackupExportDialog(
      supportsSensitiveSettings: supportsSensitiveSettings,
    ),
  );
}

Future<bool> _showSensitiveExportConfirmDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const DangerConfirmDialog(
      titleOverride: '确认导出 API Key',
      descriptionOverride: '该备份文件会包含可直接调用第三方 AI 服务的 API Key。',
      impactOverride: '如果文件泄露，可能带来额度损失或账户风险。',
      snapshotNoticeOverride: '继续前请确认你理解该备份文件将持有敏感信息。',
      confirmLabelOverride: '确认导出 API Key',
      cancelButtonKeyOverride:
          ValueKey('backup_export_sensitive_cancel_button'),
      confirmButtonKeyOverride:
          ValueKey('backup_export_sensitive_confirm_button'),
    ),
  );
  return confirmed ?? false;
}

Future<bool> _confirmSensitiveRestore(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const DangerConfirmDialog(
      titleOverride: '确认恢复 API Key',
      descriptionOverride: '这会把备份中的 API Key 写回当前设备的安全存储。',
      impactOverride: '如果当前已有本地 API Key，它们可能会被备份内容覆盖。',
      snapshotNoticeOverride: '取消后仍会继续恢复业务数据与普通设置，但不会写回 API Key。',
      confirmLabelOverride: '确认恢复 API Key',
      cancelButtonKeyOverride: ValueKey('sensitive_restore_cancel_button'),
      confirmButtonKeyOverride: ValueKey('sensitive_restore_confirm_button'),
    ),
  );
  return confirmed ?? false;
}

_DangerCopy _dangerCopy(
  DataDangerAction action, {
  required bool restoreSettings,
}) {
  return switch (action) {
    DataDangerAction.restoreFromBackupFile => _DangerCopy(
        title: '确认从备份文件恢复',
        description: restoreSettings
            ? '当前本地业务数据和普通设置都会被备份内容覆盖。'
            : '当前本地业务数据会被备份内容覆盖，当前设置保留不变。',
        impact: restoreSettings
            ? '这会替换宠物、待办、提醒、记录以及主题偏好、AI 配置等非敏感设置。'
            : '这会替换宠物、待办、提醒和记录，主题偏好与 AI 配置等普通设置保持当前状态。',
        snapshotNotice: '执行前会自动完成内部保护，当前界面不提供手动回滚入口。',
        confirmLabel: '确认恢复备份',
      ),
    DataDangerAction.clearLocalData => const _DangerCopy(
        title: '确认清空本地数据',
        description: '业务数据和普通设置会被清空。',
        impact: '清空后应用会回到接近首次使用的本地状态。',
        snapshotNotice: '执行前会自动完成内部保护，当前界面不提供手动恢复入口。',
        confirmLabel: '确认清空本地数据',
      ),
  };
}

String _backupFileName(DateTime createdAt) {
  final year = createdAt.year.toString().padLeft(4, '0');
  final month = createdAt.month.toString().padLeft(2, '0');
  final day = createdAt.day.toString().padLeft(2, '0');
  final hour = createdAt.hour.toString().padLeft(2, '0');
  final minute = createdAt.minute.toString().padLeft(2, '0');
  return 'petnote_backup_$year$month${day}_$hour$minute.json';
}

String _aiSummaryFileName() {
  return 'petnote_ai_summary.json';
}

String _fileErrorMessage(DataPackageFileException error) {
  return switch (error.code) {
    DataPackageFileErrorCode.unavailable => '系统文件管理器当前不可用：${error.message}',
    DataPackageFileErrorCode.readFailed => '文件读取失败：${error.message}',
    DataPackageFileErrorCode.writeFailed => '文件写入失败：${error.message}',
    DataPackageFileErrorCode.invalidResponse => '服务返回格式异常：${error.message}',
    DataPackageFileErrorCode.cancelled => '',
  };
}

class _DangerCopy {
  const _DangerCopy({
    required this.title,
    required this.description,
    required this.impact,
    required this.snapshotNotice,
    required this.confirmLabel,
  });

  final String title;
  final String description;
  final String impact;
  final String snapshotNotice;
  final String confirmLabel;
}

class _ReviewPageResult {
  const _ReviewPageResult({
    required this.message,
    required this.fileTitle,
  });

  final String message;
  final String fileTitle;
}

class _FileActivitySummary {
  const _FileActivitySummary({
    required this.title,
    required this.displayName,
    required this.locationLabel,
    required this.byteLength,
  });

  final String title;
  final String displayName;
  final String locationLabel;
  final int byteLength;
}

class _PageFeedbackState {
  const _PageFeedbackState({
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;
}
