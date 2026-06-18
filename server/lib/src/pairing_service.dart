import 'dart:convert';
import 'dart:math';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

import 'household_store.dart';

class PairingCodeTicket {
  PairingCodeTicket({
    required this.code,
    required this.householdId,
    required this.saltBase64,
    required this.authToken,
    required this.expiresAt,
    this.sharedKeyBase64,
  });

  final String code;
  final String householdId;
  final String saltBase64;
  final String authToken;
  final DateTime expiresAt;
  final String? sharedKeyBase64;
}

class PairingJoinResult {
  PairingJoinResult({
    required this.householdId,
    required this.saltBase64,
    required this.authToken,
    this.sharedKeyBase64,
  });

  final String householdId;
  final String saltBase64;
  final String authToken;
  final String? sharedKeyBase64;
}

class PairingService {
  PairingService(this._store);

  static const codeTtl = Duration(minutes: 5);

  final HouseholdStore _store;
  final Map<String, PairingCodeTicket> _activeCodes =
      <String, PairingCodeTicket>{};
  final Random _random = Random.secure();

  PairingCodeTicket createCode({
    String? existingHouseholdId,
    String? existingAuthToken,
    String? existingSharedKeyBase64,
    required String issuerDeviceId,
    required String issuerDeviceName,
    required String issuerRole,
    DateTime? now,
  }) {
    final issuedAt = now ?? DateTime.now().toUtc();
    final existing = _store.household(existingHouseholdId);
    final household = existing ??
        (existingHouseholdId != null && existingAuthToken != null
            ? _store.adoptExisting(
                existingHouseholdId,
                SyncCrypto.generateSaltBase64(),
                existingAuthToken,
              )
            : _store.create(
                _newId(),
                SyncCrypto.generateSaltBase64(),
                _newToken(),
              ));

    household.devices.putIfAbsent(
      issuerDeviceId,
      () => HouseholdDevice(
        deviceId: issuerDeviceId,
        name: issuerDeviceName,
      ),
    );

    final ticket = PairingCodeTicket(
      code: _newUniqueCode(),
      householdId: household.id,
      saltBase64: household.saltBase64,
      authToken: household.authToken,
      expiresAt: issuedAt.add(codeTtl),
      sharedKeyBase64: existingSharedKeyBase64,
    );
    _activeCodes[ticket.code] = ticket;
    return ticket;
  }

  PairingJoinResult? redeem({
    required String code,
    required String joiningDeviceId,
    required String joiningDeviceName,
    required String joiningRole,
    DateTime? now,
  }) {
    final ticket = _activeCodes.remove(code);
    if (ticket == null) {
      return null;
    }

    final redeemedAt = now ?? DateTime.now().toUtc();
    if (redeemedAt.isAfter(ticket.expiresAt)) {
      return null;
    }

    final household = _store.household(ticket.householdId);
    if (household == null) {
      return null;
    }

    household.devices.putIfAbsent(
      joiningDeviceId,
      () => HouseholdDevice(
        deviceId: joiningDeviceId,
        name: joiningDeviceName,
      ),
    );

    return PairingJoinResult(
      householdId: household.id,
      saltBase64: household.saltBase64,
      authToken: household.authToken,
      sharedKeyBase64: ticket.sharedKeyBase64,
    );
  }

  void releaseCode(String code) {
    _activeCodes.remove(code);
  }

  String _newUniqueCode() {
    for (var attempt = 0; attempt < 10000; attempt += 1) {
      final code = _newCode();
      if (!_activeCodes.containsKey(code)) {
        return code;
      }
    }
    throw StateError('没有可用的配对码');
  }

  String _newCode() => _random.nextInt(10000).toString().padLeft(4, '0');

  String _newToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _newId() {
    final timestamp =
        DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(36);
    final suffix =
        _random.nextInt(36 * 36 * 36 * 36).toRadixString(36).padLeft(4, '0');
    return '$timestamp$suffix';
  }
}
