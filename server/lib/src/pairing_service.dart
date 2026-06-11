import 'dart:math';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

import 'household_store.dart';

class PairingCodeTicket {
  PairingCodeTicket({
    required this.code,
    required this.householdId,
    required this.saltBase64,
    required this.expiresAt,
  });

  final String code;
  final String householdId;
  final String saltBase64;
  final DateTime expiresAt;
}

class PairingJoinResult {
  PairingJoinResult({required this.householdId, required this.saltBase64});

  final String householdId;
  final String saltBase64;
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
    required String ownerDeviceId,
    required String ownerDeviceName,
    DateTime? now,
  }) {
    final issuedAt = now ?? DateTime.now().toUtc();
    final existing = _store.household(existingHouseholdId);
    final household =
        existing ?? _store.create(_newId(), SyncCrypto.generateSaltBase64());

    household.devices.putIfAbsent(
      ownerDeviceId,
      () => HouseholdDevice(
        deviceId: ownerDeviceId,
        name: ownerDeviceName,
        role: 'owner',
      ),
    );

    final ticket = PairingCodeTicket(
      code: _newCode(),
      householdId: household.id,
      saltBase64: household.saltBase64,
      expiresAt: issuedAt.add(codeTtl),
    );
    _activeCodes[ticket.code] = ticket;
    return ticket;
  }

  PairingJoinResult? redeem({
    required String code,
    required String petDeviceId,
    required String petDeviceName,
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
      petDeviceId,
      () => HouseholdDevice(
        deviceId: petDeviceId,
        name: petDeviceName,
        role: 'pet',
      ),
    );

    return PairingJoinResult(
      householdId: household.id,
      saltBase64: household.saltBase64,
    );
  }

  String _newCode() => _random.nextInt(1000000).toString().padLeft(6, '0');

  String _newId() {
    final timestamp =
        DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(36);
    final suffix =
        _random.nextInt(36 * 36 * 36 * 36).toRadixString(36).padLeft(4, '0');
    return '$timestamp$suffix';
  }
}
