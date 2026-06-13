import 'package:web_socket_channel/web_socket_channel.dart';

/// 按 household/device 维护活动连接，提供定向发送。
class WsHub {
  final Map<String, Map<String, Set<WebSocketChannel>>> _connections = {};
  final Map<String, Map<String, String>> _roles = {};

  void register(
    String householdId,
    String deviceId,
    WebSocketChannel channel, {
    String? role,
  }) {
    _connections
        .putIfAbsent(householdId, () => {})
        .putIfAbsent(deviceId, () => <WebSocketChannel>{})
        .add(channel);
    if (role != null) {
      _roles.putIfAbsent(householdId, () => {})[deviceId] = role;
    }
  }

  void unregister(
      String householdId, String deviceId, WebSocketChannel channel) {
    final household = _connections[householdId];
    if (household == null) {
      return;
    }
    final channels = household[deviceId];
    if (channels != null && channels.remove(channel)) {
      if (channels.isNotEmpty) {
        return;
      }
      household.remove(deviceId);
      _roles[householdId]?.remove(deviceId);
      if (household.isEmpty) _connections.remove(householdId);
      if (_roles[householdId]?.isEmpty ?? false) _roles.remove(householdId);
    }
  }

  bool isOnline(String householdId, String deviceId) =>
      _connections[householdId]?.containsKey(deviceId) ?? false;

  String? roleFor(String householdId, String deviceId) =>
      _roles[householdId]?[deviceId];

  void sendTo(String householdId, String deviceId, String encodedMessage) {
    for (final channel in _connections[householdId]?[deviceId] ??
        const Iterable<WebSocketChannel>.empty()) {
      channel.sink.add(encodedMessage);
    }
  }

  Iterable<String> onlineDevices(String householdId) =>
      _connections[householdId]?.keys ?? const Iterable.empty();

  Future<void> closeAll() async {
    final channels = _connections.values
        .expand((household) => household.values)
        .expand((channels) => channels)
        .toList(growable: false);
    for (final channel in channels) {
      await channel.sink.close();
    }
    _connections.clear();
    _roles.clear();
  }
}
