enum NotificationSourceType { todo, reminder }

enum NotificationRouteTarget { checklist }

enum NotificationPermissionState {
  unknown,
  denied,
  authorized,
  provisional,
  unsupported,
}

enum NotificationSettingsOpenResult {
  opened,
  failed,
  unsupported,
}

enum NotificationExactAlarmStatus {
  available,
  unavailable,
  unsupported,
}

class NotificationPlatformCapabilities {
  const NotificationPlatformCapabilities({
    this.exactAlarmStatus = NotificationExactAlarmStatus.unsupported,
    this.maxScheduledNotificationCount,
  });

  final NotificationExactAlarmStatus exactAlarmStatus;
  final int? maxScheduledNotificationCount;

  bool get canScheduleExactAlarms =>
      exactAlarmStatus == NotificationExactAlarmStatus.available;

  bool get supportsExactAlarms =>
      exactAlarmStatus != NotificationExactAlarmStatus.unsupported;

  Map<String, dynamic> toMap() {
    return {
      'exactAlarmStatus': exactAlarmStatus.name,
      'maxScheduledNotificationCount': maxScheduledNotificationCount,
    };
  }

  factory NotificationPlatformCapabilities.fromMap(Map<Object?, Object?>? map) {
    return NotificationPlatformCapabilities(
      exactAlarmStatus: notificationExactAlarmStatusFromName(
        map?['exactAlarmStatus'] as String?,
      ),
      maxScheduledNotificationCount:
          (map?['maxScheduledNotificationCount'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NotificationPlatformCapabilities &&
        other.exactAlarmStatus == exactAlarmStatus &&
        other.maxScheduledNotificationCount == maxScheduledNotificationCount;
  }

  @override
  int get hashCode => Object.hash(
        exactAlarmStatus,
        maxScheduledNotificationCount,
      );
}

class NotificationPayload {
  const NotificationPayload({
    required this.sourceType,
    required this.sourceId,
    required this.petId,
    required this.routeTarget,
  });

  final NotificationSourceType sourceType;
  final String sourceId;
  final String petId;
  final NotificationRouteTarget routeTarget;

  String get key => '${sourceType.name}:$sourceId';

  Map<String, dynamic> toMap() {
    return {
      'sourceType': sourceType.name,
      'sourceId': sourceId,
      'petId': petId,
      'routeTarget': routeTarget.name,
    };
  }

  factory NotificationPayload.fromMap(Map<Object?, Object?> map) {
    return NotificationPayload(
      sourceType: notificationSourceTypeFromName(map['sourceType'] as String?),
      sourceId: map['sourceId'] as String? ?? '',
      petId: map['petId'] as String? ?? '',
      routeTarget: notificationRouteTargetFromName(
        map['routeTarget'] as String?,
      ),
    );
  }
}

class NotificationLaunchIntent {
  const NotificationLaunchIntent({
    required this.payload,
    this.fromForeground = false,
  });

  final NotificationPayload payload;
  final bool fromForeground;

  Map<String, dynamic> toMap() {
    return {
      'payload': payload.toMap(),
      'fromForeground': fromForeground,
    };
  }

  factory NotificationLaunchIntent.fromMap(Map<Object?, Object?> map) {
    return NotificationLaunchIntent(
      payload: NotificationPayload.fromMap(
        Map<Object?, Object?>.from(
          map['payload'] as Map? ?? const <Object?, Object?>{},
        ),
      ),
      fromForeground: map['fromForeground'] as bool? ?? false,
    );
  }
}

class NotificationJob {
  const NotificationJob({
    required this.payload,
    required this.scheduledAt,
    DateTime? eventScheduledAt,
    this.reminderLeadTimeMinutes = 0,
    required this.title,
    required this.body,
  }) : eventScheduledAt = eventScheduledAt ?? scheduledAt;

  final NotificationPayload payload;
  final DateTime scheduledAt;
  final DateTime eventScheduledAt;
  final int reminderLeadTimeMinutes;
  final String title;
  final String body;

  String get key => payload.key;

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'scheduledAtEpochMs': scheduledAt.millisecondsSinceEpoch,
      'eventScheduledAtEpochMs': eventScheduledAt.millisecondsSinceEpoch,
      'reminderLeadTimeMinutes': reminderLeadTimeMinutes,
      'title': title,
      'body': body,
      'payload': payload.toMap(),
    };
  }
}

NotificationSourceType notificationSourceTypeFromName(String? value) {
  return switch (value) {
    'reminder' => NotificationSourceType.reminder,
    _ => NotificationSourceType.todo,
  };
}

NotificationRouteTarget notificationRouteTargetFromName(String? value) {
  return switch (value) {
    _ => NotificationRouteTarget.checklist,
  };
}

NotificationPermissionState notificationPermissionStateFromName(String? value) {
  return switch (value) {
    'denied' => NotificationPermissionState.denied,
    'authorized' => NotificationPermissionState.authorized,
    'provisional' => NotificationPermissionState.provisional,
    'unsupported' => NotificationPermissionState.unsupported,
    _ => NotificationPermissionState.unknown,
  };
}

NotificationSettingsOpenResult notificationSettingsOpenResultFromName(
  String? value,
) {
  return switch (value) {
    'opened' => NotificationSettingsOpenResult.opened,
    'failed' => NotificationSettingsOpenResult.failed,
    _ => NotificationSettingsOpenResult.unsupported,
  };
}

NotificationExactAlarmStatus notificationExactAlarmStatusFromName(
  String? value,
) {
  return switch (value) {
    'available' => NotificationExactAlarmStatus.available,
    'unavailable' => NotificationExactAlarmStatus.unavailable,
    _ => NotificationExactAlarmStatus.unsupported,
  };
}
