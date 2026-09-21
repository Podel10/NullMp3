package com.nullmp3.nullmp3

import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.EventChannel
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

object AudioHalo : EventChannel.StreamHandler {
    private const val TAG = "NullMP3"
    private const val BANDS = 32
    private const val HISTORY = 20
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()
    private var visualizer: Visualizer? = null
    private var sink: EventChannel.EventSink? = null
    private var sessionId = 0
    private var lastBass = 0.0
    private var lastBeatAt = 0L
    private var lastFftAt = 0L
    private val bassHistory = DoubleArray(HISTORY)
    private var bassCount = 0
    private var bassIndex = 0
    private val smoothPeaks = DoubleArray(BANDS)

    fun start(id: Int, force: Boolean = false): Boolean {
        synchronized(lock) {
            if (id <= 0) return false
            if (!force && visualizer != null && sessionId == id) {
                val rebound = try {
                    bindCaptureLocked(visualizer!!)
                } catch (_: Exception) {
                    false
                }
                if (rebound) return true
            }
            if (force) {
                // Prefer rebind; hard recreate is a last resort for a wedged capture.
                val current = visualizer
                if (current != null) {
                    val rebound = try {
                        bindCaptureLocked(current)
                    } catch (_: Exception) {
                        false
                    }
                    if (rebound) return true
                }
                Log.w(TAG, "halo force recreate session=$id")
                stopCaptureLocked()
            } else if (visualizer != null && sessionId == id) {
                return false
            } else {
                stopCaptureLocked()
            }
            return attachLocked(id)
        }
    }

    fun pause() {
        synchronized(lock) {
            try {
                // Stop FFT without dropping the effect. Passing a null listener
                // while enabled kills capture on several OEMs until recreate.
                visualizer?.setDataCaptureListener(captureListener, 0, false, false)
            } catch (_: Exception) {
            }
            // Keep the effect attached. enabled=false / release mutes ExoPlayer.
        }
    }

    fun stop() {
        synchronized(lock) {
            sessionId = 0
            stopCaptureLocked()
        }
    }

    private fun attachLocked(id: Int): Boolean {
        return try {
            val vis = Visualizer(id)
            val range = Visualizer.getCaptureSizeRange()
            vis.captureSize = max(range[0], min(1024, range[1]))
            try {
                vis.scalingMode = Visualizer.SCALING_MODE_NORMALIZED
            } catch (_: Exception) {
            }
            visualizer = vis
            sessionId = id
            resetEnvelope()
            bindCaptureLocked(vis)
        } catch (error: Throwable) {
            Log.w(TAG, "halo visualizer failed session=$id", error)
            stopCaptureLocked()
            false
        }
    }

    private fun resetEnvelope() {
        lastBass = 0.0
        lastBeatAt = 0L
        lastFftAt = 0L
        bassCount = 0
        bassIndex = 0
        bassHistory.fill(0.0)
        smoothPeaks.fill(0.0)
    }

    private fun mag(fft: ByteArray, bin: Int): Double {
        if (bin <= 0) return 0.0
        val i = bin * 2
        if (i + 1 >= fft.size) return 0.0
        return hypot(fft[i].toDouble(), fft[i + 1].toDouble())
    }

    private fun compress(raw: Double): Double {
        return (ln(1.0 + raw.coerceAtLeast(0.0) * 22.0) / ln(23.0)).coerceIn(0.0, 1.0)
    }

    private fun compressBass(raw: Double): Double {
        return (ln(1.0 + raw.coerceAtLeast(0.0) * 36.0) / ln(37.0)).coerceIn(0.0, 1.0)
    }

    private fun emitFft(fft: ByteArray) {
        val bins = fft.size / 2
        if (bins < 8) return
        val usable = max(8, bins - 1)
        val peaks = ArrayList<Double>(BANDS)
        var energy = 0.0
        var maxPeak = 0.0
        for (b in 0 until BANDS) {
            val t0 = b / BANDS.toDouble()
            val t1 = (b + 1) / BANDS.toDouble()
            val start = (1 + t0 * t0 * (usable - 2)).toInt().coerceIn(1, usable - 1)
            val end = (1 + t1 * t1 * (usable - 2)).toInt().coerceIn(start + 1, usable)
            var sum = 0.0
            var count = 0
            for (i in start until end) {
                sum += mag(fft, i)
                count++
            }
            val n = compress(if (count == 0) 0.0 else sum / count / 96.0)
            peaks.add(n)
            energy += n
            maxPeak = max(maxPeak, n)
        }
        val norm = if (maxPeak > 0.05) maxPeak else 1.0
        for (i in 0 until BANDS) {
            val shaped = (peaks[i] / norm).coerceAtMost(1.0).pow(0.5)
            smoothPeaks[i] = smoothPeaks[i] * 0.26 + shaped * 0.74
            peaks[i] = smoothPeaks[i]
        }
        var bass = 0.0
        var bassWeight = 0.0
        val bassEnd = min(16, usable)
        for (i in 1 until bassEnd) {
            val t = (i - 1) / bassEnd.toDouble()
            val w = (1.0 - t).pow(1.7)
            bass += mag(fft, i) * w
            bassWeight += w
        }
        bass = compressBass(bass / max(1.0, bassWeight) / 72.0)
        emit(peaks, energy / BANDS, bass)
    }

