package com.a1blowers.attendance

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.IBinder
import android.view.Gravity
import android.view.WindowManager
import android.widget.TextView

class TrackingBubbleService : Service() {
    companion object { const val SHOW = "SHOW_TRACKING_BUBBLE" }
    private var bubble: TextView? = null
    private var windowManager: WindowManager? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // START_STICKY may restart this service after the app task is swiped
        // away; recreate the bubble even when Android delivers a null intent.
        showBubble()
        return START_STICKY
    }
    private fun showBubble() {
        if (bubble != null) return
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val view = TextView(this).apply {
            text = "A1"
            setTextColor(Color.WHITE); textSize = 14f; gravity = Gravity.CENTER
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.rgb(190, 25, 35)); setStroke(3, Color.WHITE) }
            setOnClickListener { startActivity(packageManager.getLaunchIntentForPackage(packageName)?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
        val size = (56 * resources.displayMetrics.density).toInt()
        val params = WindowManager.LayoutParams(size, size, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, -3).apply { gravity = Gravity.TOP or Gravity.END; x = 18; y = 180 }
        windowManager?.addView(view, params); bubble = view
    }
    override fun onDestroy() { bubble?.let { windowManager?.removeView(it) }; bubble = null; super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null
}
