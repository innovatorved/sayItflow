package com.sayitflow.android.service

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sin

/**
 * Minimal, Text-Free Bottom Floating Waveform Pill (`TYPE_ACCESSIBILITY_OVERLAY`).
 *
 * - Appears ONLY when triggered via the hardware shortcut (never stays on screen when idle).
 * - Contains ZERO text — purely a compact `96dp × 28dp` Lo-Fi Paper & Ink capsule (`#FBF3E4`
 *   surface, `1.8dp` `#1B1712` border, `2.2dp` hard shadow) at the bottom center with a
 *   status indicator dot + 9 smooth acoustic waveform bars.
 * - Automatically disappears (`hide()`) as soon as dictation completes.
 */
class OverlayPillController(
    private val serviceContext: Context,
    private val onPillClick: (() -> Unit)? = null
) {

    enum class HudMode {
        LISTENING,
        TRANSCRIBING,
        COMPLETE,
        ALERT
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val windowManager = serviceContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    private var capsuleView: MinimalWaveformPillView? = null
    private var isAdded = false
    private var dismissRunnable: Runnable? = null

    fun showListening(foregroundPackage: String = "") {
        mainHandler.post {
            cancelPendingDismiss()
            val view = ensureAttached()
            view.setMode(HudMode.LISTENING)
        }
    }

    fun updateWaveform(levels: FloatArray) {
        mainHandler.post {
            if (!isAdded) return@post
            capsuleView?.updateAudioLevels(levels)
        }
    }

    fun showTranscribing(isColdWarmUp: Boolean = false) {
        mainHandler.post {
            cancelPendingDismiss()
            val view = ensureAttached()
            view.setMode(HudMode.TRANSCRIBING)
        }
    }

    fun showMessageAndAutoDismiss(
        message: String = "",
        subtitle: String = "",
        isError: Boolean = false,
        durationMs: Long = 380L
    ) {
        mainHandler.post {
            cancelPendingDismiss()
            if (!isError) {
                // Brief mint pulse or immediate hide
                val view = ensureAttached()
                view.setMode(HudMode.COMPLETE)
                val r = Runnable { hide() }
                dismissRunnable = r
                mainHandler.postDelayed(r, 320L)
            } else {
                val view = ensureAttached()
                view.setMode(HudMode.ALERT)
                val r = Runnable { hide() }
                dismissRunnable = r
                mainHandler.postDelayed(r, 550L)
            }
        }
    }

    fun hide() {
        mainHandler.post {
            cancelPendingDismiss()
            val view = capsuleView
            if (isAdded && view != null) {
                try {
                    windowManager.removeView(view)
                } catch (_: Exception) {
                }
                view.stopLoop()
                isAdded = false
            }
        }
    }

    private fun cancelPendingDismiss() {
        dismissRunnable?.let { mainHandler.removeCallbacks(it) }
        dismissRunnable = null
    }

    private fun ensureAttached(): MinimalWaveformPillView {
        var view = capsuleView
        if (view == null) {
            view = MinimalWaveformPillView(serviceContext).apply {
                setOnClickListener {
                    onPillClick?.invoke()
                }
            }
            capsuleView = view
        }

        if (!isAdded) {
            val params = WindowManager.LayoutParams(
                dpToPx(96f),
                dpToPx(28f),
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                x = 0
                y = dpToPx(20f)
            }
            try {
                windowManager.addView(view, params)
                isAdded = true
                view.startEntryAnimation()
            } catch (_: Exception) {
            }
        }

        view.startLoop()
        return view
    }

    private fun dpToPx(dp: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            serviceContext.resources.displayMetrics
        ).toInt()
    }

    private class MinimalWaveformPillView(context: Context) : View(context) {

        private val density = context.resources.displayMetrics.density

        private var mode: HudMode = HudMode.LISTENING

        private val numBars = 9
        private val targetBars = FloatArray(numBars) { 0.18f }
        private val smoothBars = FloatArray(numBars) { 0.18f }

        private var animPhase = 0f
        private var entryProgress = 1f
        private var frameAnimator: ValueAnimator? = null

        private val capsuleRect = RectF()
        private val shadowRect = RectF()
        private val barRect = RectF()

        private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = Color.parseColor("#1B1712")
        }
        private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = Color.parseColor("#FBF3E4")
        }
        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1.75f * density
            color = Color.parseColor("#1B1712")
        }
        private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        private val dotRingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1.25f * density
            color = Color.parseColor("#1B1712")
        }
        private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }

        fun setMode(newMode: HudMode) {
            mode = newMode
            invalidate()
        }

        fun updateAudioLevels(levels: FloatArray) {
            if (levels.isEmpty()) return
            for (i in 0 until numBars) {
                val srcIdx = (i * levels.size) / numBars
                val raw = levels[srcIdx.coerceIn(0, levels.lastIndex)].coerceIn(0.10f, 1.0f)
                val centerWeight = 1.0f - (abs(i - (numBars - 1) / 2f) / (numBars / 1.4f)) * 0.22f
                targetBars[i] = (raw * centerWeight).coerceIn(0.14f, 1.0f)
            }
        }

        fun startEntryAnimation() {
            entryProgress = 0f
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 130L
                interpolator = DecelerateInterpolator(1.8f)
                addUpdateListener {
                    entryProgress = it.animatedValue as Float
                    invalidate()
                }
                start()
            }
        }

        fun startLoop() {
            if (frameAnimator?.isRunning == true) return
            frameAnimator = ValueAnimator.ofFloat(0f, 1000f).apply {
                duration = 1000_000L
                repeatCount = ValueAnimator.INFINITE
                addUpdateListener {
                    animPhase += 0.14f
                    updateSmoothBars()
                    invalidate()
                }
                start()
            }
        }

        fun stopLoop() {
            frameAnimator?.cancel()
            frameAnimator = null
        }

        private fun updateSmoothBars() {
            when (mode) {
                HudMode.LISTENING -> {
                    for (i in 0 until numBars) {
                        val idleBreath = 0.16f + 0.05f * sin(animPhase + i * 0.5f).toFloat()
                        val target = max(targetBars[i], idleBreath)
                        smoothBars[i] += (target - smoothBars[i]) * 0.40f
                    }
                }
                HudMode.TRANSCRIBING -> {
                    for (i in 0 until numBars) {
                        val wave = 0.20f + 0.58f * ((sin(animPhase * 2.2 - i * 0.55) + 1.0) * 0.5).toFloat()
                        smoothBars[i] += (wave - smoothBars[i]) * 0.32f
                    }
                }
                HudMode.COMPLETE -> {
                    for (i in 0 until numBars) {
                        smoothBars[i] += (0.55f - smoothBars[i]) * 0.35f
                    }
                }
                HudMode.ALERT -> {
                    for (i in 0 until numBars) {
                        smoothBars[i] += (0.20f - smoothBars[i]) * 0.30f
                    }
                }
            }
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0f || h <= 0f) return

            val pad = 1.5f * density
            val shadowOffset = 2.0f * density
            val scale = 0.94f + 0.06f * entryProgress
            canvas.save()
            canvas.scale(scale, scale, w / 2f, h / 2f)

            capsuleRect.set(pad, pad, w - pad - shadowOffset, h - pad - shadowOffset)
            shadowRect.set(
                capsuleRect.left + shadowOffset,
                capsuleRect.top + shadowOffset,
                capsuleRect.right + shadowOffset,
                capsuleRect.bottom + shadowOffset
            )
            val radius = capsuleRect.height() / 2f

            // Hard offset Lo-Fi Paper & Ink shadow + warm cream surface + crisp ink border
            canvas.drawRoundRect(shadowRect, radius, radius, shadowPaint)
            canvas.drawRoundRect(capsuleRect, radius, radius, bgPaint)
            canvas.drawRoundRect(capsuleRect, radius, radius, borderPaint)

            val dotColor = when (mode) {
                HudMode.LISTENING -> Color.parseColor("#FF3B2F")
                HudMode.TRANSCRIBING -> Color.parseColor("#FFCE4A")
                HudMode.COMPLETE -> Color.parseColor("#36C2AD")
                HudMode.ALERT -> Color.parseColor("#FF3B2F")
            }

            val cy = capsuleRect.centerY()
            val cx = capsuleRect.left + 13.5f * density
            dotPaint.color = dotColor
            canvas.drawCircle(cx, cy, 4.0f * density, dotPaint)
            canvas.drawCircle(cx, cy, 4.0f * density, dotRingPaint)

            // 9 pure waveform bars (zero text)
            val barW = 2.6f * density
            val barGap = 3.2f * density
            val totalBarsW = numBars * barW + (numBars - 1) * barGap
            val availableRight = capsuleRect.right - 11f * density
            val barsStartX = availableRight - totalBarsW
            val maxBarH = 13.5f * density

            for (i in 0 until numBars) {
                val level = smoothBars[i].coerceIn(0.14f, 1.0f)
                val barH = max(3.2f * density, level * maxBarH)
                val bx = barsStartX + i * (barW + barGap)
                barPaint.color = when (mode) {
                    HudMode.LISTENING -> if (level > 0.34f) Color.parseColor("#FF3B2F") else Color.parseColor("#1B1712")
                    HudMode.TRANSCRIBING -> Color.parseColor("#1B1712")
                    HudMode.COMPLETE -> Color.parseColor("#36C2AD")
                    HudMode.ALERT -> Color.parseColor("#FF3B2F")
                }
                barRect.set(bx, cy - barH / 2f, bx + barW, cy + barH / 2f)
                canvas.drawRoundRect(barRect, barW / 2f, barW / 2f, barPaint)
            }

            canvas.restore()
        }
    }
}
