import 'dart:async';

import 'package:flutter/material.dart';
import 'package:petnote/ai/ai_connection_tester.dart';
import 'package:petnote/ai/ai_provider_config.dart';
import 'package:petnote/ai/ai_settings_coordinator.dart';
import 'package:petnote/ai/ai_url_utils.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/native_option_picker.dart';
import 'package:petnote/state/app_settings_controller.dart';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({
    super.key,
    required this.settingsController,
    required this.coordinator,
  });

  final AppSettingsController settingsController;
  final AiSettingsCoordinator coordinator;

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  _AiSettingsFeedbackState? _feedbackState;
  Timer? _feedbackDismissTimer;
  String? _testingConfigId;

  @override
  void dispose() {
    _feedbackDismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settingsController,
      builder: (context, _) {
        final configs = widget.settingsController.aiProviderConfigs;
        final activeConfig = widget.settingsController.activeAiProviderConfig;
        return Scaffold(
          appBar: AppBar(title: const Text('AI 配置')),
          body: HyperPageBackground(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    const HeroPanel(
                      title: '管理 AI 能力入口',
                      subtitle:
                          '这里保存的是你自己的 AI 服务配置。PetNote 不托管你的 API Key，只用当前激活的一套配置驱动 AI 能力。',
                      child: SizedBox.shrink(),
                    ),
                    FutureBuilder<bool>(
                      future: widget.coordinator.isSecretStoreAvailable(),
                      builder: (context, snapshot) {
                        if (snapshot.data == false) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 18),
                            child: SectionCard(
                              title: '安全存储不可用',
                              children: [
                                ListRow(
                                  title: '当前平台暂不可保存 API Key',
                                  subtitle:
                                      '请先确认系统安全存储能力可用。PetNote 不会降级为普通明文存储。',
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox(height: 18);
                      },
                    ),
                    SettingsActionButton(
                      buttonKey: const ValueKey('ai_add_config_button'),
                      priority: SettingsActionPriority.primary,
                      icon: Icons.add_rounded,
                      label: '新增配置',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => AiConfigEditorPage(
                            settingsController: widget.settingsController,
                            coordinator: widget.coordinator,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SectionCard(
                      title: '当前使用',
                      children: [
                        ListRow(
                          title: activeConfig?.displayName ?? '未配置 AI 服务',
                          subtitle: activeConfig == null
                              ? '请先新增一套可用的 AI 提供商配置。'
                              : '${aiProviderLabel(activeConfig.providerType)} · '
                                  '${activeConfig.model}\n'
                                  '${activeConfig.lastConnectionMessage ?? aiConnectionStatusLabel(activeConfig.lastConnectionStatus)}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SectionCard(
                      title: '配置列表',
                      children: configs.isEmpty
                          ? const [
                              ListRow(
                                title: '还没有任何 AI 配置',
                                subtitle:
                                    '你可以先添加 OpenAI、Anthropic 或兼容 OpenAI 的服务配置。',
                              ),
                            ]
                          : configs
                              .map(
                                (config) => Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _AiConfigCard(
                                    config: config,
                                    coordinator: widget.coordinator,
                                    settingsController:
                                        widget.settingsController,
                                    isTesting: _testingConfigId == config.id,
                                    isTestLocked: _testingConfigId != null,
                                    onTestConnection: () =>
                                        _handleTestConnection(config),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ],
                ),
                if (_feedbackState != null)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: MediaQuery.viewPaddingOf(context).bottom + 24,
                    child: PageFeedbackBanner(
                      key: const ValueKey('ai_settings_feedback_banner'),
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

  Future<void> _handleTestConnection(AiProviderConfig config) async {
    if (_testingConfigId != null) {
      return;
    }
    setState(() {
      _testingConfigId = config.id;
    });
    try {
      final result = await widget.coordinator.testConnection(
        providerType: config.providerType,
        baseUrl: config.baseUrl,
        model: config.model,
        apiKey: null,
        existingConfigId: config.id,
      );
      await widget.settingsController.updateAiProviderConnectionStatus(
        configId: config.id,
        status: result.status,
        checkedAt: DateTime.now(),
        message: result.message,
      );
      if (!mounted) {
        return;
      }
      _showFeedback(
        result.message,
        isError: !_isSuccessfulConnectionStatus(result.status),
      );
    } finally {
      if (mounted) {
        setState(() {
          _testingConfigId = null;
        });
      }
    }
  }

  void _showFeedback(String message, {bool isError = false}) {
    _feedbackDismissTimer?.cancel();
    setState(() {
      _feedbackState = _AiSettingsFeedbackState(
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

class _AiConfigCard extends StatelessWidget {
  const _AiConfigCard({
    required this.config,
    required this.coordinator,
    required this.settingsController,
    required this.isTesting,
    required this.isTestLocked,
    required this.onTestConnection,
  });

  final AiProviderConfig config;
  final AiSettingsCoordinator coordinator;
  final AppSettingsController settingsController;
  final bool isTesting;
  final bool isTestLocked;
  final Future<void> Function() onTestConnection;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: coordinator.hasSavedKey(config.id),
      builder: (context, snapshot) {
        final hasSavedKey = snapshot.data ?? false;
        return Column(
          children: [
            ListRow(
              title: config.displayName,
              subtitle:
                  '${aiProviderLabel(config.providerType)} · ${config.model}\n'
                  '${hasSavedKey ? '已保存 API Key' : '尚未保存 API Key'}\n'
                  '${isTesting ? '正在测试连接，请稍候。' : (config.lastConnectionMessage ?? aiConnectionStatusLabel(config.lastConnectionStatus))}',
              trailing: config.isActive
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF0FF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '当前使用',
                        style: TextStyle(
                          color: Color(0xFF335FCA),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : null,
            ),
            if (isTesting) ...[
              const SizedBox(height: 10),
              _AiConnectionTestingNotice(
                key: ValueKey('ai_config_testing_indicator_${config.id}'),
                message: '正在测试连接，请稍候。',
              ),
            ],
            const SizedBox(height: 10),
            SettingsActionButtonGroup(
              children: [
                SettingsActionButton(
                  buttonKey: ValueKey('ai_config_activate_button_${config.id}'),
                  label: config.isActive ? '当前使用中' : '设为当前',
                  onPressed: config.isActive
                      ? null
                      : () => settingsController.setActiveAiProviderConfig(
                            config.id,
                          ),
                ),
                SettingsActionButton(
                  buttonKey: ValueKey('ai_config_test_button_${config.id}'),
                  label: isTesting ? '测试中...' : '测试连接',
                  onPressed: isTestLocked ? null : onTestConnection,
                ),
                SettingsActionButton(
                  buttonKey: ValueKey('ai_config_edit_button_${config.id}'),
                  label: '编辑',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => AiConfigEditorPage(
                        settingsController: settingsController,
                        coordinator: coordinator,
                        initialConfig: config,
                      ),
                    ),
                  ),
                ),
                SettingsActionButton(
                  buttonKey: ValueKey('ai_config_delete_button_${config.id}'),
                  label: '删除',
                  priority: SettingsActionPriority.dangerSecondary,
                  onPressed: () async {
                    await coordinator.deleteConfig(config.id);
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class AiConfigEditorPage extends StatefulWidget {
  const AiConfigEditorPage({
    super.key,
    required this.settingsController,
    required this.coordinator,
    this.initialConfig,
    this.nativeOptionPicker,
  });

  final AppSettingsController settingsController;
  final AiSettingsCoordinator coordinator;
  final AiProviderConfig? initialConfig;
  final NativeOptionPicker? nativeOptionPicker;

  @override
  State<AiConfigEditorPage> createState() => _AiConfigEditorPageState();
}

class _AiConfigEditorPageState extends State<AiConfigEditorPage> {
  late AiProviderType _providerType;
  late final TextEditingController _displayNameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  AiConnectionTestResult? _testResult;
  bool _saving = false;
  bool _testing = false;
  bool _isApiKeyVisible = false;
  _AiSettingsFeedbackState? _feedbackState;
  Timer? _feedbackDismissTimer;
  late final NativeOptionPicker _nativeOptionPicker =
      widget.nativeOptionPicker ?? MethodChannelNativeOptionPicker();

  @override
  void initState() {
    super.initState();
    final initialConfig = widget.initialConfig;
    _providerType = initialConfig?.providerType ?? AiProviderType.openai;
    _displayNameController = TextEditingController(
      text: initialConfig?.displayName ?? '',
    );
    _baseUrlController = TextEditingController(
      text: initialConfig?.baseUrl ?? defaultBaseUrlForProvider(_providerType),
    );
    _modelController = TextEditingController(text: initialConfig?.model ?? '');
    _apiKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _feedbackDismissTimer?.cancel();
    _displayNameController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialConfig = widget.initialConfig;
    final tokens = context.petNoteTokens;
    return Scaffold(
      appBar: AppBar(
        title: Text(initialConfig == null ? '新增 AI 配置' : '编辑 AI 配置'),
      ),
      body: HyperPageBackground(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                SectionCard(
                  title: '基础信息',
                  children: [
                    _NativeOptionField(
                      key: const ValueKey('ai_config_provider_field'),
                      label: '供应商类型',
                      value: aiProviderLabel(_providerType),
                      onTap: _pickProviderType,
                    ),
                    const SizedBox(height: 14),
                    HyperTextField(
                      key: const ValueKey('ai_config_display_name_field'),
                      controller: _displayNameController,
                      hintText: '例如：OpenAI 主账号',
                    ),
                    const SizedBox(height: 14),
                    HyperTextField(
                      key: const ValueKey('ai_config_base_url_field'),
                      controller: _baseUrlController,
                      hintText: '例如：https://api.openai.com/v1',
                    ),
                    const SizedBox(height: 14),
                    HyperTextField(
                      key: const ValueKey('ai_config_model_field'),
                      controller: _modelController,
                      hintText: '例如：gpt-5.4',
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const ValueKey('ai_config_api_key_field'),
                      controller: _apiKeyController,
                      obscureText: !_isApiKeyVisible,
                      decoration: InputDecoration(
                        hintText: initialConfig == null
                            ? '请输入 API Key'
                            : '已保存，留空则保持不变',
                        suffixIcon: IconButton(
                          key: const ValueKey(
                            'ai_config_api_key_visibility_button',
                          ),
                          tooltip:
                              _isApiKeyVisible ? '隐藏 API Key' : '显示 API Key',
                          icon: Icon(
                            _isApiKeyVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _isApiKeyVisible = !_isApiKeyVisible;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SectionCard(
                  title: '连接测试',
                  children: [
                    ListRow(
                      title: '最近结果',
                      subtitle: _testing
                          ? '正在测试连接，请稍候。'
                          : _testResult?.message ??
                              initialConfig?.lastConnectionMessage ??
                              aiConnectionStatusLabel(
                                initialConfig?.lastConnectionStatus ??
                                    AiConnectionStatus.unknown,
                              ),
                    ),
                    const SizedBox(height: 12),
                    SettingsActionButtonGroup(
                      children: [
                        SettingsActionButton(
                          buttonKey: const ValueKey('ai_config_test_button'),
                          priority: SettingsActionPriority.primary,
                          label: _testing ? '测试中...' : '测试连接',
                          onPressed: _testing ? null : _testConnection,
                        ),
                        SettingsActionButton(
                          buttonKey: const ValueKey('ai_config_save_button'),
                          label: _saving ? '保存中...' : '保存配置',
                          onPressed: _saving ? null : _save,
                        ),
                      ],
                    ),
                    if (_testing) ...[
                      const SizedBox(height: 12),
                      const _AiConnectionTestingNotice(
                        key: ValueKey('ai_config_editor_testing_indicator'),
                        message: '正在测试连接，请稍候。',
                      ),
                    ] else if (_testResult != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _testResult!.message,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: tokens.secondaryText,
                            ),
                      ),
                    ],
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
                  key: const ValueKey('ai_settings_feedback_banner'),
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
  }

  Future<void> _testConnection() async {
    final validationError =
        _validateInputs(requireApiKey: widget.initialConfig == null);
    if (validationError != null) {
      _showFeedback(validationError, isError: true);
      return;
    }
    setState(() {
      _testing = true;
    });
    try {
      final result = await widget.coordinator.testConnection(
        providerType: _providerType,
        baseUrl: _baseUrlController.text.trim(),
        model: _modelController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        existingConfigId: widget.initialConfig?.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _testResult = result;
      });
      _showFeedback(
        result.message,
        isError: !_isSuccessfulConnectionStatus(result.status),
      );
    } finally {
      if (mounted) {
        setState(() {
          _testing = false;
        });
      }
    }
  }

  Future<void> _pickProviderType() async {
    if (_shouldUseFlutterProviderPicker(context)) {
      final selectedValue = await _showFlutterProviderPicker(context);
      if (!mounted || selectedValue == null) {
        return;
      }
      _applyProviderTypeSelection(selectedValue);
      return;
    }
    final result = await _nativeOptionPicker.pickSingleOption(
      NativeOptionPickerRequest(
        title: '选择供应商类型',
        selectedValue: _providerType.name,
        options: AiProviderType.values
            .map(
              (providerType) => NativeOptionItem(
                value: providerType.name,
                label: aiProviderLabel(providerType),
              ),
            )
            .toList(),
      ),
    );
    if (!mounted || result.isCancelled) {
      return;
    }
    if (!result.isSuccess) {
      _showFeedback(result.errorMessage ?? '原生选项选择器当前不可用。', isError: true);
      return;
    }
    final selectedValue = result.selectedValue;
    if (selectedValue == null || selectedValue.isEmpty) {
      _showFeedback('原生选项选择器返回了无效的供应商类型。', isError: true);
      return;
    }
    _applyProviderTypeSelection(aiProviderTypeFromName(selectedValue));
  }

  Future<AiProviderType?> _showFlutterProviderPicker(BuildContext context) {
    final tokens = context.petNoteTokens;
    return showModalBottomSheet<AiProviderType>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: tokens.panelBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              key: const ValueKey('ai_provider_bottom_sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择供应商类型',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: tokens.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 16),
                ...AiProviderType.values.map(
                  (providerType) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _FlutterProviderOptionTile(
                      providerType: providerType,
                      selected: providerType == _providerType,
                      onTap: () => Navigator.of(context).pop(providerType),
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

  void _applyProviderTypeSelection(AiProviderType value) {
    final previousProviderType = _providerType;
    final previousDefaultBaseUrl =
        defaultBaseUrlForProvider(previousProviderType);
    final nextDefaultBaseUrl = defaultBaseUrlForProvider(value);
    setState(() {
      _providerType = value;
      final currentBaseUrl = _baseUrlController.text.trim();
      if (currentBaseUrl.isEmpty || currentBaseUrl == previousDefaultBaseUrl) {
        _baseUrlController.text = nextDefaultBaseUrl;
      }
    });
  }

  bool _shouldUseFlutterProviderPicker(BuildContext context) {
    return Theme.of(context).platform == TargetPlatform.android;
  }

  Future<void> _save() async {
    final validationError =
        _validateInputs(requireApiKey: widget.initialConfig == null);
    if (validationError != null) {
      _showFeedback(validationError, isError: true);
      return;
    }
    setState(() {
      _saving = true;
    });
    final now = DateTime.now();
    final initialConfig = widget.initialConfig;
    final config = AiProviderConfig(
      id: initialConfig?.id ?? 'ai_${now.microsecondsSinceEpoch}',
      displayName: _displayNameController.text.trim(),
      providerType: _providerType,
      baseUrl: _baseUrlController.text.trim(),
      model: _modelController.text.trim(),
      isActive: initialConfig?.isActive ?? true,
      createdAt: initialConfig?.createdAt ?? now,
      updatedAt: now,
      lastConnectionStatus: _testResult?.status ??
          initialConfig?.lastConnectionStatus ??
          AiConnectionStatus.unknown,
      lastConnectionCheckedAt:
          _testResult == null ? initialConfig?.lastConnectionCheckedAt : now,
      lastConnectionMessage:
          _testResult?.message ?? initialConfig?.lastConnectionMessage,
    );
    await widget.coordinator.saveConfig(
      config: config,
      apiKey: _apiKeyController.text.trim(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
    });
    Navigator.of(context).pop();
  }

  String? _validateInputs({required bool requireApiKey}) {
    if (_displayNameController.text.trim().isEmpty) {
      return '请填写显示名称。';
    }
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isEmpty) {
      return _providerType == AiProviderType.openaiCompatible
          ? '兼容 OpenAI 的配置需要填写 Base URL。'
          : '请填写 Base URL。';
    }
    if (!isValidAiBaseUrl(baseUrl)) {
      return '请填写合法的 Base URL，例如 https://api.openai.com/v1 。';
    }
    if (_modelController.text.trim().isEmpty) {
      return '请填写模型名称。';
    }
    if (requireApiKey && _apiKeyController.text.trim().isEmpty) {
      return '请填写 API Key。';
    }
    return null;
  }

  void _showFeedback(String message, {bool isError = false}) {
    _feedbackDismissTimer?.cancel();
    setState(() {
      _feedbackState = _AiSettingsFeedbackState(
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

bool _isSuccessfulConnectionStatus(AiConnectionStatus status) {
  return status == AiConnectionStatus.success;
}

class _AiSettingsFeedbackState {
  const _AiSettingsFeedbackState({
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;
}

class _AiConnectionTestingNotice extends StatelessWidget {
  const _AiConnectionTestingNotice({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.listRowBackground,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.secondaryText,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NativeOptionField extends StatelessWidget {
  const _NativeOptionField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: Icon(Icons.unfold_more_rounded),
          ),
          isEmpty: false,
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: tokens.primaryText,
                ),
          ),
        ),
      ),
    );
  }
}

class _FlutterProviderOptionTile extends StatelessWidget {
  const _FlutterProviderOptionTile({
    required this.providerType,
    required this.selected,
    required this.onTap,
  });

  final AiProviderType providerType;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: selected
                ? tokens.segmentedSelectedBackground.withValues(alpha: 0.16)
                : tokens.panelStrongBackground,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? tokens.segmentedSelectedBackground
                  : tokens.panelBorder,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    aiProviderLabel(providerType),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: tokens.primaryText,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected
                      ? tokens.segmentedSelectedBackground
                      : tokens.secondaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
