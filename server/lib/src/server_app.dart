import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'household_store.dart';
import 'pairing_service.dart';
import 'session_handler.dart';
import 'ws_hub.dart';

class SyncServerApp {
  SyncServerApp({required Directory dataDirectory})
      : store = HouseholdStore(dataDirectory),
        hub = WsHub() {
    pairing = PairingService(store);
  }

  final HouseholdStore store;
  final WsHub hub;
  late final PairingService pairing;

  Future<HttpServer> serve({required InternetAddress address, required int port}) async {
    await store.load();
    final handler = const Pipeline().addMiddleware(logRequests()).addHandler(_route);
    return shelf_io.serve(handler, address, port);
  }

  Future<Response> _route(Request request) async {
    if (request.url.path == 'healthz') {
      return Response.ok('ok');
    }
    if (request.url.path == 'ws') {
      return webSocketHandler((WebSocketChannel channel, _) {
        SessionHandler(app: this, channel: channel).bind();
      })(request);
    }
    return Response.notFound('not found');
  }

  Future<void> close() async {
    await hub.closeAll();
    await store.flush();
  }
}
