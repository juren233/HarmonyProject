import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('同一配对码与盐派生的密钥可以加解密往返', () async {
    final salt = SyncCrypto.generateSaltBase64();
    final a = await SyncCrypto.deriveFromPairingCode(code: '123456', saltBase64: salt);
    final b = await SyncCrypto.deriveFromPairingCode(code: '123456', saltBase64: salt);
    final cipher = await a.encryptString('{"pets":[]}');
    expect(await b.decryptString(cipher), '{"pets":[]}');
  });

  test('错误配对码解密失败', () async {
    final salt = SyncCrypto.generateSaltBase64();
    final a = await SyncCrypto.deriveFromPairingCode(code: '123456', saltBase64: salt);
    final wrong = await SyncCrypto.deriveFromPairingCode(code: '654321', saltBase64: salt);
    final cipher = await a.encryptString('secret');
    expect(() => wrong.decryptString(cipher), throwsA(anything));
  });

  test('密钥可导出并恢复', () async {
    final salt = SyncCrypto.generateSaltBase64();
    final a = await SyncCrypto.deriveFromPairingCode(code: '123456', saltBase64: salt);
    final restored = SyncCrypto.fromKeyBase64(await a.exportKeyBase64());
    expect(await restored.decryptString(await a.encryptString('hi')), 'hi');
  });
}
