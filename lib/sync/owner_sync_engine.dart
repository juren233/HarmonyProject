import 'package:petnote/sync/multi_device_sync_controller.dart';

class OwnerSyncEngine extends MultiDeviceSyncController {
  OwnerSyncEngine({
    required super.store,
    required super.transport,
    required super.crypto,
    super.resolveMergeConflict,
    super.settings,
    super.onRemoved,
    super.throttle,
    super.initialVersion,
  });

  @override
  Future<void> start({
    bool pushInitialSnapshot = true,
    bool requestInitialSnapshot = false,
  }) {
    return super.start(
      pushInitialSnapshot: pushInitialSnapshot,
      requestInitialSnapshot: requestInitialSnapshot,
    );
  }
}
