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
    String? diagnosticsToken,
    this.syncEventActiveDeviceTtl = const Duration(days: 30),
    this.maxRetainedSyncEvents = 1000,
    this.maxRetainedSyncEventBytes = 8 * 1024 * 1024,
  })  : store = HouseholdStore(dataDirectory),
        hub = WsHub(),
        diagnosticsToken = _normalizedDiagnosticsToken(diagnosticsToken),
        rtcTokenService = rtcTokenService ??
            RtcTokenService.fromEnvironment(Platform.environment) {
    pairing = PairingService(store);
  }

  final HouseholdStore store;
  final WsHub hub;
  final RtcTokenService rtcTokenService;
  final String? diagnosticsToken;
  final Duration syncEventActiveDeviceTtl;
  final int maxRetainedSyncEvents;
  final int maxRetainedSyncEventBytes;
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
    if (request.url.path == 'diagnostics/sync') {
      return _handleSyncDiagnostics(request);
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

  Response _handleSyncDiagnostics(Request request) {
    final token = diagnosticsToken;
    if (token == null) {
      return Response.notFound('not found');
    }
    if (request.method != 'GET') {
      return Response(405, body: 'method not allowed');
    }
    if (!_hasDiagnosticsToken(request, token)) {
      return Response(401, body: 'unauthorized');
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final households = store.households
        .map((household) => _diagnosticsForHousehold(household, nowMs))
        .toList(growable: false);
    final totals = <String, dynamic>{
      'householdCount': households.length,
      'deviceCount': households.fold<int>(
        0,
        (sum, household) => sum + (household['deviceCount'] as int),
      ),
      'activeDeviceCount': households.fold<int>(
        0,
        (sum, household) => sum + (household['activeDeviceCount'] as int),
      ),
      'onlineDeviceCount': households.fold<int>(
        0,
        (sum, household) => sum + (household['onlineDeviceCount'] as int),
      ),
      'syncEventCount': households.fold<int>(
        0,
        (sum, household) => sum + (household['syncEventCount'] as int),
      ),
      'syncEventBytes': households.fold<int>(
        0,
        (sum, household) => sum + (household['syncEventBytes'] as int),
      ),
    };
    return Response.ok(
      jsonEncode({
        'generatedAtMs': nowMs,
        'retention': {
          'activeDeviceTtlMs': syncEventActiveDeviceTtl.inMilliseconds,
          'maxRetainedSyncEvents': maxRetainedSyncEvents,
          'maxRetainedSyncEventBytes': maxRetainedSyncEventBytes,
        },
        'totals': totals,
        'households': households,
      }),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Map<String, dynamic> _diagnosticsForHousehold(
    Household household,
    int nowMs,
  ) {
    final cutoffMs = nowMs - syncEventActiveDeviceTtl.inMilliseconds;
    final devices = household.devices.values.map((device) {
      final online = hub.isOnline(household.id, device.deviceId);
      final active = online || ((device.lastSeenMs ?? -1) >= cutoffMs);
      return {
        'deviceId': device.deviceId,
        'name': device.name,
        'role': hub.roleFor(household.id, device.deviceId) ??
            device.role ??
            'unknown',
        'servedPetId': device.servedPetId,
        'online': online,
        'active': active,
        'lastSeenMs': device.lastSeenMs,
      };
    }).toList(growable: false);
    final syncEventSizes = household.syncEvents.values
        .map((event) => utf8.encode(jsonEncode(event.toJson())).length)
        .toList(growable: false);
    final syncEventBytes = utf8
        .encode(jsonEncode(household.syncEvents.map(
          (syncId, event) => MapEntry(syncId, event.toJson()),
        )))
        .length;
    return {
      'householdId': household.id,
      'deviceCount': household.devices.length,
      'activeDeviceCount':
          devices.where((device) => device['active'] == true).length,
      'onlineDeviceCount':
          devices.where((device) => device['online'] == true).length,
      'syncEventCount': household.syncEvents.length,
      'syncEventBytes': syncEventBytes,
      'maxSyncEventBytes': syncEventSizes.isEmpty
          ? 0
          : syncEventSizes.reduce((a, b) => a > b ? a : b),
      'completedItemCount': household.completedItemKeys.length,
      'completedActionCount': household.completedActions.length,
      'appliedChecklistActionCount': household.appliedChecklistActions.length,
      'actionSyncEventIndexCount': household.actionSyncEventIds.length,
      'mutationSyncEventIndexCount': household.mutationSyncEventIds.length,
      'devices': devices,
    };
  }

  bool _hasDiagnosticsToken(Request request, String token) {
    final headerToken = request.headers['x-petnote-diagnostics-token'];
    if (headerToken == token) {
      return true;
    }
    final authorization = request.headers['authorization'];
    return authorization == 'Bearer $token';
  }

  static String? _normalizedDiagnosticsToken(String? constructorToken) {
    final value = constructorToken ??
        Platform.environment['PETNOTE_SYNC_DIAGNOSTICS_TOKEN'];
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  Future<void> close() async {
    await hub.closeAll();
    await store.flush();
  }
}
