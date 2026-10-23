package com.a1blowers.attendance

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.a1blowers.attendance/overlay"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canDrawOverlays" -> result.success(Settings.canDrawOverlays(this))
                    "openOverlaySettings" -> {
                        startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")))
                        result.success(null)
                    }
                    "showTrackingBubble" -> {
                        if (Settings.canDrawOverlays(this)) startService(Intent(this, TrackingBubbleService::class.java).setAction(TrackingBubbleService.SHOW))
                        result.success(Settings.canDrawOverlays(this))
                    }
                    "hideTrackingBubble" -> {
                        stopService(Intent(this, TrackingBubbleService::class.java)); result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

}
