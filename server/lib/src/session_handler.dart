import 'dart:async';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'household_store.dart';
import 'server_app.dart';

/// 每条 WebSocket 连接一个会话。hello/pair 之后才进入已认证状态。
class SessionHandler {
  SessionHandler({required this.app, required this.channel});

  final SyncServerApp app;
  final WebSocketChannel channel;

  String? householdId;
  String? deviceId;

  void bind() {
    channel.stream.listen(_onData, onDone: _onDone, onError: (_) => _onDone());
  }

  void _onData(dynamic raw) {
    if (raw is! String) {
      _send(
          SyncMessage(SyncMessageTypes.pairError, {'message': 'bad message'}));
      return;
    }
    final SyncMessage message;
    try {
      message = SyncMessage.decode(raw);
    } on FormatException {
      _send(
          SyncMessage(SyncMessageTypes.pairError, {'message': 'bad message'}));
      return;
    }
    handle(message);
  }

  void handle(SyncMessage message) {
    switch (message.type) {
      case SyncMessageTypes.pairCreate:
        _handlePairCreate(message);
      case SyncMessageTypes.pairJoin:
        _handlePairJoin(message);
      case SyncMessageTypes.hello:
        _handleHello(message);
      case SyncMessageTypes.snapshotPush:
        _handleSnapshotPush(message);
      case SyncMessageTypes.snapshotRequest:
        _sendSnapshotIfAny();
      case SyncMessageTypes.actionPush:
        _handleActionPush(message);
      case SyncMessageTypes.actionAck:
        _handleActionAck(message);
      case SyncMessageTypes.devicesRequest:
        _sendDevices();
      case SyncMessageTypes.deviceUpdate:
        _handleDeviceUpdate(message);
      case SyncMessageTypes.deviceRemove:
        _handleDeviceRemove(message);
      case SyncMessageTypes.callInvite:
      case SyncMessageTypes.callAnswer:
      case SyncMessageTypes.callReject:
      case SyncMessageTypes.callEnd:
      case SyncMessageTypes.iceCandidate:
        _relayToTarget(message);
      default:
        _send(SyncMessage(
            SyncMessageTypes.pairError, {'message': 'unsupported'}));
    }
  }

  void _handlePairCreate(SyncMessage message) {
    final requestedDeviceId = _requiredString(message, 'deviceId');
    if (requestedDeviceId == null) return;
    final requestedHouseholdId =
        _optionalString(message.payload['householdId']);
    final existingHousehold = app.store.household(requestedHouseholdId);
    if (requestedHouseholdId != null) {
      final currentDevice = _currentDevice;
      final requestedAuthToken = _optionalString(message.payload['authToken']);
      final isAuthenticatedOwner = householdId == requestedHouseholdId &&
          deviceId == requestedDeviceId &&
          currentDevice?.role == 'owner';
      final hasValidToken = existingHousehold != null &&
          existingHousehold.authToken == requestedAuthToken &&
          existingHousehold.devices[requestedDeviceId]?.role == 'owner';
      if (!isAuthenticatedOwner && !hasValidToken) {
        _send(
            SyncMessage(SyncMessageTypes.pairError, {'message': 'forbidden'}));
        return;
      }
    }
    if (requestedHouseholdId != null && existingHousehold == null) {
      _send(SyncMessage(SyncMessageTypes.pairError, {'message': 'forbidden'}));
      return;
    }
    final ticket = app.pairing.createCode(
      existingHouseholdId: requestedHouseholdId,
      ownerDeviceId: requestedDeviceId,
      ownerDeviceName: _optionalString(message.payload['deviceName']) ?? '主人设备',
    );
    householdId = ticket.householdId;
    deviceId = requestedDeviceId;
    final household = _household;
    final device = household?.devices[requestedDeviceId];
    if (device != null) {
      device
        ..name = _optionalString(message.payload['deviceName']) ?? device.name
        ..lastSeenMs = DateTime.now().millisecondsSinceEpoch;
    }
    app.hub.register(householdId!, deviceId!, channel);
    _send(SyncMessage(SyncMessageTypes.pairCreated, {
      'code': ticket.code,
      'saltBase64': ticket.saltBase64,
      'authToken': ticket.authToken,
      'expiresAtMs': ticket.expiresAt.millisecondsSinceEpoch,
      'householdId': ticket.householdId,
      'hasPetDevice':
          household?.devices.values.any((device) => device.role == 'pet') ??
              false,
    }));
    unawaited(app.store.flush());
  }

