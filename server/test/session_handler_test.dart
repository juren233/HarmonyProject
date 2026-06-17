import 'dart:async';
import 'dart:io';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:petnote_sync_server/src/server_app.dart';
import 'package:petnote_sync_server/src/session_handler.dart';
import 'package:test/test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('bind 后同一连接上的消息会按顺序串行进入 handle', () async {
    final input = StreamController<dynamic>(sync: true);
    final output = StreamController<dynamic>.broadcast();
    final channel =
        _FakeWebSocketChannel(input.stream, _FakeWebSocketSink(output.sink));
    final app = SyncServerApp(
      dataDirectory: Directory.systemTemp.createTempSync('petnote_session_'),
    );
    final firstCanFinish = Completer<void>();
    final entered = <String>[];
    final handler = _SerialSpySessionHandler(
      app: app,
      channel: channel,
      firstCanFinish: firstCanFinish,
      entered: entered,
    )..bind();

    input
      ..add(const SyncMessage('first', {}).encode())
      ..add(const SyncMessage('second', {}).encode());

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(entered, ['first']);

    firstCanFinish.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(entered, ['first', 'second']);
    await input.close();
    await output.close();
    await app.close();
  });
}

class _SerialSpySessionHandler extends SessionHandler {
  _SerialSpySessionHandler({
    required super.app,
    required super.channel,
    required this.firstCanFinish,
    required this.entered,
  });

  final Completer<void> firstCanFinish;
  final List<String> entered;

  @override
  Future<void> handle(SyncMessage message) async {
    entered.add(message.type);
    if (message.type == 'first') {
      await firstCanFinish.future;
    }
  }
}

class _FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  _FakeWebSocketChannel(this.stream, this.sink);

  @override
  final Stream<dynamic> stream;

  @override
  final WebSocketSink sink;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

class _FakeWebSocketSink implements WebSocketSink {
  _FakeWebSocketSink(this._sink);

  final StreamSink<dynamic> _sink;

  @override
  Future<void> addStream(Stream<dynamic> stream) => _sink.addStream(stream);

  @override
  void add(dynamic data) => _sink.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);

  @override
  Future<void> close([int? closeCode, String? closeReason]) => _sink.close();

  @override
  Future get done => _sink.done;
}
