import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:petnote/app/harmony_ohos_view.dart';

enum RtcVideoViewRole { local, remote }

class RtcVideoView extends StatelessWidget {
  const RtcVideoView.local({super.key})
      : role = RtcVideoViewRole.local,
        remoteUserId = null;

  const RtcVideoView.remote({
    super.key,
    required this.remoteUserId,
  }) : role = RtcVideoViewRole.remote;

  static const String viewType = 'petnote/rtc_video_view';

  final RtcVideoViewRole role;
  final String? remoteUserId;

  Map<String, Object?> get _creationParams => {
        'role': role.name,
        if (remoteUserId != null) 'remoteUserId': remoteUserId,
      };

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform.name == 'ohos') {
      return HarmonyOhosView(
        viewType: viewType,
        layoutDirection: Directionality.of(context),
        creationParams: _creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          viewType: viewType,
          creationParams: _creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: viewType,
          creationParams: _creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        );
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return const ColoredBox(color: Colors.black);
    }
  }
}