  void _handlePairJoin(SyncMessage message) {
    final requestedDeviceId = _requiredString(message, 'deviceId');
    if (requestedDeviceId == null) return;
    final result = app.pairing.redeem(
      code: _optionalString(message.payload['code']) ?? '',
      petDeviceId: requestedDeviceId,
      petDeviceName: _optionalString(message.payload['deviceName']) ?? '宠物端设备',
    );
    if (result == null) {
      _send(SyncMessage(SyncMessageTypes.pairError, {'message': '配对码无效或已过期'}));
      return;
    }
    householdId = result.householdId;
    deviceId = requestedDeviceId;
    final household = _household;
    final device = household?.devices[requestedDeviceId];
    if (device != null) {
      device
        ..name = _optionalString(message.payload['deviceName']) ?? device.name
        ..lastSeenMs = DateTime.now().millisecondsSinceEpoch;
    }
    app.hub.register(householdId!, deviceId!, channel);
    _send(SyncMessage(SyncMessageTypes.pairJoined, {
      'householdId': result.householdId,
      'saltBase64': result.saltBase64,
      'authToken': result.authToken,
    }));
    for (final owner in household?.devices.values
            .where((device) => device.role == 'owner') ??
        const Iterable<HouseholdDevice>.empty()) {
      app.hub.sendTo(
        householdId!,
        owner.deviceId,
        SyncMessage(SyncMessageTypes.pairPeerJoined, {
          'deviceId': requestedDeviceId,
          'deviceName': message.payload['deviceName'],
        }).encode(),
      );
    }
    unawaited(app.store.flush());
  }

  void _handleHello(SyncMessage message) {
    if (householdId != null) {
      _send(SyncMessage(
          SyncMessageTypes.pairError, {'message': 'already registered'}));
      return;
    }
    final requestedDeviceId = message.payload['deviceId'];
    if (requestedDeviceId is! String || requestedDeviceId.isEmpty) {
      _send(
          SyncMessage(SyncMessageTypes.pairError, {'message': 'bad message'}));
      return;
    }
    final rawHouseholdId = message.payload['householdId'];
    final household =
        app.store.household(rawHouseholdId is String ? rawHouseholdId : null);
    if (household == null) {
      _send(SyncMessage(
          SyncMessageTypes.pairError, {'message': 'unknown household'}));
      return;
    }
    final device = household.devices[requestedDeviceId];
    if (device == null) {
      _send(SyncMessage(
          SyncMessageTypes.pairError, {'message': 'unknown device'}));
      return;
    }
    final requestedRole = _optionalString(message.payload['role']);
    if (requestedRole != null && requestedRole != device.role) {
      _send(SyncMessage(
          SyncMessageTypes.pairError, {'message': 'role mismatch'}));
      return;
    }
    if (_optionalString(message.payload['authToken']) != household.authToken) {
      _send(
          SyncMessage(SyncMessageTypes.pairError, {'message': 'auth failed'}));
      return;
    }
    householdId = household.id;
    deviceId = requestedDeviceId;
    device
      ..name = _optionalString(message.payload['deviceName']) ?? device.name
      ..lastSeenMs = DateTime.now().millisecondsSinceEpoch;
    app.hub.register(householdId!, deviceId!, channel);
    _send(SyncMessage(SyncMessageTypes.helloAck,
        {'snapshotVersion': household.snapshotVersion}));
    if (device.role == 'owner') {
      for (final action in household.pendingActions) {
        _send(SyncMessage(
            SyncMessageTypes.action, Map<String, dynamic>.from(action)));
      }
    }
    unawaited(app.store.flush());
  }

  Household? get _household => app.store.household(householdId);

  void _handleSnapshotPush(SyncMessage message) {
    final household = _registeredHousehold();
    if (household == null) return;
    if (!_requireRole('owner')) return;
    final version = message.payload['version'];
    final ciphertext = message.payload['ciphertext'];
    if (version is! int || ciphertext is! String || ciphertext.isEmpty) {
      _send(
          SyncMessage(SyncMessageTypes.pairError, {'message': 'bad message'}));
      return;
    }
    household
      ..snapshotVersion = version
      ..snapshotCiphertext = ciphertext;
    for (final device
        in household.devices.values.where((device) => device.role == 'pet')) {
      app.hub.sendTo(
        householdId!,
        device.deviceId,
        SyncMessage(SyncMessageTypes.snapshot, message.payload).encode(),
      );
    }
    unawaited(app.store.flush());
  }

  void _sendSnapshotIfAny() {
    final household = _registeredHousehold();
    if (household == null || household.snapshotCiphertext == null) return;
    if (!_requireRole('pet')) return;
    _send(SyncMessage(SyncMessageTypes.snapshot, {
      'version': household.snapshotVersion,
      'ciphertext': household.snapshotCiphertext,
    }));
  }

