import 'package:petnote/sync/multi_device_sync_controller.dart';

class PetReplicaController extends MultiDeviceSyncController {
  PetReplicaController({
    required super.store,
    required super.transport,
    required super.crypto,
    super.resolveMergeConflict,
    super.settings,
    super.onRemoved,
    super.throttle,
    super.photoAttachmentCodec,
    super.initialVersion,
    super.canSend,
  });
}
