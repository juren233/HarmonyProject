import 'package:flutter/material.dart';
import 'package:petnote/app/remote_video_call_page.dart';
import 'package:petnote/state/petnote_store.dart';

enum RemoteVideoMode { call, watch }

class RemoteVideoPillButton extends StatelessWidget {
  const RemoteVideoPillButton({super.key, required this.pet});

  // 连接对象固定为爱宠页当前展示的宠物。
  final Pet pet;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('remote_video_pill'),
      color: const Color(0xFFF2A65A),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _showOptions(context),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_rounded, size: 18, color: Colors.white),
              SizedBox(width: 6),
              Text(
                '远程视频',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('remote_video_option_call'),
              leading: const Icon(Icons.video_call_rounded),
              title: const Text('视频通话'),
              onTap: () =>
                  _openCallPage(context, sheetContext, RemoteVideoMode.call),
            ),
            ListTile(
              key: const ValueKey('remote_video_option_watch'),
              leading: const Icon(Icons.visibility_rounded),
              title: const Text('先看看它'),
              onTap: () =>
                  _openCallPage(context, sheetContext, RemoteVideoMode.watch),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openCallPage(
    BuildContext context,
    BuildContext sheetContext,
    RemoteVideoMode mode,
  ) {
    Navigator.of(sheetContext).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => RemoteVideoCallPage(mode: mode, pet: pet),
      ),
    );
  }
}
