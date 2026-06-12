import 'package:flutter/foundation.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

enum SyncConnectionState { disconnected, connecting, connected }

abstract class SyncTransport {
  Stream<SyncMessage> get messages;
  Stream<Object> get errors;
  ValueListenable<SyncConnectionState> get state;

  Future<void> connect();
  void send(SyncMessage message);
  Future<void> disconnect();
}
