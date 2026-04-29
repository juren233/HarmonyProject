import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PetNoteAppDirectory {
  const PetNoteAppDirectory._();

  static const MethodChannel _channel = MethodChannel(_channelName);
  static const String _channelName = 'petnote/app_directory';

  static Future<String?> load() async {
    try {
      return await _channel.invokeMethod<String>('getApplicationSupportPath');
    } on FlutterError catch (error) {
      if (error.toString().contains('Binding has not yet been initialized')) {
        return null;
      }
      debugPrint('PetNote app directory channel failed: $error');
    } on MissingPluginException catch (error) {
      debugPrint('PetNote app directory channel is missing: $error');
    } on PlatformException catch (error) {
      debugPrint('PetNote app directory channel failed: ${error.message}');
    }
    return null;
  }
}
