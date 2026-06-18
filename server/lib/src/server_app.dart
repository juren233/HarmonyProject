import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'household_store.dart';
import 'pairing_service.dart';
import 'rtc_token_service.dart';
import 'session_handler.dart';
import 'ws_hub.dart';

class SyncServerApp {
  SyncServerApp({
    required Directory dataDirectory,
    RtcTokenService? rtcTokenService,
  })  : store = HouseholdStore(dataDirectory),
        hub = WsHub(),
        rtcTokenService = rtcTokenService ??
            RtcTokenService.fromEnvironment(Platform.environment) {
    pairing = PairingService(store);
  }

  final HouseholdStore store;
  final WsHub hub;
  final RtcTokenService rtcTokenService;
  late final PairingService pairing;

  Future<HttpServer> serve(
      {required InternetAddress address, required int port}) async {
    await store.load();
    final handler =
        const Pipeline().addMiddleware(logRequests()).addHandler(_route);
    return shelf_io.serve(handler, address, port);
  }

  Future<Response> _route(Request request) async {
    if (request.url.path == 'healthz') {
      return Response.ok('ok');
    }
    if (request.url.path == 'rtc/token') {
      return _handleRtcToken(request);
    }
    if (request.url.path == 'ws') {
      return webSocketHandler((WebSocketChannel channel, _) {
        SessionHandler(app: this, channel: channel).bind();
      })(request);
    }
    return Response.notFound('not found');
  }

  Future<Response> _handleRtcToken(Request request) async {
    if (request.method != 'POST') {
      return Response(405, body: 'method not allowed');
    }
    if (!rtcTokenService.isConfigured) {
      return Response(503, body: 'rtc not configured');
    }
    final body = await request.readAsString();
    final Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return Response(400, body: 'bad request');
      }
      payload = decoded;
    } on FormatException {
      return Response(400, body: 'bad request');
    }
    final channelId = payload['channelId'];
    final userId = payload['userId'];
    final role = payload['role'];
    final householdId = payload['householdId'];
    final authToken = payload['authToken'];
    if (channelId is! String || userId is! String || role is! String) {
      return Response(400, body: 'bad request');
    }
    if (householdId is! String || authToken is! String) {
      return Response(401, body: 'unauthorized');
    }
    final household = store.household(householdId);
    if (household == null || household.authToken != authToken) {
      return Response(401, body: 'unauthorized');
    }
    if (!household.devices.containsKey(userId)) {
      return Response(403, body: 'forbidden');
    }
    try {
      final token = rtcTokenService.issueToken(
        channelId: channelId,
        userId: userId,
        role: RtcUserRole.parse(role),
      );
      return Response.ok(
        jsonEncode(token.toJson()),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    } on FormatException {
      return Response(400, body: 'bad request');
    } on StateError {
      return Response(503, body: 'rtc not configured');
    }
  }

  Future<void> close() async {
    await hub.closeAll();
    await store.flush();
  }
}
