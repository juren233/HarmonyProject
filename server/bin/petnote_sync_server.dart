import 'dart:io';

import 'package:petnote_sync_server/src/server_app.dart';

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8787;
  final dataDir = Directory(Platform.environment['DATA_DIR'] ?? './data')..createSync(recursive: true);
  final app = SyncServerApp(dataDirectory: dataDir);
  final server = await app.serve(address: InternetAddress.anyIPv4, port: port);
  stdout.writeln('petnote sync server listening on :${server.port}');
}
