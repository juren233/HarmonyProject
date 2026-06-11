import 'dart:convert';
import 'dart:io';

class HouseholdDevice {
  HouseholdDevice({
    required this.deviceId,
    required this.name,
    required this.role,
    this.servedPetId,
    this.lastSeenMs,
  });

  final String deviceId;
  String name;
  final String role;
  String? servedPetId;
  int? lastSeenMs;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'role': role,
        if (servedPetId != null) 'servedPetId': servedPetId,
        if (lastSeenMs != null) 'lastSeenMs': lastSeenMs,
      };

  factory HouseholdDevice.fromJson(Map<String, dynamic> json) =>
      HouseholdDevice(
        deviceId: json['deviceId'] as String,
        name: json['name'] as String,
        role: json['role'] as String,
        servedPetId: json['servedPetId'] as String?,
        lastSeenMs: json['lastSeenMs'] as int?,
      );
}

class Household {
  Household({required this.id, required this.saltBase64});

  final String id;
  final String saltBase64;
  int snapshotVersion = 0;
  String? snapshotCiphertext;
  final Map<String, HouseholdDevice> devices = <String, HouseholdDevice>{};
  final List<Map<String, dynamic>> pendingActions = <Map<String, dynamic>>[];

  Map<String, dynamic> toJson() => {
        'id': id,
        'saltBase64': saltBase64,
        'snapshotVersion': snapshotVersion,
        if (snapshotCiphertext != null)
          'snapshotCiphertext': snapshotCiphertext,
        'devices': devices.map(
          (deviceId, device) => MapEntry(deviceId, device.toJson()),
        ),
        'pendingActions': pendingActions,
      };

  factory Household.fromJson(Map<String, dynamic> json) {
    final household = Household(
      id: json['id'] as String,
      saltBase64: json['saltBase64'] as String,
    )
      ..snapshotVersion = json['snapshotVersion'] as int? ?? 0
      ..snapshotCiphertext = json['snapshotCiphertext'] as String?;

    final devicesJson =
        json['devices'] as Map<String, dynamic>? ?? <String, dynamic>{};
    for (final entry in devicesJson.entries) {
      household.devices[entry.key] = HouseholdDevice.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }

    final pendingJson = json['pendingActions'] as List<dynamic>? ?? <dynamic>[];
    household.pendingActions.addAll(
      pendingJson.map((action) => Map<String, dynamic>.from(action as Map)),
    );

    return household;
  }
}

class HouseholdStore {
  HouseholdStore(this.dataDirectory);

  final Directory dataDirectory;
  final Map<String, Household> _households = <String, Household>{};

  File get _file => File('${dataDirectory.path}/households.json');

  Household? household(String? id) => id == null ? null : _households[id];

  Household create(String id, String saltBase64) {
    final household = Household(id: id, saltBase64: saltBase64);
    _households[id] = household;
    return household;
  }

  Future<void> load() async {
    _households.clear();
    if (!await _file.exists()) {
      return;
    }

    final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    final householdsJson =
        json['households'] as Map<String, dynamic>? ?? <String, dynamic>{};
    for (final entry in householdsJson.entries) {
      _households[entry.key] =
          Household.fromJson(entry.value as Map<String, dynamic>);
    }
  }

  Future<void> flush() async {
    if (!await dataDirectory.exists()) {
      await dataDirectory.create(recursive: true);
    }
    await _file.writeAsString(
      jsonEncode({
        'households': _households.map(
          (id, household) => MapEntry(id, household.toJson()),
        ),
      }),
    );
  }
}
