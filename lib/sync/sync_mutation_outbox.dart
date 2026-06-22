import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_failure_queue.dart';
import 'package:petnote/sync/sync_photo_attachment.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class SyncMutationOutbox {
  SyncMutationOutbox({
    required this.store,
    required this.crypto,
    required this.failureQueue,
    required this.lastError,
    required this.isStopped,
    this.pendingItemKeys,
    this.beforeSend,
  });

  final PetNoteStore store;
  final SyncCrypto crypto;
  final SyncFailureQueue failureQueue;
  final ValueNotifier<Object?> lastError;
  final bool Function() isStopped;
  final ValueNotifier<Set<String>>? pendingItemKeys;
  final VoidCallback? beforeSend;
  final SyncPhotoAttachmentCodec _photoAttachmentCodec =
      const SyncPhotoAttachmentCodec();

  final Set<String> _pendingActionKeys = <String>{};
  StreamSubscription<PetNoteMutation>? _subscription;
  int _runtimeGeneration = 0;

  void start() {
    if (_subscription != null) {
      return;
    }
    _subscription = store.localMutations.listen((mutation) {
      unawaited(pushMutation(mutation));
    }, onError: (Object error) {
      lastError.value = error;
    });
  }

  Future<void> flushPendingMutations() async {
    final generation = _runtimeGeneration;
    for (final mutation in store.pendingLocalMutations) {
      if (generation != _runtimeGeneration) {
        return;
      }
      await pushMutation(mutation);
    }
  }

  bool hasPendingAction(PetAction action) {
    return _pendingActionKeys.contains(action.dedupeKey);
  }

  Future<void> pushMutation(PetNoteMutation mutation) async {
    try {
      final generation = _runtimeGeneration;
      if (isStopped()) {
        return;
      }
      if (generation != _runtimeGeneration) {
        return;
      }
      beforeSend?.call();
      if (generation != _runtimeGeneration) {
        return;
      }
      if (mutation.kind == PetNoteMutationKind.checklistAction) {
        if (generation != _runtimeGeneration) {
          return;
        }
        await _pushChecklistAction(mutation);
        return;
      }
      final mutationPayload = mutation.toJson();
      final petPhotoAttachment = await _petPhotoAttachmentJson(mutation);
      if (petPhotoAttachment != null) {
        mutationPayload[petPhotoAttachmentPayloadKey] = petPhotoAttachment;
      }
      final json = jsonEncode(mutationPayload);
      if (generation != _runtimeGeneration) {
        return;
      }
      final message = SyncMessage(SyncMessageTypes.mutationPush, {
        'mutationId': mutation.id,
        'ciphertext': await crypto.encryptString(json),
        'entityType': mutation.entityType.name,
        'entityId': mutation.entityId,
        'kind': mutation.kind.name,
      });
      if (generation != _runtimeGeneration) {
        return;
      }
      failureQueue.sendOrQueue(message);
      if (generation != _runtimeGeneration) {
        return;
      }
    } on Object catch (error) {
      lastError.value = error;
    }
  }

  Future<Map<String, dynamic>?> _petPhotoAttachmentJson(
    PetNoteMutation mutation,
  ) async {
    if (mutation.entityType != PetNoteEntityType.pet ||
        mutation.kind != PetNoteMutationKind.upsert) {
      return null;
    }
    final data = mutation.data;
    if (data == null) {
      return null;
    }
    final attachment = await _photoAttachmentCodec.collectForPet(
      Pet.fromJson(data),
    );
    return attachment?.toJson();
  }

  Future<void> applySyncReceived(SyncMessage message) async {
    final mutationId = message.payload['mutationId'];
    if (mutationId is String && mutationId.isNotEmpty) {
      await store.markMutationSynced(mutationId);
    }
    final sourceType = message.payload['sourceType'];
    final itemId = message.payload['itemId'];
    if (sourceType is! String ||
        sourceType.isEmpty ||
        itemId is! String ||
        itemId.isEmpty) {
      return;
    }
    final itemKey = '$sourceType:$itemId';
    final kind = message.payload['kind'];
    if (kind is String && kind.isNotEmpty) {
      _pendingActionKeys.remove('$itemKey:$kind');
    } else {
      _pendingActionKeys.removeWhere((key) => key.startsWith('$itemKey:'));
    }
    await store.markChecklistActionSynced(
      sourceType: sourceType,
      itemId: itemId,
      kind: kind as String?,
    );
    _removePendingItemKey(itemKey);
  }

  Future<void> markRemoteActionApplied(PetAction action) async {
    final itemKey = '${action.sourceType}:${action.itemId}';
    await store.markChecklistActionSynced(
      sourceType: action.sourceType,
      itemId: action.itemId,
      kind: action.kind.name,
    );
    if (action.kind == PetActionKind.markDone) {
      _pendingActionKeys.removeWhere((key) => key.startsWith('$itemKey:'));
    } else {
      _pendingActionKeys.remove(action.dedupeKey);
    }
    _removePendingItemKey(itemKey);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    clearRuntimeState();
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    clearRuntimeState(clearFailureQueue: false);
  }

  void clearRuntimeState({bool clearFailureQueue = true}) {
    _runtimeGeneration += 1;
    _pendingActionKeys.clear();
    pendingItemKeys?.value = const <String>{};
    if (clearFailureQueue) {
      failureQueue.clear();
    }
  }

  Future<void> _pushChecklistAction(PetNoteMutation mutation) async {
    final generation = _runtimeGeneration;
    if (isStopped()) {
      return;
    }
    final actionKind = mutation.actionKind;
    if (actionKind == null) {
      throw const FormatException('missing checklist action kind');
    }
    final sourceType = _sourceTypeForEntityType(mutation.entityType);
    final action = PetAction(
      kind: actionKind,
      sourceType: sourceType,
      itemId: mutation.entityId,
      occurredAtMs: mutation.occurredAtMs,
    );
    final message = SyncMessage(SyncMessageTypes.actionPush, {
      'actionId': mutation.id,
      'ciphertext': await crypto.encryptString(jsonEncode(action.toJson())),
      'kind': action.kind.name,
      'sourceType': action.sourceType,
      'itemId': action.itemId,
      if (action.occurredAtMs != null) 'occurredAtMs': action.occurredAtMs,
    });
    if (generation != _runtimeGeneration) {
      return;
    }
    failureQueue.sendOrQueue(message);
    if (generation != _runtimeGeneration) {
      return;
    }
    _pendingActionKeys.add(action.dedupeKey);
    pendingItemKeys?.value = <String>{
      ...?pendingItemKeys?.value,
      '${action.sourceType}:${action.itemId}',
    };
  }

  void _removePendingItemKey(String itemKey) {
    final notifier = pendingItemKeys;
    if (notifier == null) {
      return;
    }
    notifier.value = {
      for (final key in notifier.value)
        if (key != itemKey) key,
    };
  }

  String _sourceTypeForEntityType(PetNoteEntityType entityType) {
    return switch (entityType) {
      PetNoteEntityType.todo => 'todo',
      PetNoteEntityType.reminder => 'reminder',
      PetNoteEntityType.pet ||
      PetNoteEntityType.record =>
        throw FormatException('unsupported checklist entity: $entityType'),
    };
  }
}
