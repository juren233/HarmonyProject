import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// 同步数据端到端加密：HKDF-SHA256 从配对码+盐派生 AES-256-GCM 密钥。
class SyncCrypto {
  SyncCrypto(this._secretKey);

  final SecretKey _secretKey;
  static final AesGcm _aes = AesGcm.with256bits();

  static String generateSaltBase64() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  static Future<SyncCrypto> deriveFromPairingCode({
    required String code,
    required String saltBase64,
  }) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final key = await hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(code)),
      nonce: base64Decode(saltBase64),
      info: utf8.encode('petnote-sync-v1'),
    );
    return SyncCrypto(key);
  }

  static SyncCrypto fromKeyBase64(String keyBase64) {
    return SyncCrypto(SecretKey(base64Decode(keyBase64)));
  }

  Future<String> exportKeyBase64() async {
    return base64Encode(await _secretKey.extractBytes());
  }

  Future<String> encryptString(String plaintext) async {
    final box = await _aes.encrypt(utf8.encode(plaintext), secretKey: _secretKey);
    return base64Encode(box.concatenation());
  }

  Future<String> decryptString(String payloadBase64) async {
    final box = SecretBox.fromConcatenation(
      base64Decode(payloadBase64),
      nonceLength: 12,
      macLength: 16,
    );
    return utf8.decode(await _aes.decrypt(box, secretKey: _secretKey));
  }
}
