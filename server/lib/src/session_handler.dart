import 'dart:async';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'household_store.dart';
import 'pairing_service.dart';
import 'server_app.dart';

/// 每条 WebSocket 连接一个会话。hello/pair 之后才进入已认证状态。
class SessionHandler {
  SessionHandler({required this.app, required this.channel});

  final SyncServerApp app;
  final WebSocketChannel channel;

  String? householdId;
  String? deviceId;
  String? _sessionRole;
  String? _issuedPairingCode;

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
        _sendSnapshotIfAny(message);
      case SyncMessageTypes.actionPush:
        _handleActionPush(message);
      case SyncMessageTypes.actionAck:
        _handleActionAck(message);
      case SyncMessageTypes.syncReceived:
        _handleSyncReceived(message);
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
      final isAuthenticatedDevice = householdId == requestedHouseholdId &&
          deviceId == requestedDeviceId &&
          currentDevice != null;
      final hasValidToken = existingHousehold != null &&
          existingHousehold.authToken == requestedAuthToken &&
          existingHousehold.devices.containsKey(requestedDeviceId);
      if (!isAuthenticatedDevice && !hasValidToken) {
        _send(
            SyncMessage(SyncMessageTypes.pairError, {'message': 'forbidden'}));
        return;
      }
    }
    if (requestedHouseholdId != null && existingHousehold == null) {
      _send(SyncMessage(SyncMessageTypes.pairError, {'message': 'forbidden'}));
      return;
    }
    late final PairingCodeTicket ticket;
    try {
      ticket = app.pairing.createCode(
        existingHouseholdId: requestedHouseholdId,
        issuerDeviceId: requestedDeviceId,
        issuerDeviceName:
            _optionalString(message.payload['deviceName']) ?? '设备',
        issuerRole: _normalizedRole(_optionalString(message.payload['role'])) ??
            'owner',
      );
    } on StateError {
      _send(SyncMessage(
        SyncMessageTypes.pairError,
        {'message': '服务繁忙，请稍后再试'},
      ));
      return;
    }
    householdId = ticket.householdId;
    deviceId = requestedDeviceId;
    _issuedPairingCode = ticket.code;
    final household = _household;
    final device = household?.devices[requestedDeviceId];
    if (device != null) {
      device
        ..name = _optionalString(message.payload['deviceName']) ?? device.name
        ..lastSeenMs = DateTime.now().millisecondsSinceEpoch;
    }
    _sessionRole =
        _normalizedRole(_optionalString(message.payload['role'])) ?? 'owner';
    app.hub.register(householdId!, deviceId!, channel, role: _sessionRole);
    _send(SyncMessage(SyncMessageTypes.pairCreated, {
      'code': ticket.code,
      'saltBase64': ticket.saltBase64,
      'authToken': ticket.authToken,
      'expiresAtMs': ticket.expiresAt.millisecondsSinceEpoch,
      'householdId': ticket.householdId,
      'hasPetDevice': household?.devices.keys.any(
            (deviceId) => deviceId != requestedDeviceId,
          ) ??
          false,
    }));
    unawaited(app.store.flush());
  }

  void _handlePairJoin(SyncMessage message) {
    final requestedDeviceId = _requiredString(message, 'deviceId');
    if (requestedDeviceId == null) return;
    final result = app.pairing.redeem(
      code: _optionalString(message.payload['code']) ?? '',
      joiningDeviceId: requestedDeviceId,
      joiningDeviceName: _optionalString(message.payload['deviceName']) ?? '设备',
      joiningRole:
          _normalizedRole(_optionalString(message.payload['role'])) ?? 'pet',
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
    _sessionRole =
        _normalizedRole(_optionalString(message.payload['role'])) ?? 'pet';
    app.hub.register(householdId!, deviceId!, channel, role: _sessionRole);
    _send(SyncMessage(SyncMessageTypes.pairJoined, {
      'householdId': result.householdId,
      'saltBase64': result.saltBase64,
      'authToken': result.authToken,
    }));
    for (final device in household?.devices.values ??
        const Iterable<HouseholdDevice>.empty()) {
      if (device.deviceId == requestedDeviceId) {
        continue;
      }
      app.hub.sendTo(
        householdId!,
        device.deviceId,
        SyncMessage(SyncMessageTypes.pairPeerJoined, {
          'deviceId': requestedDeviceId,
          'deviceName': message.payload['deviceName'],
          'dataPolicy': _normalizedDataPolicy(
                  _optionalString(message.payload['dataPolicy']))
              .name,
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
    final requestedRole =
        _normalizedRole(_optionalString(message.payload['role']));
    if (requestedRole == null) {
      _send(
          SyncMessage(SyncMessageTypes.pairError, {'message': 'bad message'}));
      return;
    }
    if (_optionalString(message.payload['authToken']) != household.authToken) {
      _send(
          SyncMessage(SyncMessageTypes.pairError, {'message': 'auth failed'}));
      return;
    }
    householdId = household.id;
    deviceId = requestedDeviceId;
    _sessionRole = requestedRole;
    device
      ..name = _optionalString(message.payload['deviceName']) ?? device.name
      ..lastSeenMs = DateTime.now().millisecondsSinceEpoch;
    app.hub.register(householdId!, deviceId!, channel, role: _sessionRole);
    _send(const SyncMessage(SyncMessageTypes.helloAck, {'snapshotVersion': 0}));
    unawaited(app.store.flush());
  }

  Household? get _household => app.store.household(householdId);

  void _handleSnapshotPush(SyncMessage message) {
    final household = _registeredHousehold();
    if (household == null) return;
    final version = message.payload['version'];
    final ciphertext = message.payload['ciphertext'];
    if (version is! int || ciphertext is! String || ciphertext.isEmpty) {
      _send(
          SyncMessage(SyncMessageTypes.pairError, {'message': 'bad message'}));
      return;
    }
    final completedItemKeys = _stringSet(message.payload['completedItemKeys']);
    final missingCompletedKeys =
        household.completedItemKeys.difference(completedItemKeys);
    if (missingCompletedKeys.isNotEmpty) {
      _sendMissingSyncEvents(household);
      _sendMissingCompletedActions(household, missingCompletedKeys);
      return;
    }
    household.completedItemKeys.addAll(completedItemKeys);
    _broadcastToOtherDevices(
      household,
      SyncMessage(
        SyncMessageTypes.snapshot,
        _registerSyncEvent(
          household,
          messageType: SyncMessageTypes.snapshot,
          payload: Map<String, dynamic>.from(message.payload),
        ).payload,
      ),
    );
    unawaited(app.store.flush());
  }

  void _sendSnapshotIfAny(SyncMessage message) {
    final household = _registeredHousehold();
    if (household == null) return;
    _sendMissingSyncEvents(household);
    _broadcastToOtherDevices(
      household,
      SyncMessage(
        SyncMessageTypes.snapshotRequest,
        Map<String, dynamic>.from(message.payload),
      ),
    );
  }

  void _handleActionPush(SyncMessage message) {
    final household = _registeredHousehold();
    if (household == null) return;
    final actionId = message.payload['actionId'];
    final ciphertext = message.payload['ciphertext'];
    final sourceType = _optionalString(message.payload['sourceType']);
    final itemId = _optionalString(message.payload['itemId']);
    final kind = _optionalString(message.payload['kind']);
    if (actionId is! String ||
        actionId.isEmpty ||
        ciphertext is! String ||
        ciphertext.isEmpty ||
        sourceType == null ||
        itemId == null ||
        kind == null) {
      _send(
          SyncMessage(SyncMessageTypes.pairError, {'message': 'bad message'}));
      return;
    }
    final itemKey = '$sourceType:$itemId';
    final completedAction = household.completedActions[itemKey];
    if (completedAction != null && kind != PetActionKind.markDone.name) {
      _send(SyncMessage(SyncMessageTypes.action, completedAction));
      return;
    }
    final outgoingPayload = <String, dynamic>{
      'actionId': actionId,
      'ciphertext': ciphertext,
      'kind': kind,
      'sourceType': sourceType,
      'itemId': itemId,
    };
    if (kind == PetActionKind.markDone.name) {
      final event = _registerSyncEvent(
        household,
        messageType: SyncMessageTypes.action,
        payload: outgoingPayload,
      );
      household.completedItemKeys.add(itemKey);
      household.completedActions[itemKey] = event.payload;
      _broadcastToOtherDevices(
        household,
        SyncMessage(SyncMessageTypes.action, event.payload),
      );
      unawaited(app.store.flush());
      return;
    }
    final event = _registerSyncEvent(
      household,
      messageType: SyncMessageTypes.action,
      payload: outgoingPayload,
    );
    _broadcastToOtherDevices(
      household,
      SyncMessage(SyncMessageTypes.action, event.payload),
    );
    unawaited(app.store.flush());
  }

  void _handleActionAck(SyncMessage message) {
    final household = _registeredHousehold();
    if (household == null) return;
    final actionId = _requiredString(message, 'actionId');
    if (actionId == null) return;
  }

  void _handleSyncReceived(SyncMessage message) {
    final household = _registeredHousehold();
    if (household == null) return;
    final syncId = _requiredString(message, 'syncId');
    if (syncId == null) return;
    final event = household.syncEvents[syncId];
    if (event == null) {
      return;
    }
    if (deviceId != event.originDeviceId) {
      event.receivedByDeviceIds.add(deviceId!);
    }
    final originDeviceId = _optionalString(message.payload['originDeviceId']) ??
        event.originDeviceId;
    if (originDeviceId.isNotEmpty && originDeviceId != deviceId) {
      final receiptPayload = _syncReceivedPayload(
        event,
        syncId: syncId,
        receivedDeviceId: deviceId!,
      );
      app.hub.sendTo(
        householdId!,
        originDeviceId,
        SyncMessage(SyncMessageTypes.syncReceived, receiptPayload).encode(),
      );
    }
    _pruneReceivedSyncEvents(household);
    unawaited(app.store.flush());
  }

  Map<String, dynamic> _syncReceivedPayload(
    SyncEventReceipt event, {
    required String syncId,
    required String receivedDeviceId,
  }) {
    final payload = <String, dynamic>{
      'syncId': syncId,
      'originDeviceId': event.originDeviceId,
      'receivedDeviceId': receivedDeviceId,
    };
    for (final key in <String>[
      'actionId',
      'kind',
      'sourceType',
      'itemId',
      'version',
      'dataPolicy',
    ]) {
      final value = event.payload[key];
      if (value != null) {
        payload[key] = value;
      }
    }
    return payload;
  }

  void _sendDevices() {
    final household = _registeredHousehold();
    if (household == null) return;
    _send(SyncMessage(SyncMessageTypes.devices, {
      'devices': household.devices.values
          .where((device) => device.deviceId != deviceId)
          .map((device) => SyncedDeviceInfo(
                deviceId: device.deviceId,
                name: device.name,
                role:
                    app.hub.roleFor(householdId!, device.deviceId) ?? 'unknown',
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
    if (removedDeviceId == deviceId) {
      _send(SyncMessage(SyncMessageTypes.pairError, {'message': 'forbidden'}));
      return;
    }
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

  void _broadcastToOtherDevices(Household household, SyncMessage message) {
    for (final device in household.devices.values) {
      if (device.deviceId == deviceId) {
        continue;
      }
      app.hub.sendTo(householdId!, device.deviceId, message.encode());
    }
  }

  SyncEventReceipt _registerSyncEvent(
    Household household, {
    required String messageType,
    required Map<String, dynamic> payload,
  }) {
    final syncId = _optionalString(payload['syncId']) ??
        '${DateTime.now().toUtc().microsecondsSinceEpoch}-${deviceId ?? 'unknown'}';
    final originDeviceId = deviceId ?? '';
    final eventPayload = Map<String, dynamic>.from(payload)
      ..['syncId'] = syncId
      ..['originDeviceId'] = originDeviceId;
    final event = SyncEventReceipt(
      syncId: syncId,
      originDeviceId: originDeviceId,
      messageType: messageType,
      payload: eventPayload,
    );
    household.syncEvents[syncId] = event;
    return event;
  }

  void _sendMissingSyncEvents(Household household) {
    final currentDeviceId = deviceId;
    if (currentDeviceId == null) {
      return;
    }
    final missingCompletedKeys = <String>{};
    var receiptChanged = false;
    for (final event in household.syncEvents.values) {
      if (event.originDeviceId == currentDeviceId) {
        continue;
      }
      if (event.receivedByDeviceIds.contains(currentDeviceId)) {
        continue;
      }
      if (_isObsoleteCompletedAction(household, event.payload)) {
        event.receivedByDeviceIds.add(currentDeviceId);
        receiptChanged = true;
        continue;
      }
      if (event.messageType == SyncMessageTypes.snapshot) {
        final completedKeys = _stringSet(event.payload['completedItemKeys']);
        final missingKeys =
            household.completedItemKeys.difference(completedKeys);
        if (missingKeys.isNotEmpty) {
          event.receivedByDeviceIds.add(currentDeviceId);
          receiptChanged = true;
          missingCompletedKeys.addAll(missingKeys);
          continue;
        }
      }
      _send(SyncMessage(event.messageType, event.payload));
    }
    if (missingCompletedKeys.isNotEmpty) {
      _sendMissingCompletedActions(household, missingCompletedKeys);
    }
    if (receiptChanged) {
      _pruneReceivedSyncEvents(household);
      unawaited(app.store.flush());
    }
  }

  void _sendMissingCompletedActions(
    Household household,
    Set<String> itemKeys,
  ) {
    for (final itemKey in itemKeys) {
      final action = household.completedActions[itemKey];
      if (action == null) {
        continue;
      }
      _send(SyncMessage(SyncMessageTypes.action, action));
    }
  }

  bool _isObsoleteCompletedAction(
    Household household,
    Map<String, dynamic> payload,
  ) {
    final sourceType = _optionalString(payload['sourceType']);
    final itemId = _optionalString(payload['itemId']);
    final kind = _optionalString(payload['kind']);
    if (sourceType == null || itemId == null || kind == null) {
      return false;
    }
    return household.completedActions.containsKey('$sourceType:$itemId') &&
        kind != PetActionKind.markDone.name;
  }

  void _pruneReceivedSyncEvents(Household household) {
    final deviceIds = household.devices.keys.toSet();
    household.syncEvents.removeWhere((_, event) {
      final receiptTargets = {...deviceIds}..remove(event.originDeviceId);
      return receiptTargets.difference(event.receivedByDeviceIds).isEmpty;
    });
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
    if (_sessionRole == role) {
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

  Set<String> _stringSet(Object? value) {
    if (value is! List) {
      return const <String>{};
    }
    return value.whereType<String>().toSet();
  }

  String? _normalizedRole(String? role) {
    if (role == 'owner' || role == 'pet') {
      return role;
    }
    return null;
  }

  SyncDataPolicy _normalizedDataPolicy(String? value) {
    return SyncDataPolicy.values.firstWhere(
      (policy) => policy.name == value,
      orElse: () => SyncDataPolicy.merge,
    );
  }

  void _onDone() {
    final issuedPairingCode = _issuedPairingCode;
    if (issuedPairingCode != null) {
      app.pairing.releaseCode(issuedPairingCode);
      _issuedPairingCode = null;
    }
    if (householdId != null && deviceId != null) {
      app.hub.unregister(householdId!, deviceId!, channel);
    }
  }

  void _send(SyncMessage message) => channel.sink.add(message.encode());
}
