import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/sync/official_sync_server_resolver.dart';
import 'package:petnote/sync/pairing_flow.dart';

class PetPairingPage extends StatefulWidget {
  PetPairingPage({
    super.key,
    required this.settingsController,
    PairingFlow? pairingFlow,
    OfficialSyncServerResolver? officialServerResolver,
  })  : _pairingFlow = pairingFlow,
        officialServerResolver =
            officialServerResolver ?? OfficialSyncServerResolver();

  final AppSettingsController settingsController;
  final PairingFlow? _pairingFlow;
  final OfficialSyncServerResolver officialServerResolver;

  @override
  State<PetPairingPage> createState() => _PetPairingPageState();
}

class _PetPairingPageState extends State<PetPairingPage> {
  late final TextEditingController _serverController;
  late final TextEditingController _codeController;
  late final TextEditingController _deviceNameController;
  late SyncServerMode _serverMode;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _serverMode = widget.settingsController.syncServerMode;
    _serverController = TextEditingController(
      text: widget.settingsController.syncServerUrl ?? '',
    );
    _codeController = TextEditingController();
    _deviceNameController = TextEditingController(text: '客厅的小屏幕');
  }

  @override
  void dispose() {
    _serverController.dispose();
    _codeController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Scaffold(
      body: HyperPageBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            children: [
              const PageHeader(
                title: '配对宠物端',
                subtitle: '输入主人设备上的配对码',
              ),
              SectionCard(
                title: '配对',
                children: [
                  HyperSegmentedControl(
                    key: const ValueKey('pairing_server_mode_control'),
                    items: const [
                      SegmentItem(
                        key: 'official',
                        label: '官方服务器',
                      ),
                      SegmentItem(
                        key: 'custom',
                        label: '自定义',
                      ),
                    ],
                    selectedKey: _serverMode.name,
                    onChanged: _setServerModeByKey,
                  ),
                  if (_serverMode == SyncServerMode.custom)
                    TextField(
                      key: const ValueKey('pairing_server_field'),
                      controller: _serverController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: '服务器地址'),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('pairing_code_field'),
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: tokens.primaryText,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 8,
                        ),
                    decoration: const InputDecoration(
                      labelText: '配对码',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _deviceNameController,
                    decoration: const InputDecoration(labelText: '设备名'),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('pairing_submit_button'),
                      onPressed: _loading ? null : _submit,
                      child: Text(_loading ? '配对中' : '开始配对'),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => widget.settingsController
                        .setDeviceRole(DeviceRole.owner),
                child: const Text('切回主人模式'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setServerModeByKey(String key) async {
    final value =
        key == 'custom' ? SyncServerMode.custom : SyncServerMode.official;
    setState(() => _serverMode = value);
    await widget.settingsController.setSyncServerMode(value);
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final serverUrl = await _resolveServerUrl();
      final flow = widget._pairingFlow ??
          PairingFlow(settingsController: widget.settingsController);
      await flow.joinAsPet(
        serverUrl: serverUrl,
        code: _codeController.text,
        deviceName: _deviceNameController.text,
      );
    } on PairingException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on OfficialSyncServerException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<String> _resolveServerUrl() async {
    if (_serverMode == SyncServerMode.custom) {
      await widget.settingsController.setSyncServerMode(SyncServerMode.custom);
      await widget.settingsController.setSyncServerUrl(
        normalizeSyncServerUrl(_serverController.text),
      );
      final serverUrl = widget.settingsController.syncServerUrl;
      if (serverUrl == null || serverUrl.isEmpty) {
        throw const PairingException('请输入服务器地址');
      }
      return serverUrl;
    }
    await widget.settingsController.setSyncServerMode(SyncServerMode.official);
    final serverUrl = await widget.officialServerResolver.resolve();
    await widget.settingsController.setSyncServerUrl(serverUrl);
    _serverController.text = serverUrl;
    return serverUrl;
  }
}
