package com.krustykrab.petnote

import android.content.Context
import android.widget.FrameLayout
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class PetNoteRtcVideoViewFactory(
    private val rtcBridge: PetNoteRtcBridge,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<Any, Any>()
        val role = params["role"] as? String ?: "remote"
        val remoteUserId = params["remoteUserId"] as? String
        return PetNoteRtcVideoPlatformView(context, rtcBridge, role, remoteUserId)
    }
}

private class PetNoteRtcVideoPlatformView(
    context: Context,
    private val rtcBridge: PetNoteRtcBridge,
    private val role: String,
    private val remoteUserId: String?,
) : PlatformView {
    private val container = FrameLayout(context)

    init {
        rtcBridge.bindVideoView(role, remoteUserId, container)
    }

    override fun getView(): FrameLayout = container

    override fun dispose() {
        rtcBridge.unbindVideoView(container)
    }
}
