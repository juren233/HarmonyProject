import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'household_store.dart';
import 'pairing_service.dart';
import 'powersync_jwt.dart';
import 'powersync_upload_repository.dart';
import 'rtc_token_service.dart';
import 'session_handler.dart';
import 'ws_hub.dart';

class SyncServerApp {
  SyncServerApp({
    required Directory dataDirectory,
    RtcTokenService? rtcTokenService,
    PowerSyncJwtSigner? powerSyncJwtSigner,
    PowerSyncUploadRepository? powerSyncUploadRepository,
    String? powerSyncEndpoint,
  })  : store = HouseholdStore(dataDirectory),
        hub = WsHub(),
        rtcTokenService = rtcTokenService ??
            RtcTokenService.fromEnvironment(Platform.environment),
        powerSyncJwtSigner = powerSyncJwtSigner ??
            PowerSyncJwtSigner.fromEnvironment(Platform.environment),
        powerSyncUploadRepository = powerSyncUploadRepository ??
            PostgresPowerSyncUploadRepository.fromEnvironment(
                Platform.environment),
        powerSyncEndpoint = powerSyncEndpoint ??
            (Platform.environment['POWERSYNC_ENDPOINT'] ??
                'http://127.0.0.1:8080') {
    pairing = PairingService(store);
  }

  final HouseholdStore store;
  final WsHub hub;
  final RtcTokenService rtcTokenService;
  final PowerSyncJwtSigner powerSyncJwtSigner;
  final PowerSyncUploadRepository powerSyncUploadRepository;
  final String powerSyncEndpoint;
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
    if (request.url.path == 'powersync/credentials') {
      return _handlePowerSyncCredentials(request);
    }
    if (request.url.path == 'powersync/upload') {
      return _handlePowerSyncUpload(request);
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
    final payload = await _readJsonObject(request);
    if (payload == null) {
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

  Future<Response> _handlePowerSyncCredentials(Request request) async {
    if (request.method != 'POST') {
      return Response(405, body: 'method not allowed');
    }
    if (!powerSyncJwtSigner.isConfigured) {
      return Response(503, body: 'powersync not configured');
    }
    final payload = await _readJsonObject(request);
    if (payload == null) {
      return Response(400, body: 'bad request');
    }
    final auth = _authenticatePowerSyncPayload(payload);
    if (auth.error != null) {
      return auth.error!;
    }
    final context = auth.context!;
    final signedToken = powerSyncJwtSigner.sign(
      householdId: context.householdId,
      deviceId: context.deviceId,
      role: context.role,
    );
    return Response.ok(
      jsonEncode({
        'endpoint': powerSyncEndpoint,
        'token': signedToken.token,
        'user_id': context.deviceId,
        'expires_at_ms': signedToken.expiresAt.millisecondsSinceEpoch,
      }),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _handlePowerSyncUpload(Request request) async {
    if (request.method != 'POST') {
      return Response(405, body: 'method not allowed');
    }
    final payload = await _readJsonObject(request);
    if (payload == null) {
      return Response(400, body: 'bad request');
    }
    final auth = _authenticatePowerSyncPayload(payload);
    if (auth.error != null) {
      return auth.error!;
    }
    if (!powerSyncUploadRepository.isConfigured) {
      return Response(503, body: 'powersync database not configured');
    }
    final operationsJson = payload['operations'];
    if (operationsJson is! List) {
      return Response(400, body: 'bad request');
    }
    if (operationsJson.any((item) => item is! Map)) {
      return Response(400, body: 'bad request');
    }
    try {
      final operations = operationsJson
          .cast<Map>()
          .map((item) => PowerSyncUploadOperation.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false);
      final context = auth.context!;
      final result = await powerSyncUploadRepository.applyUpload(
        PowerSyncUploadRequest(
          householdId: context.householdId,
          deviceId: context.deviceId,
          role: context.role,
          operations: operations,
        ),
      );
      return Response.ok(
        jsonEncode({'applied': result.applied, 'skipped': result.skipped}),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    } on FormatException {
      return Response(400, body: 'bad request');
    }
  }

  Future<Map<String, dynamic>?> _readJsonObject(Request request) async {
    final body = await request.readAsString();
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  _PowerSyncAuthResult _authenticatePowerSyncPayload(
    Map<String, dynamic> payload,
  ) {
    final householdId = payload['householdId'];
    final authToken = payload['authToken'];
    final deviceId = payload['deviceId'];
    if (householdId is! String || authToken is! String || deviceId is! String) {
      return _PowerSyncAuthResult.error(Response(401, body: 'unauthorized'));
    }
    final household = store.household(householdId);
    if (household == null || household.authToken != authToken) {
      return _PowerSyncAuthResult.error(Response(401, body: 'unauthorized'));
    }
    final device = household.devices[deviceId];
    if (device == null) {
      return _PowerSyncAuthResult.error(Response(403, body: 'forbidden'));
    }
    final requestedRole = payload['role'];
    final role = requestedRole is String && requestedRole.trim().isNotEmpty
        ? requestedRole.trim()
        : device.role ?? 'unknown';
    return _PowerSyncAuthResult.context(_PowerSyncAuthContext(
      householdId: householdId,
      deviceId: deviceId,
      role: role,
    ));
  }

  Future<void> close() async {
    await hub.closeAll();
    await powerSyncUploadRepository.close();
    await store.flush();
  }
}

class _PowerSyncAuthContext {
  const _PowerSyncAuthContext({
    required this.householdId,
    required this.deviceId,
    required this.role,
  });

  final String householdId;
  final String deviceId;
  final String role;
}

class _PowerSyncAuthResult {
  const _PowerSyncAuthResult._({this.context, this.error});

  factory _PowerSyncAuthResult.context(_PowerSyncAuthContext context) {
    return _PowerSyncAuthResult._(context: context);
  }

  factory _PowerSyncAuthResult.error(Response error) {
    return _PowerSyncAuthResult._(error: error);
  }

  final _PowerSyncAuthContext? context;
  final Response? error;
}
