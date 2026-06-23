import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  Future<void> _messageQueue = Future<void>.value();

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
    _messageQueue =
        _messageQueue.catchError((Object _) {}).then((_) => handle(message));
    unawaited(_messageQueue.catchError((_) {}));
  }

  Future<void> handle(SyncMessage message) async {
    switch (message.type) {
      case SyncMessageTypes.pairCreate:
        _handlePairCreate(message);
      case SyncMessageTypes.pairJoin:
        _handlePairJoin(message);
      case SyncMessageTypes.hello:
        _handleHello(message);
      case SyncMessageTypes.snapshotPush:
        await _handleSnapshotPush(message);
      case SyncMessageTypes.snapshotRequest:
        _sendSnapshotIfAny(message);
      case SyncMessageTypes.actionPush:
        await _handleActionPush(message);
      case SyncMessageTypes.mutationPush:
        await _handleMutationPush(message);
      case SyncMessageTypes.actionAck:
        _handleActionAck(message);
      case SyncMessageTypes.syncReceived:
        await _handleSyncReceived(message);
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
      case SyncMessageTypes.callMediaState:
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
    final requestedAuthToken = _optionalString(message.payload['authToken']);
    final requestedSharedKeyBase64 =
        _optionalString(message.payload['sharedKeyBase64']);
    final requestedDeviceName =
        _optionalString(message.payload['deviceName']) ?? '设备';
    final requestedRole =
        _normalizedRole(_optionalString(message.payload['role'])) ?? 'owner';
    if (requestedHouseholdId != null) {
      final currentDevice = _currentDevice;
      final isAuthenticatedDevice = householdId == requestedHouseholdId &&
          deviceId == requestedDeviceId &&
          currentDevice != null;
      final isLegacyRegisteredDevice = existingHousehold != null &&
          !message.payload.containsKey('authToken') &&
          existingHousehold.devices.containsKey(requestedDeviceId);
      final hasValidToken = existingHousehold != null &&
          existingHousehold.authToken == requestedAuthToken &&
          existingHousehold.devices.containsKey(requestedDeviceId);
      final isAuthenticatedServerRestore =
          existingHousehold == null && requestedAuthToken != null;
      if (!isAuthenticatedDevice &&
          !hasValidToken &&
          !isLegacyRegisteredDevice &&
          !isAuthenticatedServerRestore) {
        _send(
            SyncMessage(SyncMessageTypes.pairError, {'message': 'forbidden'}));
        return;
      }
    }
    if (requestedHouseholdId != null &&
        existingHousehold == null &&
        requestedAuthToken == null) {
      _send(SyncMessage(SyncMessageTypes.pairError, {'message': 'forbidden'}));
      return;
    }
    late final PairingCodeTicket ticket;
    try {
      ticket = app.pairing.createCode(
        existingHouseholdId: requestedHouseholdId,
        existingAuthToken: requestedAuthToken,
        existingSharedKeyBase64: requestedSharedKeyBase64,
        issuerDeviceId: requestedDeviceId,
        issuerDeviceName: requestedDeviceName,
        issuerRole: requestedRole,
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
        ..name = requestedDeviceName
        ..role = requestedRole
        ..lastSeenMs = DateTime.now().millisecondsSinceEpoch;
    }
    _sessionRole = requestedRole;
    app.hub.register(householdId!, deviceId!, channel, role: _sessionRole);
    _send(SyncMessage(SyncMessageTypes.pairCreated, {
      'code': ticket.code,
      'saltBase64': ticket.saltBase64,
      'authToken': ticket.authToken,
      'expiresAtMs': ticket.expiresAt.millisecondsSinceEpoch,
      'householdId': ticket.householdId,
      if (requestedHouseholdId != null && existingHousehold == null)
        'restoredHousehold': true,
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
    _sessionRole =
        _normalizedRole(_optionalString(message.payload['role'])) ?? 'pet';
    final household = _household;
    final device = household?.devices[requestedDeviceId];
    if (device != null) {
      device
        ..name = _optionalString(message.payload['deviceName']) ?? device.name
        ..role = _sessionRole
        ..lastSeenMs = DateTime.now().millisecondsSinceEpoch;
    }
    app.hub.register(householdId!, deviceId!, channel, role: _sessionRole);
    _send(SyncMessage(SyncMessageTypes.pairJoined, {
      'householdId': result.householdId,
      'saltBase64': result.saltBase64,
      'authToken': result.authToken,
      if (result.sharedKeyBase64 != null)
        'sharedKeyBase64': result.sharedKeyBase64,
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
    final requestedRole =
        _normalizedRole(_optionalString(message.payload['role']));
    if (requestedRole == null) {
      _send(
          SyncMessage(SyncMessageTypes.pairError, {'message': 'bad message'}));
      return;
    }
    final household =
        app.store.household(rawHouseholdId is String ? rawHouseholdId : null);
    if (household == null) {
      final requestedAuthToken = _optionalString(message.payload['authToken']);
      final requestedDeviceName =
          _optionalString(message.payload['deviceName']) ?? '设备';
      if (rawHouseholdId is String &&
          requestedAuthToken != null &&
          requestedAuthToken.isNotEmpty) {
        final restoredHousehold = app.store.adoptExisting(
          rawHouseholdId,
          SyncCrypto.generateSaltBase64(),
          requestedAuthToken,
        );
        final restoredDevice = restoredHousehold.devices.putIfAbsent(
          requestedDeviceId,
          () => HouseholdDevice(
            deviceId: requestedDeviceId,
            name: requestedDeviceName,
          ),
        );
        householdId = restoredHousehold.id;
        deviceId = requestedDeviceId;
        _sessionRole = requestedRole;
        restoredDevice
          ..name = requestedDeviceName
          ..role = requestedRole
          ..lastSeenMs = DateTime.now().millisecondsSinceEpoch
          ..lastPulledServerSeq =
              _optionalPositiveInt(message.payload['lastPulledServerSeq']) ??
                  restoredDevice.lastPulledServerSeq;
        _pruneReceivedSyncEvents(restoredHousehold);
        app.hub.register(householdId!, deviceId!, channel, role: _sessionRole);
        _send(SyncMessage(SyncMessageTypes.helloAck, {
          'snapshotVersion': 0,
          'restoredHousehold': true,
          'restoredDevice': true,
        }));
        unawaited(app.store.flush());
        return;
      }
      _send(SyncMessage(
          SyncMessageTypes.pairError, {'message': 'unknown household'}));
      return;
    }
    var device = household.devices[requestedDeviceId];
    final requestedAuthToken = _optionalString(message.payload['authToken']);
    final canRestoreDevice =
        requestedAuthToken != null && requestedAuthToken == household.authToken;
    var restoredDevice = false;
    if (device == null && canRestoreDevice) {
      restoredDevice = true;
      device = HouseholdDevice(
        deviceId: requestedDeviceId,
        name: _optionalString(message.payload['deviceName']) ?? '设备',
      );
      household.devices[requestedDeviceId] = device;
    }
    if (device == null) {
      _send(SyncMessage(
          SyncMessageTypes.pairError, {'message': 'unknown device'}));
      return;
    }
    final needsLegacyAuthTokenRestore =
        !message.payload.containsKey('authToken');
    if (requestedAuthToken != household.authToken &&
        !needsLegacyAuthTokenRestore) {
      _send(
          SyncMessage(SyncMessageTypes.pairError, {'message': 'auth failed'}));
      return;
    }
    householdId = household.id;
    deviceId = requestedDeviceId;
    _sessionRole = requestedRole;
    device
      ..name = _optionalString(message.payload['deviceName']) ?? device.name
      ..role = requestedRole
      ..lastSeenMs = DateTime.now().millisecondsSinceEpoch
      ..lastPulledServerSeq =
          _optionalPositiveInt(message.payload['lastPulledServerSeq']) ??
              device.lastPulledServerSeq;
    _pruneReceivedSyncEvents(household);
    app.hub.register(householdId!, deviceId!, channel, role: _sessionRole);
    _send(SyncMessage(SyncMessageTypes.helloAck, {
      'snapshotVersion': 0,
      if (needsLegacyAuthTokenRestore) 'authToken': household.authToken,
      if (restoredDevice) 'restoredDevice': true,
    }));
    unawaited(app.store.flush());
  }

  Household? get _household => app.store.household(householdId);

  Future<void> _handleSnapshotPush(SyncMessage message) async {
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
    final isAuthoritativeRemoteSnapshot =
        _normalizedDataPolicy(_optionalString(message.payload['dataPolicy'])) ==
            SyncDataPolicy.remoteWins;
    final missingCompletedKeys =
        household.completedItemKeys.difference(completedItemKeys);
    if (!isAuthoritativeRemoteSnapshot && missingCompletedKeys.isNotEmpty) {
      _sendMissingSyncEvents(household);
      _sendMissingCompletedActions(household, missingCompletedKeys);
      return;
    }
    if (isAuthoritativeRemoteSnapshot) {
      household.completedItemKeys
        ..clear()
        ..addAll(completedItemKeys);
      household.completedActions
          .removeWhere((itemKey, _) => !completedItemKeys.contains(itemKey));
      household.retainAppliedChecklistActionsForCompletedItems(
        completedItemKeys,
      );
    } else {
      household.completedItemKeys.addAll(completedItemKeys);
    }
    final event = _registerSyncEvent(
      household,
      messageType: SyncMessageTypes.snapshot,
      payload: Map<String, dynamic>.from(message.payload),
    );
    await app.store.flush();
    _send(SyncMessage(
      SyncMessageTypes.syncReceived,
      _syncReceivedPayload(
        event,
        syncId: event.syncId,
        receivedDeviceId: deviceId ?? '',
      ),
    ));
    _broadcastToOtherDevices(
      household,
      (_) => SyncMessage(SyncMessageTypes.snapshot, event.payload),
    );
  }

  void _sendSnapshotIfAny(SyncMessage message) {
    final household = _registeredHousehold();
    if (household == null) return;
    final afterServerSeq = _optionalInt(message.payload['afterServerSeq']);
    final maxEvents = _optionalInt(message.payload['maxEvents']);
    final batch = _sendMissingSyncEvents(
      household,
      afterServerSeq: afterServerSeq,
      maxEvents: maxEvents,
    );
    final isIncrementalReplay = afterServerSeq != null || maxEvents != null;
    if (isIncrementalReplay) {
      _send(SyncMessage(SyncMessageTypes.syncCheckpoint, {
        'afterServerSeq': afterServerSeq,
        'requestedMaxEvents': maxEvents,
        'sentEventCount': batch.sentEventCount,
        'remainingEventCount': batch.remainingEventCount,
        'hasMore': batch.remainingEventCount > 0,
        if (batch.fromServerSeq != null) 'fromServerSeq': batch.fromServerSeq,
        if (batch.toServerSeq != null) 'toServerSeq': batch.toServerSeq,
      }));
    }
    if (isIncrementalReplay) {
      return;
    }
    _broadcastToOtherDevices(
      household,
      (_) => SyncMessage(
        SyncMessageTypes.snapshotRequest,
        Map<String, dynamic>.from(message.payload),
      ),
    );
  }

  Future<void> _handleActionPush(SyncMessage message) async {
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
      _sendCompletedActionReceiptIfPossible(completedAction);
      return;
    }
    final outgoingPayload = <String, dynamic>{
      'actionId': actionId,
      'ciphertext': ciphertext,
      'kind': kind,
      'sourceType': sourceType,
      'itemId': itemId,
    };
    final occurredAtMs = (message.payload['occurredAtMs'] as num?)?.toInt();
    if (occurredAtMs != null) {
      outgoingPayload['occurredAtMs'] = occurredAtMs;
    }
    if (occurredAtMs != null &&
        household.isOlderChecklistAction(itemKey, outgoingPayload)) {
      final latestAction = household.latestAppliedChecklistActionForItem(
        itemKey,
      );
      if (latestAction != null) {
        _sendAppliedActionReceipt(latestAction);
        return;
      }
    }
    final existingAppliedAction = household.appliedChecklistAction(
      sourceType: sourceType,
      itemId: itemId,
      kind: kind,
    );
    if (existingAppliedAction != null) {
      _sendAppliedActionReceipt(existingAppliedAction);
      return;
    }
    final existingSyncId = household.actionSyncEventIds[actionId];
    if (existingSyncId != null) {
      final existingEvent = household.syncEvents[existingSyncId];
      final receiptPayload = existingEvent == null
          ? {
              'syncId': existingSyncId,
              'originDeviceId': deviceId ?? '',
              'actionId': actionId,
              'kind': kind,
              'sourceType': sourceType,
              'itemId': itemId,
            }
          : _syncReceivedPayload(
              existingEvent,
              syncId: existingSyncId,
              receivedDeviceId: deviceId ?? '',
            );
      await app.store.flush();
      _send(SyncMessage(
        SyncMessageTypes.syncReceived,
        receiptPayload,
      ));
      return;
    }
    if (kind == PetActionKind.markDone.name) {
      final event = _registerSyncEvent(
        household,
        messageType: SyncMessageTypes.action,
        payload: outgoingPayload,
      );
      household.actionSyncEventIds[actionId] = event.syncId;
      final actionKey = household.checklistActionKey(
        sourceType: sourceType,
        itemId: itemId,
        kind: kind,
      );
      household.removeAppliedChecklistActionsForItem(
        itemKey,
        exceptActionKey: actionKey,
      );
      household.rememberAppliedChecklistAction(event.payload);
      household.completedItemKeys.add(itemKey);
      household.completedActions[itemKey] = event.payload;
      await app.store.flush();
      _send(SyncMessage(
        SyncMessageTypes.syncReceived,
        _syncReceivedPayload(
          event,
          syncId: event.syncId,
          receivedDeviceId: deviceId ?? '',
        ),
      ));
      _broadcastToOtherDevices(
        household,
        (_) => SyncMessage(SyncMessageTypes.action, event.payload),
      );
      return;
    }
    final event = _registerSyncEvent(
      household,
      messageType: SyncMessageTypes.action,
      payload: outgoingPayload,
    );
    household.actionSyncEventIds[actionId] = event.syncId;
    household.completedItemKeys.add(itemKey);
    household.rememberAppliedChecklistAction(event.payload);
    await app.store.flush();
    _send(SyncMessage(
      SyncMessageTypes.syncReceived,
      _syncReceivedPayload(
        event,
        syncId: event.syncId,
        receivedDeviceId: deviceId ?? '',
      ),
    ));
    _broadcastToOtherDevices(
      household,
      (_) => SyncMessage(SyncMessageTypes.action, event.payload),
    );
  }

  Future<void> _handleMutationPush(SyncMessage message) async {
    final household = _registeredHousehold();
    if (household == null) return;
    final mutationId = message.payload['mutationId'];
    final ciphertext = message.payload['ciphertext'];
    final entityType = _optionalString(message.payload['entityType']);
    final entityId = _optionalString(message.payload['entityId']);
    final kind = _optionalString(message.payload['kind']);
    if (mutationId is! String ||
        mutationId.isEmpty ||
        ciphertext is! String ||
        ciphertext.isEmpty ||
        entityType == null ||
        entityId == null ||
        kind == null) {
      _send(
          SyncMessage(SyncMessageTypes.pairError, {'message': 'bad message'}));
      return;
    }
    final existingSyncId = household.mutationSyncEventIds[mutationId];
    if (existingSyncId != null) {
      final existingEvent = household.syncEvents[existingSyncId];
      final receiptPayload = existingEvent == null
          ? {
              'syncId': existingSyncId,
              'originDeviceId': deviceId ?? '',
              'mutationId': mutationId,
              'entityType': entityType,
              'entityId': entityId,
              'kind': kind,
            }
          : _syncReceivedPayload(
              existingEvent,
              syncId: existingSyncId,
              receivedDeviceId: deviceId ?? '',
            );
      await app.store.flush();
      _send(SyncMessage(
        SyncMessageTypes.syncReceived,
        receiptPayload,
      ));
      return;
    }
    final event = _registerSyncEvent(
      household,
      messageType: SyncMessageTypes.mutation,
      payload: {
        'mutationId': mutationId,
        'ciphertext': ciphertext,
        'entityType': entityType,
        'entityId': entityId,
        'kind': kind,
      },
    );
    household.mutationSyncEventIds[mutationId] = event.syncId;
    await app.store.flush();
    _send(SyncMessage(
      SyncMessageTypes.syncReceived,
      _syncReceivedPayload(
        event,
        syncId: event.syncId,
        receivedDeviceId: deviceId ?? '',
      ),
    ));
    _broadcastToOtherDevices(
      household,
      (_) => SyncMessage(SyncMessageTypes.mutation, event.payload),
    );
  }

  void _handleActionAck(SyncMessage message) {
    final household = _registeredHousehold();
    if (household == null) return;
    final actionId = _requiredString(message, 'actionId');
    if (actionId == null) return;
  }

  Future<void> _handleSyncReceived(SyncMessage message) async {
    final household = _registeredHousehold();
    if (household == null) return;
    final syncId = _requiredString(message, 'syncId');
    if (syncId == null) return;
    final currentDeviceId = deviceId;
    if (currentDeviceId == null) return;
    final event = household.syncEvents[syncId];
    if (event == null) {
      return;
    }
    _recordDeviceAck(household, currentDeviceId, event.serverSeq);
    if (currentDeviceId != event.originDeviceId) {
      event.receivedByDeviceIds.add(currentDeviceId);
    }
    final originDeviceId = _optionalString(message.payload['originDeviceId']) ??
        event.originDeviceId;
    if (originDeviceId.isNotEmpty && originDeviceId != currentDeviceId) {
      final receiptPayload = _syncReceivedPayload(
        event,
        syncId: syncId,
        receivedDeviceId: currentDeviceId,
      );
      await app.store.flush();
      app.hub.sendTo(
        householdId!,
        originDeviceId,
        SyncMessage(SyncMessageTypes.syncReceived, receiptPayload).encode(),
      );
    }
    _pruneReceivedSyncEvents(household);
    await app.store.flush();
  }

  void _recordDeviceAck(
    Household household,
    String receivedDeviceId,
    int serverSeq,
  ) {
    final device = household.devices[receivedDeviceId];
    if (device == null || serverSeq <= 0) {
      return;
    }
    final previousSeq = device.lastAckServerSeq ?? 0;
    if (serverSeq > previousSeq) {
      device.lastAckServerSeq = serverSeq;
    }
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
      'serverSeq': event.serverSeq,
    };
    for (final key in <String>[
      'actionId',
      'kind',
      'sourceType',
      'itemId',
      'mutationId',
      'entityType',
      'entityId',
      'version',
      'dataPolicy',
      'mergeMode',
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
      'devices': _devicesFor(household, excludedDeviceId: deviceId),
    }));
  }

  void _handleDeviceUpdate(SyncMessage message) {
    final household = _registeredHousehold();
    if (household == null) return;
    final requestedDeviceId =
        _sessionRole == 'pet' ? deviceId : _requiredString(message, 'deviceId');
    if (requestedDeviceId == null) return;
    if (_sessionRole == 'pet' && message.payload.containsKey('deviceId')) {
      final explicitDeviceId = _optionalString(message.payload['deviceId']);
      if (explicitDeviceId != null && explicitDeviceId != deviceId) {
        _send(
            SyncMessage(SyncMessageTypes.pairError, {'message': 'forbidden'}));
        return;
      }
    } else if (_sessionRole != 'owner' && _sessionRole != 'pet') {
      _send(SyncMessage(SyncMessageTypes.pairError, {'message': 'forbidden'}));
      return;
    }
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
    _broadcastToOtherDevices(
      household,
      (targetDeviceId) => SyncMessage(
        SyncMessageTypes.devices,
        {'devices': _devicesFor(household, excludedDeviceId: targetDeviceId)},
      ),
    );
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
    _broadcastToOtherDevices(
      household,
      (targetDeviceId) => SyncMessage(
        SyncMessageTypes.devices,
        {'devices': _devicesFor(household, excludedDeviceId: targetDeviceId)},
      ),
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

  void _broadcastToOtherDevices(
    Household household,
    SyncMessage Function(String targetDeviceId) messageFor,
  ) {
    for (final device in household.devices.values) {
      if (device.deviceId == deviceId) {
        continue;
      }
      app.hub.sendTo(
          householdId!, device.deviceId, messageFor(device.deviceId).encode());
    }
  }

  List<Map<String, dynamic>> _devicesFor(
    Household household, {
    required String? excludedDeviceId,
  }) {
    return household.devices.values
        .where((device) => device.deviceId != excludedDeviceId)
        .map((device) => SyncedDeviceInfo(
              deviceId: device.deviceId,
              name: device.name,
              role: app.hub.roleFor(householdId!, device.deviceId) ??
                  device.role ??
                  'unknown',
              servedPetId: device.servedPetId,
              online: app.hub.isOnline(householdId!, device.deviceId),
              lastSeenMs: device.lastSeenMs,
            ).toJson())
        .toList();
  }

  SyncEventReceipt _registerSyncEvent(
    Household household, {
    required String messageType,
    required Map<String, dynamic> payload,
  }) {
    final syncId = _optionalString(payload['syncId']) ??
        '${DateTime.now().toUtc().microsecondsSinceEpoch}-${deviceId ?? 'unknown'}';
    final originDeviceId = deviceId ?? '';
    final serverSeq = household.allocateServerSeq();
    final eventPayload = Map<String, dynamic>.from(payload)
      ..['syncId'] = syncId
      ..['originDeviceId'] = originDeviceId
      ..['serverSeq'] = serverSeq;
    final event = SyncEventReceipt(
      syncId: syncId,
      originDeviceId: originDeviceId,
      messageType: messageType,
      serverSeq: serverSeq,
      payload: eventPayload,
    );
    household.syncEvents[syncId] = event;
    _enforceSyncEventRetention(household);
    return event;
  }

  _SyncEventBatch _sendMissingSyncEvents(
    Household household, {
    int? afterServerSeq,
    int? maxEvents,
  }) {
    final currentDeviceId = deviceId;
    if (currentDeviceId == null) {
      return const _SyncEventBatch();
    }
    final eventLimit = maxEvents == null ? null : maxEvents.clamp(1, 100);
    final missingCompletedKeys = <String>{};
    var receiptChanged = false;
    var sentEventCount = 0;
    var remainingEventCount = 0;
    int? fromServerSeq;
    int? toServerSeq;
    final events = household.syncEvents.values.toList(growable: false)
      ..sort((a, b) => a.serverSeq.compareTo(b.serverSeq));
    for (final event in events) {
      if (event.originDeviceId == currentDeviceId) {
        continue;
      }
      if (event.receivedByDeviceIds.contains(currentDeviceId)) {
        continue;
      }
      if (afterServerSeq != null && event.serverSeq <= afterServerSeq) {
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
      if (eventLimit != null && sentEventCount >= eventLimit) {
        remainingEventCount += 1;
        continue;
      }
      _send(SyncMessage(event.messageType, event.payload));
      sentEventCount += 1;
      fromServerSeq ??= event.serverSeq;
      toServerSeq = event.serverSeq;
    }
    if (missingCompletedKeys.isNotEmpty) {
      _sendMissingCompletedActions(household, missingCompletedKeys);
    }
    if (receiptChanged) {
      _pruneReceivedSyncEvents(household);
      unawaited(app.store.flush());
    }
    return _SyncEventBatch(
      sentEventCount: sentEventCount,
      remainingEventCount: remainingEventCount,
      fromServerSeq: fromServerSeq,
      toServerSeq: toServerSeq,
    );
  }

  void _sendMissingCompletedActions(
    Household household,
    Set<String> itemKeys,
  ) {
    for (final itemKey in itemKeys) {
      final action = household.completedActions[itemKey] ??
          household.latestAppliedChecklistActionForItem(itemKey);
      if (action == null) {
        continue;
      }
      _send(SyncMessage(SyncMessageTypes.action, action));
    }
  }

  void _sendCompletedActionReceiptIfPossible(Map<String, dynamic> action) {
    final syncId = _optionalString(action['syncId']);
    if (syncId == null) {
      return;
    }
    final household = _household;
    final event = household?.syncEvents[syncId];
    _send(SyncMessage(
      SyncMessageTypes.syncReceived,
      event == null
          ? _syncReceivedPayloadFromPayload(
              action,
              syncId: syncId,
              receivedDeviceId: deviceId ?? '',
            )
          : _syncReceivedPayload(
              event,
              syncId: syncId,
              receivedDeviceId: deviceId ?? '',
            ),
    ));
  }

  void _sendAppliedActionReceipt(Map<String, dynamic> action) {
    final syncId = _optionalString(action['syncId']);
    if (syncId == null) {
      return;
    }
    _send(SyncMessage(
      SyncMessageTypes.syncReceived,
      _syncReceivedPayloadFromPayload(
        action,
        syncId: syncId,
        receivedDeviceId: deviceId ?? '',
      ),
    ));
  }

  Map<String, dynamic> _syncReceivedPayloadFromPayload(
    Map<String, dynamic> eventPayload, {
    required String syncId,
    required String receivedDeviceId,
  }) {
    final payload = <String, dynamic>{
      'syncId': syncId,
      'originDeviceId': _optionalString(eventPayload['originDeviceId']) ?? '',
      'receivedDeviceId': receivedDeviceId,
    };
    for (final key in <String>[
      'actionId',
      'kind',
      'sourceType',
      'itemId',
      'mutationId',
      'entityType',
      'entityId',
      'version',
      'dataPolicy',
      'mergeMode',
      'occurredAtMs',
    ]) {
      final value = eventPayload[key];
      if (value != null) {
        payload[key] = value;
      }
    }
    return payload;
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
    final latestAction =
        household.latestAppliedChecklistActionForItem('$sourceType:$itemId');
    final latestSyncId = _optionalString(latestAction?['syncId']);
    final payloadSyncId = _optionalString(payload['syncId']);
    if (latestSyncId != null && latestSyncId != payloadSyncId) {
      return true;
    }
    return household.completedActions.containsKey('$sourceType:$itemId') &&
        kind != PetActionKind.markDone.name;
  }

  void _pruneReceivedSyncEvents(Household household) {
    final devices = _activeReceiptTargets(household);
    household.syncEvents.removeWhere((_, event) {
      final receiptTargets =
          devices.where((device) => device.deviceId != event.originDeviceId);
      return receiptTargets
          .every((device) => _hasDeviceReceivedEvent(device, event));
    });
    _enforceSyncEventRetention(household);
  }

  bool _hasDeviceReceivedEvent(
    HouseholdDevice device,
    SyncEventReceipt event,
  ) {
    if (event.receivedByDeviceIds.contains(device.deviceId)) {
      return true;
    }
    final lastPulledServerSeq = device.lastPulledServerSeq;
    return lastPulledServerSeq != null &&
        lastPulledServerSeq >= event.serverSeq;
  }

  List<HouseholdDevice> _activeReceiptTargets(Household household) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cutoffMs = nowMs - app.syncEventActiveDeviceTtl.inMilliseconds;
    return household.devices.values
        .where((device) =>
            app.hub.isOnline(household.id, device.deviceId) ||
            ((device.lastSeenMs ?? -1) >= cutoffMs))
        .toList(growable: false);
  }

  void _enforceSyncEventRetention(Household household) {
    final maxEvents = app.maxRetainedSyncEvents;
    final maxBytes = app.maxRetainedSyncEventBytes;
    var removedCount = 0;
    while (maxEvents > 0 && household.syncEvents.length > maxEvents) {
      final oldestSyncId = _oldestRetentionCandidateSyncId(household);
      if (oldestSyncId == null) {
        household.syncEvents.remove(household.syncEvents.keys.first);
        removedCount += 1;
        continue;
      }
      household.syncEvents.remove(oldestSyncId);
      removedCount += 1;
    }
    var payloadBytes = _syncEventPayloadBytes(household);
    while (maxBytes > 0 &&
        household.syncEvents.isNotEmpty &&
        payloadBytes > maxBytes) {
      final oldestSyncId = _oldestRetentionCandidateSyncId(household);
      if (oldestSyncId == null) {
        household.syncEvents.remove(household.syncEvents.keys.first);
        removedCount += 1;
        payloadBytes = _syncEventPayloadBytes(household);
        continue;
      }
      household.syncEvents.remove(oldestSyncId);
      removedCount += 1;
      payloadBytes = _syncEventPayloadBytes(household);
    }
    if (removedCount > 0) {
      stderr.writeln(
        '[PetNoteSyncServer] pruned $removedCount sync events '
        'for household=${household.id} remaining=${household.syncEvents.length} '
        'bytes=$payloadBytes',
      );
    }
  }

  String? _oldestRetentionCandidateSyncId(Household household) {
    for (final entry in household.syncEvents.entries) {
      if (_canPruneSyncEventForRetention(household, entry.value)) {
        return entry.key;
      }
    }
    return null;
  }

  bool _canPruneSyncEventForRetention(
    Household household,
    SyncEventReceipt event,
  ) {
    final receiptTargets = _activeReceiptTargets(household)
        .where((device) => device.deviceId != event.originDeviceId);
    return receiptTargets
        .every((device) => _hasDeviceReceivedEvent(device, event));
  }

  int _syncEventPayloadBytes(Household household) {
    final payload = household.syncEvents.map(
      (syncId, event) => MapEntry(syncId, event.toJson()),
    );
    return utf8.encode(jsonEncode(payload)).length;
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

  int? _optionalInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  int? _optionalPositiveInt(Object? value) {
    final parsed = _optionalInt(value);
    if (parsed == null || parsed < 0) {
      return null;
    }
    return parsed;
  }

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

class _SyncEventBatch {
  const _SyncEventBatch({
    this.sentEventCount = 0,
    this.remainingEventCount = 0,
    this.fromServerSeq,
    this.toServerSeq,
  });

  final int sentEventCount;
  final int remainingEventCount;
  final int? fromServerSeq;
  final int? toServerSeq;
}
