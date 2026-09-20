package com.nullmp3.nullmp3

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.media.Image
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt

/// Progress for the video to GIF tool, so a long clip shows numbers instead of
/// a spinner that looks stuck.
object GifProgress : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var lastAt = 0L

    fun send(stage: String, done: Int, total: Int) {
        val target = sink ?: return
        val now = SystemClock.elapsedRealtime()
        if (done < total && now - lastAt < 80) return
        lastAt = now
        val payload = hashMapOf<String, Any?>("stage" to stage, "done" to done, "total" to total)
        mainHandler.post { target.success(payload) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }
}

/// Decoding, quantising and GIF encoding all happen here. The Dart side used to
/// do the encoding, which took minutes for anything longer than a couple of
/// seconds.
object VideoGif {
    private const val TAG = "NullMP3"
    private const val MAX_FRAMES = 450
    private const val BUDGET_MS = 180_000L
    private const val MAX_EDGE = 1080

    fun info(context: Context, path: String): HashMap<String, Any?> {
        val retriever = open(context, path)
        try {
            val durationMs = meta(retriever, MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            var width = meta(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            var height = meta(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = meta(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) {
                val swap = width
                width = height
                height = swap
            }
            return hashMapOf(
                "durationMs" to durationMs,
                "width" to width,
                "height" to height,
                "rotation" to rotation,
            )
        } finally {
            release(retriever)
        }
    }

    fun poster(context: Context, path: String, maxSide: Int = 360): ByteArray? {
        val retriever = open(context, path)
        try {
            val bitmap = try {
                retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    ?: retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST)
                    ?: retriever.getFrameAtTime(1_000_000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    ?: retriever.frameAtTime
            } catch (_: Exception) {
                null
            } ?: return null
            val scaled = scaleToMax(bitmap, maxSide.coerceIn(64, 720))
            val out = ByteArrayOutputStream()
            return try {
                scaled.compress(Bitmap.CompressFormat.JPEG, 82, out)
                out.toByteArray()
            } finally {
                if (scaled !== bitmap) scaled.recycle()
                bitmap.recycle()
            }
        } finally {
            release(retriever)
        }
    }

    fun make(
        context: Context,
        path: String,
        startMs: Long,
        endMs: Long,
        fps: Int,
        maxWidth: Int,
        name: String,
    ): HashMap<String, Any?> {
        val clip = info(context, path)
        val durationMs = clip["durationMs"] as? Long ?: 0L
        val rotation = clip["rotation"] as? Int ?: 0
        val from = startMs.coerceAtLeast(0)
        val to = if (durationMs > 0) endMs.coerceIn(from + 200, durationMs) else endMs.coerceAtLeast(from + 200)
        val span = to - from
        val rate = fps.coerceIn(2, 30)
        val wanted = ((span * rate) / 1000L).toInt().coerceIn(2, MAX_FRAMES)
        val size = scaledSize(clip["width"] as? Int ?: 0, clip["height"] as? Int ?: 0, maxWidth)
        val dstW = size.first
        val dstH = size.second
        val writer = GifWriter(dstW, dstH)
        val deadline = SystemClock.elapsedRealtime() + BUDGET_MS
        val sampler = Sampler(dstW, dstH, rotation)
        val pixels = IntArray(dstW * dstH)
        val samples = IntArray(96_000)
        var sampleCount = 0
        val counted = walk(context, path, from * 1000, to * 1000, wanted, deadline, sampler) { _, ordinal ->
            sampler.copyInto(pixels)
            val stride = max(1, pixels.size / 1600)
            var i = (ordinal * 13) % stride
            while (i < pixels.size && sampleCount < samples.size) {
                samples[sampleCount++] = pixels[i]
                i += stride
            }
            GifProgress.send("scan", ordinal + 1, wanted)
        }

        if (counted >= 2) {
            writer.buildPalette(samples, sampleCount)
            val total = counted
            walk(context, path, from * 1000, to * 1000, wanted, deadline, sampler) { _, ordinal ->
                sampler.copyInto(pixels)
                writer.addFrame(pixels)
                GifProgress.send("encode", ordinal + 1, total)
            }
        }

        if (writer.frames < 2) {
            // Some clips refuse to decode in buffer mode; fall back to stills.
            stills(context, path, from, to, dstW, dstH, writer, wanted)
        }
        if (writer.frames < 2) throw IllegalStateException("no_frames")

        val delayCs = (span.toDouble() / writer.frames / 10.0).roundToInt()
        val bytes = writer.finish(delayCs)
        GifProgress.send("save", 1, 1)
        val cached = cache(context, bytes, name)
        val saved = save(context, bytes, name)
        Log.i(TAG, "gif ${writer.frames} frames ${bytes.size / 1024}KB -> $saved")
        return hashMapOf(
            "path" to saved,
            "file" to cached,
            "frames" to writer.frames,
            "size" to bytes.size,
            "width" to dstW,
            "height" to dstH,
        )
    }

    /// Walks the clip once, handing [onFrame] evenly spaced frames. Sequential
    /// decoding beats seeking per frame by a wide margin.
    private fun walk(
        context: Context,
        path: String,
        startUs: Long,
        endUs: Long,
        wanted: Int,
        deadline: Long,
        sampler: Sampler,
        onFrame: (Image, Int) -> Unit,
    ): Int {
        val extractor = MediaExtractor()
        try {
            if (path.startsWith("content:")) {
                extractor.setDataSource(context, Uri.parse(path), null)
            } else {
                extractor.setDataSource(path)
            }
        } catch (error: Exception) {
            extractor.release()
            Log.w(TAG, "gif extractor failed", error)
            return 0
        }
        var track = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val candidate = extractor.getTrackFormat(i)
            if (candidate.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true) {
                track = i
                format = candidate
                break
            }
        }
        val mime = format?.getString(MediaFormat.KEY_MIME)
        if (track < 0 || format == null || mime == null) {
            extractor.release()
            return 0
        }
        extractor.selectTrack(track)
        sampler.configure(format)
        val codec = try {
            MediaCodec.createDecoderByType(mime).apply {
                configure(format, null, null, 0)
                start()
            }
        } catch (error: Exception) {
            extractor.release()
            Log.w(TAG, "gif decoder failed", error)
            return 0
        }

        var delivered = 0
        try {
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val info = MediaCodec.BufferInfo()
            val step = ((endUs - startUs).toDouble() / wanted).coerceAtLeast(1.0)
            var slot = 0
            var fed = false
            var done = false
            while (!done) {
                if (SystemClock.elapsedRealtime() > deadline) break
                if (!fed) {
                    val input = codec.dequeueInputBuffer(10_000)
                    if (input >= 0) {
                        val buffer = codec.getInputBuffer(input)
                        val read = if (buffer == null) -1 else extractor.readSampleData(buffer, 0)
                        if (read < 0) {
                            codec.queueInputBuffer(input, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            fed = true
                        } else {
                            codec.queueInputBuffer(input, 0, read, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val output = codec.dequeueOutputBuffer(info, 10_000)
                if (output >= 0) {
                    val pts = info.presentationTimeUs
                    if (info.size > 0 && pts + 2000 >= startUs) {
                        if (pts > endUs) {
                            done = true
                        } else if (pts + 2000 >= startUs + step * slot) {
                            val image = try {
                                codec.getOutputImage(output)
                            } catch (_: Exception) {
                                null
                            }
                            if (image != null) {
                                try {
                                    sampler.read(image)
                                    onFrame(image, delivered)
                                } finally {
                                    image.close()
                                }
                                delivered++
                                slot = max(slot + 1, ((pts - startUs) / step).toInt() + 1)
                                if (slot >= wanted) done = true
                            }
                        }
                    }
                    codec.releaseOutputBuffer(output, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) done = true
                }
            }
        } catch (error: Exception) {
            Log.w(TAG, "gif walk failed", error)
        } finally {
            try {
                codec.stop()
            } catch (_: Exception) {
            }
            try {
                codec.release()
            } catch (_: Exception) {
            }
            extractor.release()
        }
        return delivered
    }

    /// Last resort for clips the decoder will not hand over: a handful of stills.
    private fun stills(
        context: Context,
        path: String,
        startMs: Long,
        endMs: Long,
        dstW: Int,
        dstH: Int,
        writer: GifWriter,
        wanted: Int,
    ) {
        val retriever = open(context, path)
        val count = wanted.coerceIn(2, 90)
        val grabbed = ArrayList<IntArray>(count)
        try {
            val step = (endMs - startMs).toDouble() / count
            for (i in 0 until count) {
                val timeUs = ((startMs + step * i) * 1000).toLong()
                val bitmap = try {
                    retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                        ?: retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                } catch (_: Exception) {
                    null
                } ?: continue
                val scaled = scaleExact(bitmap, dstW, dstH)
                val pixels = IntArray(dstW * dstH)
                scaled.getPixels(pixels, 0, dstW, 0, 0, dstW, dstH)
                for (j in pixels.indices) pixels[j] = pixels[j] and 0xFFFFFF
                grabbed.add(pixels)
                if (scaled !== bitmap) scaled.recycle()
                bitmap.recycle()
                GifProgress.send("scan", i + 1, count)
            }
        } finally {
            release(retriever)
        }
        if (grabbed.size < 2) return
        val samples = IntArray(96_000)
        var sampleCount = 0
        val stride = max(1, dstW * dstH * grabbed.size / samples.size + 1)
        for (frame in grabbed) {
            var i = 0
            while (i < frame.size && sampleCount < samples.size) {
                samples[sampleCount++] = frame[i]
                i += stride
            }
        }
        writer.buildPalette(samples, sampleCount)
        for ((i, frame) in grabbed.withIndex()) {
            writer.addFrame(frame)
            GifProgress.send("encode", i + 1, grabbed.size)
        }
    }

    /// Converts decoder YUV into the GIF's RGB buffer. Android already rotated
    /// the coded frame in metadata only, so the mapping here also turns the
    /// pixels the right way up. Colour is converted at native size, then Skia
    /// scales it — nearest-neighbour on the chroma planes was what made faces
    /// look like melted wax.
    private class Sampler(
        private val dstW: Int,
        private val dstH: Int,
        private val rotation: Int,
    ) {
        private var yArr = ByteArray(0)
        private var uArr = ByteArray(0)
        private var vArr = ByteArray(0)
        private var rgb = IntArray(0)
        private var scaled = IntArray(dstW * dstH)
        private var srcBmp: Bitmap? = null
        private var bt709 = true
        private var fullRange = false

        fun configure(format: MediaFormat) {
            val standard = intOf(format, MediaFormat.KEY_COLOR_STANDARD)
            val range = intOf(format, MediaFormat.KEY_COLOR_RANGE)
            val width = intOf(format, MediaFormat.KEY_WIDTH)
            val height = intOf(format, MediaFormat.KEY_HEIGHT)
            bt709 = when (standard) {
                MediaFormat.COLOR_STANDARD_BT601_PAL,
                MediaFormat.COLOR_STANDARD_BT601_NTSC,
                -> false
                MediaFormat.COLOR_STANDARD_BT709,
                MediaFormat.COLOR_STANDARD_BT2020,
                -> true
                else -> max(width, height) >= 720
            }
            fullRange = range == MediaFormat.COLOR_RANGE_FULL
        }

        fun read(image: Image) {
            val crop = image.cropRect
            val cropW = if (crop.width() > 0) crop.width() else image.width
            val cropH = if (crop.height() > 0) crop.height() else image.height
            val displayW = if (rotation == 90 || rotation == 270) cropH else cropW
            val displayH = if (rotation == 90 || rotation == 270) cropW else cropH
            if (rgb.size != displayW * displayH) rgb = IntArray(displayW * displayH)
            val planes = image.planes
            yArr = fill(planes[0].buffer.duplicate(), yArr)
            uArr = fill(planes[1].buffer.duplicate(), uArr)
            vArr = fill(planes[2].buffer.duplicate(), vArr)
            val yRow = planes[0].rowStride
            val yPix = planes[0].pixelStride.coerceAtLeast(1)
            val uRow = planes[1].rowStride
            val uPix = planes[1].pixelStride.coerceAtLeast(1)
            val vRow = planes[2].rowStride
            val vPix = planes[2].pixelStride.coerceAtLeast(1)
            val left = crop.left
            val top = crop.top
            val chromaW = max(1, (cropW + 1) / 2)
            val chromaH = max(1, (cropH + 1) / 2)
            for (sy in 0 until cropH) {
                val yRowStart = (top + sy) * yRow
                val cy = sy / 2
                val fy = sy - cy * 2
                val cy1 = if (cy + 1 < chromaH) cy + 1 else cy
                for (sx in 0 until cropW) {
                    val yIdx = yRowStart + (left + sx) * yPix
                    val yVal = yArr[yIdx.coerceIn(0, yArr.size - 1)].toInt() and 0xFF
                    val cx = sx / 2
                    val fx = sx - cx * 2
                    val cx1 = if (cx + 1 < chromaW) cx + 1 else cx
                    val cb = chroma(uArr, uRow, uPix, left / 2 + cx, top / 2 + cy, left / 2 + cx1, top / 2 + cy1, fx, fy)
                    val cr = chroma(vArr, vRow, vPix, left / 2 + cx, top / 2 + cy, left / 2 + cx1, top / 2 + cy1, fx, fy)
                    val color = yuvToRgb(yVal, cb, cr)
                    val dest = when (rotation) {
                        90 -> sx * displayW + (displayW - 1 - sy)
                        180 -> (displayH - 1 - sy) * displayW + (displayW - 1 - sx)
                        270 -> (displayH - 1 - sx) * displayW + sy
                        else -> sy * displayW + sx
                    }
                    rgb[dest] = color
                }
            }
            if (displayW == dstW && displayH == dstH) {
                System.arraycopy(rgb, 0, scaled, 0, scaled.size)
                return
            }
            var src = srcBmp
            if (src == null || src.width != displayW || src.height != displayH) {
                src?.recycle()
                src = Bitmap.createBitmap(displayW, displayH, Bitmap.Config.ARGB_8888)
                srcBmp = src
            }
            src.setPixels(rgb, 0, displayW, 0, 0, displayW, displayH)
            val fitted = Bitmap.createScaledBitmap(src, dstW, dstH, true)
            fitted.getPixels(scaled, 0, dstW, 0, 0, dstW, dstH)
            if (fitted !== src) fitted.recycle()
            for (i in scaled.indices) scaled[i] = scaled[i] and 0xFFFFFF
        }

        fun copyInto(out: IntArray) {
            System.arraycopy(scaled, 0, out, 0, scaled.size.coerceAtMost(out.size))
        }

        private fun chroma(
            plane: ByteArray,
            rowStride: Int,
            pixStride: Int,
            x0: Int,
            y0: Int,
            x1: Int,
            y1: Int,
            fx: Int,
            fy: Int,
        ): Int {
            val a = sample(plane, rowStride, pixStride, x0, y0)
            if (fx == 0 && fy == 0) return a
            val b = sample(plane, rowStride, pixStride, x1, y0)
            val c = sample(plane, rowStride, pixStride, x0, y1)
            val d = sample(plane, rowStride, pixStride, x1, y1)
            // fx/fy are 0 or 1 because source chroma is half-res. A 1 means
            // the luma pixel sits on the far side of the 2x2 block.
            val top = a * (2 - fx) + b * fx
            val bottom = c * (2 - fx) + d * fx
            return (top * (2 - fy) + bottom * fy + 2) shr 2
        }

        private fun sample(plane: ByteArray, rowStride: Int, pixStride: Int, x: Int, y: Int): Int {
            val idx = y * rowStride + x * pixStride
            if (idx < 0 || idx >= plane.size) return 128
            return plane[idx].toInt() and 0xFF
        }

        private fun yuvToRgb(y: Int, cb: Int, cr: Int): Int {
            val luma = if (fullRange) y shl 10 else 1192 * max(0, y - 16)
            val u = cb - 128
            val v = cr - 128
            val r: Int
            val g: Int
            val b: Int
            if (bt709) {
                r = (luma + 1836 * v) shr 10
                g = (luma - 218 * v - 546 * u) shr 10
                b = (luma + 2163 * u) shr 10
            } else {
                r = (luma + 1634 * v) shr 10
                g = (luma - 833 * v - 400 * u) shr 10
                b = (luma + 2066 * u) shr 10
            }
            return (clamp(r) shl 16) or (clamp(g) shl 8) or clamp(b)
        }

        private fun fill(buffer: java.nio.ByteBuffer, target: ByteArray): ByteArray {
            val size = buffer.remaining()
            val out = if (target.size >= size) target else ByteArray(size)
            buffer.get(out, 0, size)
            return out
        }

        private fun intOf(format: MediaFormat, key: String): Int {
            return try {
                if (format.containsKey(key)) format.getInteger(key) else 0
            } catch (_: Exception) {
                0
            }
        }

        private fun clamp(value: Int): Int = if (value < 0) 0 else if (value > 255) 255 else value
    }

    private fun cache(context: Context, bytes: ByteArray, name: String): String {
        val dir = File(context.cacheDir, "gifs")
        dir.mkdirs()
        for (stale in dir.listFiles() ?: emptyArray()) {
            if (stale.isFile) stale.delete()
        }
        // A fresh name every time, otherwise the image cache keeps showing the
        // previous run of the same clip.
        val stem = safeName(name).substringBeforeLast('.')
        val dest = File(dir, "$stem-${System.currentTimeMillis()}.gif")
        dest.writeBytes(bytes)
        return dest.absolutePath
    }

    private fun save(context: Context, bytes: ByteArray, name: String): String {
        val fileName = safeName(name)
        publishToPictures(context, bytes, fileName)?.let { return it }
        val dir = File(context.getExternalFilesDir(Environment.DIRECTORY_PICTURES) ?: context.filesDir, "gifs")
        dir.mkdirs()
        var dest = File(dir, fileName)
        var n = 2
        while (dest.exists()) {
            dest = File(dir, "${fileName.substringBeforeLast('.')} ($n).gif")
            n++
        }
        dest.writeBytes(bytes)
        scan(context, dest.absolutePath)
        return dest.absolutePath
    }

    private fun safeName(name: String): String {
        val safe = name.replace(Regex("[<>:\"/\\\\|?*]"), " ").replace(Regex("\\s+"), " ").trim()
        val stem = if (safe.isEmpty()) "nullmp3" else safe
        return if (stem.endsWith(".gif", true)) stem else "$stem.gif"
    }

    private fun publishToPictures(context: Context, bytes: ByteArray, fileName: String): String? {
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, "image/gif")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/NullMP3/")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }
        val uri = try {
            context.contentResolver.insert(collection, values)
        } catch (error: Exception) {
            Log.w(TAG, "gif insert failed", error)
            null
        } ?: return null
        return try {
            context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("no_stream")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val done = ContentValues()
                done.put(MediaStore.MediaColumns.IS_PENDING, 0)
                context.contentResolver.update(uri, done, null, null)
            }
            queryPath(context, uri) ?: uri.toString()
        } catch (error: Exception) {
            Log.w(TAG, "gif write failed", error)
            try {
                context.contentResolver.delete(uri, null, null)
            } catch (_: Exception) {
            }
            null
        }
    }

    private fun queryPath(context: Context, uri: Uri): String? {
        return try {
            context.contentResolver.query(
                uri,
                arrayOf(MediaStore.MediaColumns.DATA),
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                val idx = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                if (idx < 0) null else cursor.getString(idx)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun scaledSize(width: Int, height: Int, maxWidth: Int): Pair<Int, Int> {
        val srcW = width.coerceAtLeast(2)
        val srcH = height.coerceAtLeast(2)
        val cap = if (maxWidth <= 0) srcW.coerceIn(80, MAX_EDGE) else maxWidth.coerceIn(80, MAX_EDGE)
        val outW: Int
        val outH: Int
        if (srcW <= cap) {
            outW = srcW
            outH = srcH
        } else {
            val scale = cap.toDouble() / srcW
            outW = cap
            outH = max(2, (srcH * scale).roundToInt())
        }
        return even(outW) to even(outH)
    }

    private fun even(value: Int): Int = (value / 2 * 2).coerceAtLeast(2)

    private fun scaleToMax(src: Bitmap, maxSide: Int): Bitmap {
        val width = src.width
        val height = src.height
        if (width <= 0 || height <= 0) return src
        val longest = max(width, height)
        if (longest <= maxSide) return src
        val scale = maxSide.toFloat() / longest
        val dstW = (width * scale).roundToInt().coerceAtLeast(1)
        val dstH = (height * scale).roundToInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, dstW, dstH, true)
    }

    private fun scaleExact(src: Bitmap, dstW: Int, dstH: Int): Bitmap {
        if (src.width == dstW && src.height == dstH) return src
        val out = Bitmap.createBitmap(dstW, dstH, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(out)
        canvas.drawBitmap(
            src,
            null,
            android.graphics.Rect(0, 0, dstW, dstH),
            android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG),
        )
        return out
    }

    private fun meta(retriever: MediaMetadataRetriever, key: Int): String? {
        return try {
            retriever.extractMetadata(key)
        } catch (_: Exception) {
            null
        }
    }

    private fun open(context: Context, path: String): MediaMetadataRetriever {
        val retriever = MediaMetadataRetriever()
        try {
            if (path.startsWith("content:")) {
                retriever.setDataSource(context, Uri.parse(path))
            } else {
                retriever.setDataSource(path)
            }
        } catch (error: Exception) {
            release(retriever)
            throw error
        }
        return retriever
    }

    private fun release(retriever: MediaMetadataRetriever) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                retriever.close()
            } else {
                retriever.release()
            }
        } catch (_: Exception) {
        }
    }

    private fun scan(context: Context, path: String) {
        try {
            MediaScannerConnection.scanFile(context, arrayOf(path), arrayOf("image/gif"), null)
        } catch (_: Exception) {
        }
    }
}