    private fun emitWave(waveform: ByteArray) {
        var sum = 0.0
        val chunk = max(1, waveform.size / BANDS)
        val peaks = ArrayList<Double>(BANDS)
        var maxPeak = 0.0
        for (b in 0 until BANDS) {
            var amp = 0
            val start = b * chunk
            val end = min(waveform.size, start + chunk)
            for (j in start until end) {
                amp = max(amp, kotlin.math.abs((waveform[j].toInt() and 0xFF) - 128))
            }
            val n = compress(amp / 96.0)
            peaks.add(n)
            sum += n
            maxPeak = max(maxPeak, n)
        }
        val norm = if (maxPeak > 0.05) maxPeak else 1.0
        for (i in 0 until BANDS) {
            val shaped = (peaks[i] / norm).pow(0.5)
            smoothPeaks[i] = smoothPeaks[i] * 0.36 + shaped * 0.64
            peaks[i] = smoothPeaks[i]
        }
        emit(peaks, sum / BANDS, sum / BANDS)
    }

    private fun emit(peaks: ArrayList<Double>, energy: Double, bass: Double) {
        val out = sink ?: return
        bassHistory[bassIndex] = bass
        bassIndex = (bassIndex + 1) % HISTORY
        if (bassCount < HISTORY) bassCount++
        var mean = 0.0
        for (i in 0 until bassCount) mean += bassHistory[i]
        mean /= bassCount
        var variance = 0.0
        for (i in 0 until bassCount) {
            val d = bassHistory[i] - mean
            variance += d * d
        }
        val std = sqrt(variance / bassCount)
        val flux = max(0.0, bass - lastBass)
        val primed = bassCount >= HISTORY
        val now = SystemClock.uptimeMillis()
        val beat = primed &&
            flux > std * 0.85 + 0.012 &&
            bass > mean + std * 0.22 &&
            bass > 0.04 &&
            now - lastBeatAt > 150
        if (beat) lastBeatAt = now
        lastBass = bass
        val strength = if (!primed || std < 0.005) {
            0.0
        } else {
            ((bass - mean) / (std * 1.7 + 0.028)).coerceIn(0.0, 1.0)
        }
        val payload = hashMapOf(
            "peaks" to peaks,
            "energy" to energy,
            "bass" to bass,
            "beat" to beat,
            "strength" to if (beat) max(strength, 0.55) else strength,
            "ready" to primed,
        )
        mainHandler.post {
            try {
                out.success(payload)
            } catch (_: Exception) {
            }
        }
    }

    private val captureListener = object : Visualizer.OnDataCaptureListener {
        override fun onWaveFormDataCapture(
            visualizer: Visualizer?,
            waveform: ByteArray?,
            samplingRate: Int,
        ) {
            if (waveform == null || waveform.isEmpty()) return
            if (SystemClock.uptimeMillis() - lastFftAt < 220) return
            emitWave(waveform)
        }

        override fun onFftDataCapture(
            visualizer: Visualizer?,
            fft: ByteArray?,
            samplingRate: Int,
        ) {
            if (fft == null || fft.size < 8) return
            lastFftAt = SystemClock.uptimeMillis()
            emitFft(fft)
        }
    }

    private fun bindCaptureLocked(vis: Visualizer): Boolean {
        val rate = max(Visualizer.getMaxCaptureRate() / 4, 10000)
        // Re-enable FFT in place. pause() leaves the effect attached; clearing
        // the listener while enabled kills capture on several OEMs.
        return try {
            vis.setDataCaptureListener(captureListener, rate, false, true)
            if (!vis.enabled) vis.enabled = true
            vis.enabled
        } catch (_: Exception) {
            false
        }
    }

    private fun stopCaptureLocked() {
        try {
            visualizer?.enabled = false
        } catch (_: Exception) {
        }
        try {
            visualizer?.release()
        } catch (_: Exception) {
        }
        visualizer = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        synchronized(lock) {
            val vis = visualizer
            if (vis != null && sessionId > 0) {
                try {
                    bindCaptureLocked(vis)
                } catch (_: Exception) {
                }
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        // Detach capture only. Releasing the effect mutes ExoPlayer.
        sink = null
        pause()
    }
}