  void _handleActionPush(SyncMessage message) {
    final household = _registeredHousehold();
    if (household == null) return;
    if (!_requireRole('pet')) return;
    final actionId = message.payload['actionId'];
    final ciphertext = message.payload['ciphertext'];
    if (actionId is! String ||
        actionId.isEmpty ||
        ciphertext is! String ||
        ciphertext.isEmpty) {
      _send(
          SyncMessage(SyncMessageTypes.pairError, {'message': 'bad message'}));
      return;
    }
    final entry = <String, dynamic>{
      'actionId': actionId,
      'ciphertext': ciphertext,
    };
    household.pendingActions.add(entry);
    for (final device
        in household.devices.values.where((device) => device.role == 'owner')) {
      if (app.hub.isOnline(householdId!, device.deviceId)) {
        app.hub.sendTo(
          householdId!,
          device.deviceId,
          SyncMessage(SyncMessageTypes.action, entry).encode(),
        );
      }
    }
    unawaited(app.store.flush());
  }

  void _handleActionAck(SyncMessage message) {
    final household = _registeredHousehold();
    if (household == null) return;
    if (!_requireRole('owner')) return;
    final actionId = _requiredString(message, 'actionId');
    if (actionId == null) return;
    household.pendingActions
        .removeWhere((action) => action['actionId'] == actionId);
    unawaited(app.store.flush());
  }

  void _sendDevices() {
    final household = _registeredHousehold();
    if (household == null) return;
    if (!_requireRole('owner')) return;
    _send(SyncMessage(SyncMessageTypes.devices, {
      'devices': household.devices.values
          .map((device) => SyncedDeviceInfo(
                deviceId: device.deviceId,
                name: device.name,
                role: device.role,
                servedPetId: device.servedPetId,
                online: app.hub.isOnline(householdId!, device.deviceId),
                lastSeenMs: device.lastSeenMs,
              ).toJson())
          .toList(),
    }));
  }

  void _handleDeviceUpdate(SyncMessage message) {
    final household = _registeredHousehold();
    if (household == null) return;
    if (!_requireRole('owner')) return;
    final requestedDeviceId = _requiredString(message, 'deviceId');
    if (requestedDeviceId == null) return;
    final device = household.devices[requestedDeviceId];
    if (device == null) {
      _send(SyncMessage(
          SyncMessageTypes.pairError, {'message': 'unknown device'}));
      return;
    }
    final name = _optionalString(message.payload['name']);
    if (name != null && name.isNotEmpty) {
      device.name = name;
    }
    if (message.payload.containsKey('servedPetId')) {
      final servedPetId = message.payload['servedPetId'];
      if (servedPetId != null && servedPetId is! String) {
        _send(SyncMessage(
            SyncMessageTypes.pairError, {'message': 'bad message'}));
        return;
      }
      device.servedPetId = servedPetId as String?;
      app.hub.sendTo(
        householdId!,
        device.deviceId,
        SyncMessage(SyncMessageTypes.deviceConfig,
            {'servedPetId': device.servedPetId}).encode(),
      );
    }
    unawaited(app.store.flush());
    _sendDevices();
  }

  void _handleDeviceRemove(SyncMessage message) {
    final household = _registeredHousehold();
    if (household == null) return;
    if (!_requireRole('owner')) return;
    final removedDeviceId = _requiredString(message, 'deviceId');
    if (removedDeviceId == null) return;
    household.devices.remove(removedDeviceId);
    app.hub.sendTo(
      householdId!,
      removedDeviceId,
      SyncMessage(SyncMessageTypes.deviceConfig, {'removed': true}).encode(),
    );
    unawaited(app.store.flush());
    _sendDevices();
  }

  void _relayToTarget(SyncMessage message) {
    final household = _registeredHousehold();
    if (household == null) return;
    final target = _optionalString(message.payload['targetDeviceId']);
    if (target == null || !household.devices.containsKey(target)) {
      _send(SyncMessage(
          SyncMessageTypes.pairError, {'message': 'unknown device'}));
      return;
    }
    app.hub.sendTo(householdId!, target, message.encode());
  }

  Household? _registeredHousehold() {
    final household = _household;
    if (household == null) {
      _send(SyncMessage(
          SyncMessageTypes.pairError, {'message': 'not registered'}));
      return null;
    }
    return household;
  }

  HouseholdDevice? get _currentDevice => _household?.devices[deviceId];

  bool _requireRole(String role) {
    if (_currentDevice?.role == role) {
      return true;
    }
    _send(SyncMessage(SyncMessageTypes.pairError, {'message': 'forbidden'}));
    return false;
  }

  String? _requiredString(SyncMessage message, String key) {
    final value = message.payload[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    _send(SyncMessage(SyncMessageTypes.pairError, {'message': 'bad message'}));
    return null;
  }

  String? _optionalString(Object? value) => value is String ? value : null;

  void _onDone() {
    if (householdId != null && deviceId != null) {
      app.hub.unregister(householdId!, deviceId!, channel);
    }
  }

  void _send(SyncMessage message) => channel.sink.add(message.encode());
}
