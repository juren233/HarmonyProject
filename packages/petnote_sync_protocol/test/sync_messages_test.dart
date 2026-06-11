import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('消息 JSON 编解码往返', () {
    final message = SyncMessage(SyncMessageTypes.snapshotPush, {
      'version': 3,
      'ciphertext': 'abc',
    });
    final decoded = SyncMessage.decode(message.encode());
    expect(decoded.type, SyncMessageTypes.snapshotPush);
    expect(decoded.payload['version'], 3);
  });

  test('PetAction 编解码往返', () {
    final action = PetAction(kind: PetActionKind.markDone, sourceType: 'todo', itemId: 't1');
    final decoded = PetAction.fromJson(action.toJson());
    expect(decoded.kind, PetActionKind.markDone);
    expect(decoded.sourceType, 'todo');
    expect(decoded.itemId, 't1');
  });

  test('非法 JSON 抛 FormatException', () {
    expect(() => SyncMessage.decode('not json'), throwsFormatException);
  });
}
