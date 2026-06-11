import 'package:web_socket_channel/web_socket_channel.dart';

/// 按 household/device 维护活动连接，提供定向发送。
class WsHub {
  final Map<String, Map<String, WebSocketChannel>> _connections = {};

  void register(String householdId, String deviceId, WebSocketChannel channel) {
    _connections.putIfAbsent(householdId, () => {})[deviceId] = channel;
  }

  void unregister(String householdId, String deviceId, WebSocketChannel channel) {
    final household = _connections[householdId];
    if (household != null && identical(household[deviceId], channel)) {
      household.remove(deviceId);
      if (household.isEmpty) _connections.remove(householdId);
    }
  }

  bool isOnline(String householdId, String deviceId) =>
      _connections[householdId]?.containsKey(deviceId) ?? false;

  void sendTo(String householdId, String deviceId, String encodedMessage) {
    _connections[householdId]?[deviceId]?.sink.add(encodedMessage);
  }

  Iterable<String> onlineDevices(String householdId) =>
      _connections[householdId]?.keys ?? const Iterable.empty();

  Future<void> closeAll() async {
    for (final household in _connections.values) {
      for (final channel in household.values) {
        await channel.sink.close();
      }
    }
    _connections.clear();
  }
}
