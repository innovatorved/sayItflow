package com.sayitflow.android.service

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import com.sayitflow.android.audio.AudioCaptureManager

/**
 * Renders the signature SayItFlow Monochrome Studio floating pill at the top of the screen
 * during push-to-talk dictation using `TYPE_ACCESSIBILITY_OVERLAY`.
 */
class OverlayPillController(private val serviceContext: Context) {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val windowManager = serviceContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    private var pillContainer: LinearLayout? = null
    private var statusDot: View? = null
    private var statusText: TextView? = null
    private val barViews = ArrayList<View>(AudioCaptureManager.WAVEFORM_BARS)
    private var isAdded = false

    fun showListening() {
        mainHandler.post {
            ensurePillAttached()
            statusDot?.background = circleDrawable(Color.parseColor("#FAFAFA"))
            statusText?.text = "Listening"
        }
    }

    fun updateWaveform(levels: FloatArray) {
        mainHandler.post {
            if (!isAdded || barViews.isEmpty()) return@post
            for (i in 0 until minOf(levels.size, barViews.size)) {
                val bar = barViews[i]
                val heightDp = 4f + (levels[i].coerceIn(0.1f, 1.0f) * 14f)
                val lp = bar.layoutParams as LinearLayout.LayoutParams
                lp.height = dpToPx(heightDp)
                bar.layoutParams = lp
            }
        }
    }

    fun showTranscribing() {
        mainHandler.post {
            ensurePillAttached()
            statusDot?.background = circleDrawable(Color.parseColor("#A1A1AA"))
            statusText?.text = "Voz + S1-mini..."
            for (bar in barViews) {
                val lp = bar.layoutParams as LinearLayout.LayoutParams
                lp.height = dpToPx(6f)
                bar.layoutParams = lp
            }
        }
    }

    fun showMessageAndAutoDismiss(message: String, durationMs: Long = 1100L) {
        mainHandler.post {
            ensurePillAttached()
            statusDot?.background = circleDrawable(Color.parseColor("#E4E4E7"))
            statusText?.text = message
            mainHandler.postDelayed({ hide() }, durationMs)
        }
    }

    fun hide() {
        mainHandler.post {
            if (isAdded && pillContainer != null) {
                try {
                    windowManager.removeView(pillContainer)
                } catch (_: Exception) {
                }
                isAdded = false
            }
        }
    }

    private fun ensurePillAttached() {
        if (pillContainer == null) {
            pillContainer = buildPillView()
        }
        if (!isAdded) {
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                y = dpToPx(48f)
            }
            try {
                windowManager.addView(pillContainer, params)
                isAdded = true
            } catch (_: Exception) {
            }
        }
    }

    private fun buildPillView(): LinearLayout {
        val root = LinearLayout(serviceContext).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dpToPx(16f), dpToPx(10f), dpToPx(16f), dpToPx(10f))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(24f).toFloat()
                setColor(Color.parseColor("#F209090B"))
                setStroke(dpToPx(1f), Color.parseColor("#3F3F46"))
            }
            elevation = dpToPx(8f).toFloat()
        }

        val dot = View(serviceContext).apply {
            layoutParams = LinearLayout.LayoutParams(dpToPx(8f), dpToPx(8f)).apply {
                marginEnd = dpToPx(10f)
            }
            background = circleDrawable(Color.parseColor("#FAFAFA"))
        }
        statusDot = dot
        root.addView(dot)

        val label = TextView(serviceContext).apply {
            text = "Listening"
            setTextColor(Color.parseColor("#FAFAFA"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = dpToPx(12f)
            }
        }
        statusText = label
        root.addView(label)

        val barsWrap = LinearLayout(serviceContext).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                dpToPx(18f)
            )
        }
        barViews.clear()
        for (i in 0 until AudioCaptureManager.WAVEFORM_BARS) {
            val bar = View(serviceContext).apply {
                layoutParams = LinearLayout.LayoutParams(dpToPx(3f), dpToPx(6f)).apply {
                    if (i < AudioCaptureManager.WAVEFORM_BARS - 1) {
                        marginEnd = dpToPx(3f)
                    }
                }
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dpToPx(2f).toFloat()
                    setColor(Color.parseColor("#FAFAFA"))
                }
            }
            barViews.add(bar)
            barsWrap.addView(bar)
        }
        root.addView(barsWrap)
        return root
    }

    private fun circleDrawable(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
        }
    }

    private fun dpToPx(dp: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            serviceContext.resources.displayMetrics
        ).toInt()
    }
}
