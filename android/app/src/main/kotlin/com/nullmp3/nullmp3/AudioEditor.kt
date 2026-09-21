package com.nullmp3.nullmp3

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.io.OutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

object AudioEditor {
    fun waveform(path: String, bars: Int): HashMap<String, Any?> {
        val count = bars.coerceIn(64, 2048)
        val file = File(path)
        val peaks = FloatArray(count)
        var durationMs = 0
        var sampleRate = 0
        var bitrate = 0
        var mime = mimeOf(path)
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            val track = audioTrack(extractor)
            if (track != null) {
                val format = extractor.getTrackFormat(track)
                mime = format.getString(MediaFormat.KEY_MIME) ?: mime
                if (format.containsKey(MediaFormat.KEY_DURATION)) {
                    durationMs = (format.getLong(MediaFormat.KEY_DURATION) / 1000L).toInt()
                }
                if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                    sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                }
                if (format.containsKey(MediaFormat.KEY_BIT_RATE)) {
                    bitrate = format.getInteger(MediaFormat.KEY_BIT_RATE)
                }
                extractor.selectTrack(track)
                decodePeaks(extractor, format, mime, peaks, durationMs, sampleRate)
            }
        } catch (_: Exception) {
        } finally {
            try {
                extractor.release()
            } catch (_: Exception) {
            }
        }
        if (sampleRate == 0 || bitrate == 0) {
            probeMp3(file)?.let { info ->
                if (sampleRate == 0) sampleRate = info.first
                if (bitrate == 0) bitrate = info.second
                mime = "audio/mpeg"
            }
        }
        normalize(peaks)
        return result(peaks, durationMs, sampleRate, bitrate, mime)
    }

    /**
     * Rewrites fragmented / CMAF HLS dumps (ftyp+moov+moof…) into a progressive
     * M4A that ExoPlayer and MediaStore can decode. Returns dest path on success.
     */
    fun remuxProgressive(srcPath: String, destPath: String): String? {
        val src = File(srcPath)
        if (!src.isFile || src.length() < 64) return null
        val dest = File(destPath)
        dest.parentFile?.mkdirs()
        if (dest.exists()) dest.delete()
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        return try {
            extractor.setDataSource(src.absolutePath)
            val track = audioTrack(extractor) ?: return null
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: return null
            if (!mime.startsWith("audio/")) return null
            // Encrypted CMAF (SoundCloud Go+ / Widevine) — remuxing strips DRM
            // signaling but leaves ciphertext. Refuse so we don't produce a
            // "valid" silent/corrupt M4A.
            if (fileLooksDrmProtected(src)) {
                Log.w("NullMP3", "remux skipped: DRM-protected source")
                return null
            }
            muxer = MediaMuxer(dest.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val dstTrack = muxer.addTrack(format)
            muxer.start()
            val buffer = ByteBuffer.allocate(512 * 1024)
            val info = MediaCodec.BufferInfo()
            extractor.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
            var wrote = 0
            while (true) {
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                info.offset = 0
                info.size = size
                info.presentationTimeUs = extractor.sampleTime.coerceAtLeast(0L)
                info.flags = extractor.sampleFlags
                muxer.writeSampleData(dstTrack, buffer, info)
                wrote++
                if (!extractor.advance()) break
            }
            muxer.stop()
            muxer.release()
            muxer = null
            extractor.release()
            if (wrote <= 0 || dest.length() < 256) {
                dest.delete()
                return null
            }
            Log.i("NullMP3", "remux $wrote samples -> ${dest.absolutePath} (${dest.length()} bytes)")
            dest.absolutePath
        } catch (error: Exception) {
            Log.w("NullMP3", "remux failed: ${error.message}")
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
            try {
                extractor.release()
            } catch (_: Exception) {
            }
            try {
                if (dest.exists()) dest.delete()
            } catch (_: Exception) {
            }
            null
        }
    }

    /// Quiet recordings would otherwise draw as a flat line.
    private fun normalize(peaks: FloatArray) {
        var loudest = 0f
        for (value in peaks) loudest = max(loudest, value)
        if (loudest < 0.01f || loudest > 0.98f) return
        val scale = 0.98f / loudest
        for (i in peaks.indices) peaks[i] = min(1f, peaks[i] * scale)
    }

    fun materialize(context: Context, path: String): String {
        val dest = File(context.cacheDir, "edit-${path.hashCode().toUInt()}.bin")
        if (dest.length() > 256) return dest.absolutePath
        openSource(context, path).use { input ->
            dest.outputStream().buffered(64 * 1024).use { out -> input.copyTo(out) }
        }
        if (dest.length() < 256) throw IllegalStateException("missing")
        Log.i("NullMP3", "cut materialized ${dest.absolutePath} (${dest.length()} bytes)")
        return dest.absolutePath
    }

    fun cut(
        context: Context,
        path: String,
        destPath: String,
        sourceExt: String,
        startMs: Long,
        endMs: Long,
        durationMs: Long,
        title: String,
        artist: String,
        album: String,
    ): String {
        // The incoming path is usually a cached copy with no meaningful
        // extension, so the caller tells us what the original file was.
        var kind = sourceKind(sourceExt)
        var dest = destFile(context, destPath, title, outputExt(kind))
        val start = startMs.coerceAtLeast(0)
        val end = endMs.coerceAtLeast(start + 200)
        val tmp = File(context.cacheDir, "nullmp3-src-${System.nanoTime()}.bin")
        try {
            Log.i("NullMP3", "cut start $path as $kind ${start}..${end} of $durationMs")
            openSource(context, path).use { input ->
                tmp.outputStream().buffered(64 * 1024).use { out -> input.copyTo(out) }
            }
            if (tmp.length() < 256) throw IllegalStateException("cut_failed")
            var trimmed = when (kind) {
                "wav" -> cutWav(tmp, dest, start, end)
                "mp4" -> cutContainer(tmp, dest, start, end)
                "mp3" ->
                    dest.outputStream().buffered(64 * 1024).use { out ->
                        cutMp3(tmp, out, start, end, durationMs, title, artist, album)
                    }
                else -> cutToWav(tmp, dest, start, end)
            }
            // The in-place strategies have proportional fallbacks that can
            // degenerate into the whole file. Sizes are only comparable while
            // the encoding is kept, so this only judges those strategies.
            val keptEverything = kind != "pcm" &&
                end - start < durationMs * 95 / 100 &&
                dest.length() >= tmp.length() * 97 / 100
            if ((!trimmed || keptEverything) && kind != "pcm" && destPath.isEmpty()) {
                Log.w("NullMP3", "$kind trim gave nothing usable, decoding instead")
                try {
                    dest.delete()
                } catch (_: Exception) {
                }
                kind = "pcm"
                dest = destFile(context, destPath, title, "wav")
                trimmed = cutToWav(tmp, dest, start, end)
            }
            if (!trimmed || dest.length() < 256) throw IllegalStateException("cut_failed")
            Log.i("NullMP3", "cut saved ${dest.absolutePath} (${dest.length()} bytes)")
            return dest.absolutePath
        } finally {
            try {
                tmp.delete()
            } catch (_: Exception) {
            }
        }
    }

    private fun sourceKind(ext: String): String {
        val clean = ext.trim().trimStart('.').lowercase()
        return when (clean) {
            "mp3", "mp2", "mpga" -> "mp3"
            "m4a", "mp4", "m4b", "aac" -> "mp4"
            "wav", "wave" -> "wav"
            else -> "pcm"
        }
    }

    /// Formats we cannot trim in place are decoded and written out as WAV.
    private fun outputExt(kind: String): String {
        return when (kind) {
            "mp3" -> "mp3"
            "mp4" -> "m4a"
            else -> "wav"
        }
    }

    private fun destFile(context: Context, destPath: String, title: String, ext: String): File {
        if (destPath.isNotEmpty()) {
            val dest = File(destPath)
            dest.parentFile?.mkdirs()
            return dest
        }
        val dir = File(context.getExternalFilesDir(null) ?: context.filesDir, "cuts")
        dir.mkdirs()
        var stem = title.trim().ifEmpty { "cut" }
        stem = stem.replace(Regex("[<>:\"/\\\\|?*]"), " ").replace(Regex("\\s+"), " ").trim()
        if (!Regex("\\(cut\\)(\\s*\\(\\d+\\))?$", RegexOption.IGNORE_CASE).containsMatchIn(stem)) {
            stem = "$stem (cut)"
        }
        return File(dir, "$stem.$ext")
    }

    private fun openSource(context: Context, path: String): InputStream {
        if (path.startsWith("content:")) {
            return context.contentResolver.openInputStream(Uri.parse(path))
                ?: throw IllegalStateException("missing")
        }
        val uri = audioUri(context, path)
        if (uri != null) {
            Log.i("NullMP3", "cut uri $uri")
            return context.contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("missing")
        }
        val dataDir = context.applicationInfo.dataDir
        val extDir = context.getExternalFilesDir(null)?.absolutePath
        val inApp = path.startsWith(dataDir) ||
            (extDir != null && path.startsWith(extDir)) ||
            path.contains("/Android/data/${context.packageName}/")
        if (inApp) {
            return FileInputStream(File(path))
        }
        Log.w("NullMP3", "cut no uri for $path")
        throw IllegalStateException("missing")
    }

    private fun audioUri(context: Context, path: String): Uri? {
        val name = path.substringAfterLast('/').substringAfterLast('\\')
        if (name.isEmpty()) return null
        val rel = relativeDir(path)
        val relSlash = rel?.let { if (it.endsWith("/")) it else "$it/" }
        val collections = mutableListOf(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Files.getContentUri("external"),
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                collections.add(0, MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY))
            } catch (_: Exception) {
            }
            collections.add(MediaStore.Downloads.EXTERNAL_CONTENT_URI)
        }
        for (collection in collections) {
            if (relSlash != null) {
                queryId(
                    context,
                    collection,
                    "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?",
                    arrayOf(name, relSlash),
                )?.let { return it }
                queryId(
                    context,
                    collection,
                    "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?",
                    arrayOf(name, relSlash.trimEnd('/')),
                )?.let { return it }
            }
            queryId(
                context,
                collection,
                "${MediaStore.MediaColumns.DISPLAY_NAME}=?",
                arrayOf(name),
            )?.let { return it }
        }
        return null
    }

    private fun queryId(context: Context, collection: Uri, selection: String, args: Array<String>): Uri? {
        return try {
            context.contentResolver.query(
                collection,
                arrayOf(MediaStore.MediaColumns._ID),
                selection,
                args,
                null,
            )?.use { cursor ->
                val idx = cursor.getColumnIndex(MediaStore.MediaColumns._ID)
                if (idx < 0 || !cursor.moveToFirst()) return null
                ContentUris.withAppendedId(collection, cursor.getLong(idx))
            }
        } catch (error: Exception) {
            Log.w("NullMP3", "cut uri query failed", error)
            null
        }
    }

    fun publishExisting(context: Context, cutPath: String, originalPath: String, destName: String): String {
        val tmp = File(cutPath)
        if (!tmp.exists() || tmp.length() < 256) throw IllegalStateException("cut_failed")
        val original = File(originalPath)
        val wanted = File(original.parentFile, destName)
        return publishCut(context, original, wanted, tmp)
    }

    private fun result(
        peaks: FloatArray,
        durationMs: Int,
        sampleRate: Int,
        bitrate: Int,
        mime: String,
    ): HashMap<String, Any?> {
        return hashMapOf(
            "peaks" to peaks.map { it.toDouble() },
            "durationMs" to durationMs,
            "sampleRate" to sampleRate,
            "bitrate" to bitrate,
            "mime" to mime,
        )
    }

    private fun mimeOf(path: String): String {
        val lower = path.lowercase()
        return when {
            lower.endsWith(".mp3") -> "audio/mpeg"
            lower.endsWith(".m4a") || lower.endsWith(".mp4") || lower.endsWith(".aac") -> "audio/mp4"
            lower.endsWith(".wav") -> "audio/wav"
            lower.endsWith(".flac") -> "audio/flac"
            lower.endsWith(".ogg") || lower.endsWith(".opus") -> "audio/ogg"
            else -> "audio/*"
        }
    }

    /** True when the ISO-BMFF dump carries DRM (enca / tenc / pssh / schm). */
    private fun fileLooksDrmProtected(file: File): Boolean {
        if (!file.isFile || file.length() < 64) return false
        return try {
            RandomAccessFile(file, "r").use { raf ->
                val n = min(file.length(), 512L * 1024L).toInt()
                val buf = ByteArray(n)
                raf.readFully(buf)
                containsFourCC(buf, "enca") ||
                    containsFourCC(buf, "tenc") ||
                    containsFourCC(buf, "pssh") ||
                    containsFourCC(buf, "schm")
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun containsFourCC(buf: ByteArray, fourCC: String): Boolean {
        if (fourCC.length != 4) return false
        val a = fourCC[0].code
        val b = fourCC[1].code
        val c = fourCC[2].code
        val d = fourCC[3].code
        for (i in 0 until buf.size - 3) {
            if (buf[i].toInt() and 0xff == a &&
                buf[i + 1].toInt() and 0xff == b &&
                buf[i + 2].toInt() and 0xff == c &&
                buf[i + 3].toInt() and 0xff == d
            ) {
                return true
            }
        }
        return false
    }

    private fun audioTrack(extractor: MediaExtractor): Int? {
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) return i
        }
        return null
    }

    private fun decodePeaks(
        extractor: MediaExtractor,
        format: MediaFormat,
        mime: String,
        peaks: FloatArray,
        durationMs: Int,
        sampleRateHint: Int,
    ) {
        val decoder = try {
            MediaCodec.createDecoderByType(mime)
        } catch (_: Exception) {
            return
        }
        try {
            decoder.configure(format, null, null, 0)
            decoder.start()
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var pcmFrames = 0L
            var sampleRate = sampleRateHint
            var channels = 2
            if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT).coerceAtLeast(1)
            }
            val totalFrames = if (durationMs > 0 && sampleRate > 0) {
                max(1L, sampleRate.toLong() * durationMs / 1000L)
            } else {
                0L
            }
            var steps = 0
            while (!outputDone && steps++ < 400_000) {
                if (!inputDone) {
                    val inIndex = decoder.dequeueInputBuffer(8_000)
                    if (inIndex >= 0) {
                        val buffer = decoder.getInputBuffer(inIndex)
                        val size = if (buffer == null) -1 else extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIndex = decoder.dequeueOutputBuffer(info, 8_000)
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val outFormat = decoder.outputFormat
                    if (outFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                        sampleRate = outFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    }
                    if (outFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                        channels = outFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT).coerceAtLeast(1)
                    }
                    continue
                }
                if (outIndex < 0) continue
                val outBuf = decoder.getOutputBuffer(outIndex)
                if (outBuf != null && info.size > 0) {
                    val framesGuess = if (totalFrames > 0) totalFrames else max(1L, pcmFrames + 1)
                    absorbPcm(outBuf, info, channels, peaks, pcmFrames, framesGuess)
                    val bytesPerFrame = 2 * channels
                    if (bytesPerFrame > 0) pcmFrames += (info.size / bytesPerFrame).toLong()
                }
                decoder.releaseOutputBuffer(outIndex, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
            }
        } catch (_: Exception) {
        } finally {
            try {
                decoder.stop()
            } catch (_: Exception) {
            }
            try {
                decoder.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun absorbPcm(
        buffer: ByteBuffer,
        info: MediaCodec.BufferInfo,
        channels: Int,
        peaks: FloatArray,
        startFrame: Long,
        totalFrames: Long,
    ) {
        val end = info.offset + info.size
        buffer.position(info.offset)
        buffer.limit(end)
        var frame = startFrame
        val ch = channels.coerceAtLeast(1)
        while (buffer.remaining() >= 2 * ch) {
            var amp = 0
            repeat(ch) {
                amp = max(amp, abs(buffer.short.toInt()))
            }
            val bar = ((frame * peaks.size) / totalFrames).toInt().coerceIn(0, peaks.lastIndex)
            val value = amp / 32768f
            if (value > peaks[bar]) peaks[bar] = value
            frame++
        }
    }

    private fun cutContainer(src: File, dest: File, startMs: Long, endMs: Long): Boolean {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        return try {
            extractor.setDataSource(src.absolutePath)
            val track = audioTrack(extractor) ?: return false
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: return false
            if (mime.contains("mpeg") && !mime.contains("mp4")) return false
            extractor.seekTo(startMs * 1000L, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            muxer = MediaMuxer(dest.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val dstTrack = muxer.addTrack(format)
            muxer.start()
            val buffer = ByteBuffer.allocate(256 * 1024)
            val info = MediaCodec.BufferInfo()
            var offsetUs = -1L
            val endUs = endMs * 1000L
            while (true) {
                buffer.clear()
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val time = extractor.sampleTime
                if (time > endUs) break
                if (time >= startMs * 1000L) {
                    if (offsetUs < 0) offsetUs = time
                    info.offset = 0
                    info.size = size
                    info.presentationTimeUs = (time - offsetUs).coerceAtLeast(0)
                    info.flags = extractor.sampleFlags
                    buffer.position(0)
                    buffer.limit(size)
                    muxer.writeSampleData(dstTrack, buffer, info)
                }
                extractor.advance()
            }
            true
        } catch (_: Exception) {
            false
        } finally {
            try {
                muxer?.stop()
            } catch (_: Exception) {
            }
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
            try {
                extractor.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun cutWav(src: File, dest: File, startMs: Long, endMs: Long): Boolean {
        try {
            RandomAccessFile(src, "r").use { input ->
                val length = input.length()
                if (length < 44L) return false
                var offset = 12L
                var channels = 2
                var sampleRate = 44100
                var bits = 16
                var dataStart = -1L
                var dataSize = 0L
                while (offset + 8 <= length) {
                    input.seek(offset)
                    val head = ByteArray(8)
                    if (input.read(head) < 8) break
                    val id = String(head, 0, 4, Charsets.US_ASCII)
                    val size = u32(head, 4).toLong() and 0xFFFFFFFFL
                    if (offset + 8 + size > length) break
                    if (id == "fmt ") {
                        val fmtLen = min(size, 40L).toInt()
                        val fmt = ByteArray(fmtLen)
                        if (input.read(fmt) >= 16) {
                            channels = u16(fmt, 2).coerceAtLeast(1)
                            sampleRate = u32(fmt, 4).coerceAtLeast(1)
                            bits = u16(fmt, 14).coerceAtLeast(8)
                        }
                    } else if (id == "data") {
                        dataStart = offset + 8
                        dataSize = min(size, length - dataStart)
                        break
                    }
                    offset += 8 + size + (size and 1L)
                }
                if (dataStart < 0) return false
                val bytesPerSec = sampleRate.toLong() * channels * (bits / 8)
                if (bytesPerSec <= 0) return false
                val align = channels * (bits / 8)
                if (align <= 0) return false
                var from = ((startMs * bytesPerSec) / 1000L)
                var to = ((endMs * bytesPerSec) / 1000L)
                from -= from % align
                to -= to % align
                from = from.coerceIn(0L, dataSize)
                to = to.coerceIn(from, dataSize)
                val sliceLen = to - from
                if (sliceLen < align) return false
                val header = ByteArray(44)
                System.arraycopy("RIFF".toByteArray(), 0, header, 0, 4)
                putU32(header, 4, (36 + sliceLen).toInt())
                System.arraycopy("WAVEfmt ".toByteArray(), 0, header, 8, 8)
                putU32(header, 16, 16)
                putU16(header, 20, 1)
                putU16(header, 22, channels)
                putU32(header, 24, sampleRate)
                putU32(header, 28, bytesPerSec.toInt())
                putU16(header, 32, align)
                putU16(header, 34, bits)
                System.arraycopy("data".toByteArray(), 0, header, 36, 4)
                putU32(header, 40, sliceLen.toInt())
                RandomAccessFile(dest, "rw").use { out ->
                    out.setLength(0)
                    out.write(header)
                    input.seek(dataStart + from)
                    val buf = ByteArray(64 * 1024)
                    var left = sliceLen
                    while (left > 0) {
                        val n = input.read(buf, 0, min(left, buf.size.toLong()).toInt())
                        if (n <= 0) break
                        out.write(buf, 0, n)
                        left -= n
                    }
                }
                return dest.exists() && dest.length() > 44L
            }
        } catch (_: Exception) {
            return false
        }
    }

    /// Last resort for formats with no safe in-place trim: decode the selected
    /// range and write it out as WAV.
    private fun cutToWav(src: File, dest: File, startMs: Long, endMs: Long): Boolean {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        var out: RandomAccessFile? = null
        var pcmBytes = 0L
        var sampleRate = 44100
        var channels = 2
        try {
            extractor.setDataSource(src.absolutePath)
            val track = audioTrack(extractor) ?: return false
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: return false
            if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            }
            if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT).coerceAtLeast(1)
            }
            extractor.selectTrack(track)
            extractor.seekTo(startMs * 1000L, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            decoder = MediaCodec.createDecoderByType(mime)
            decoder.configure(format, null, null, 0)
            decoder.start()
            out = RandomAccessFile(dest, "rw")
            out.setLength(0)
            out.write(ByteArray(44))
            val startUs = startMs * 1000L
            val endUs = endMs * 1000L
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var steps = 0
            val limit = 256L * 1024 * 1024
            while (!outputDone && steps++ < 400_000 && pcmBytes < limit) {
                if (!inputDone) {
                    val inIndex = decoder.dequeueInputBuffer(8_000)
                    if (inIndex >= 0) {
                        val buffer = decoder.getInputBuffer(inIndex)
                        val size = if (buffer == null) -1 else extractor.readSampleData(buffer, 0)
                        val time = extractor.sampleTime
                        if (size < 0 || (time in 1..Long.MAX_VALUE && time > endUs)) {
                            decoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(inIndex, 0, size, time, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIndex = decoder.dequeueOutputBuffer(info, 8_000)
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val outFormat = decoder.outputFormat
                    if (outFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                        sampleRate = outFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    }
                    if (outFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                        channels = outFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT).coerceAtLeast(1)
                    }
                    continue
                }
                if (outIndex < 0) continue
                val outBuf = decoder.getOutputBuffer(outIndex)
                if (outBuf != null && info.size > 0 && info.presentationTimeUs >= startUs) {
                    val chunk = ByteArray(info.size)
                    outBuf.position(info.offset)
                    outBuf.get(chunk, 0, info.size)
                    out.write(chunk)
                    pcmBytes += info.size.toLong()
                }
                decoder.releaseOutputBuffer(outIndex, false)
                if (info.presentationTimeUs > endUs) outputDone = true
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
            }
            if (pcmBytes < 256) return false
            out.seek(0)
            out.write(wavHeader(pcmBytes.toInt(), sampleRate, channels, 16))
            return true
        } catch (error: Exception) {
            Log.w("NullMP3", "decode cut failed", error)
            return false
        } finally {
            try {
                out?.close()
            } catch (_: Exception) {
            }
            try {
                decoder?.stop()
            } catch (_: Exception) {
            }
            try {
                decoder?.release()
            } catch (_: Exception) {
            }
            try {
                extractor.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun wavHeader(dataSize: Int, sampleRate: Int, channels: Int, bits: Int): ByteArray {
        val align = channels * (bits / 8)
        val head = ByteArray(44)
        System.arraycopy("RIFF".toByteArray(), 0, head, 0, 4)
        putU32(head, 4, 36 + dataSize)
        System.arraycopy("WAVEfmt ".toByteArray(), 0, head, 8, 8)
        putU32(head, 16, 16)
        putU16(head, 20, 1)
        putU16(head, 22, channels)
        putU32(head, 24, sampleRate)
        putU32(head, 28, sampleRate * align)
        putU16(head, 32, align)
        putU16(head, 34, bits)
        System.arraycopy("data".toByteArray(), 0, head, 36, 4)
        putU32(head, 40, dataSize)
        return head
    }

    private fun cutMp3(
        src: File,
        out: OutputStream,
        startMs: Long,
        endMs: Long,
        durationMs: Long,
        title: String,
        artist: String,
        album: String,
    ): Boolean {
        out.write(id3Tag(title, artist, album))
        var audio = writeMp3Extractor(src, out, startMs, endMs)
        if (audio < 256) audio = writeMp3Frames(src, out, startMs, endMs)
        if (audio < 256) audio = writeMp3Range(src, out, startMs, endMs, durationMs)
        return audio >= 256
    }

    private fun writeMp3Extractor(src: File, out: OutputStream, startMs: Long, endMs: Long): Long {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(src.absolutePath)
            val track = audioTrack(extractor) ?: return 0
            val mime = extractor.getTrackFormat(track).getString(MediaFormat.KEY_MIME) ?: return 0
            if (!mime.contains("mpeg") && !mime.contains("mp3")) return 0
            extractor.selectTrack(track)
            try {
                extractor.seekTo(startMs * 1000L, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            } catch (_: Exception) {
            }
            val buffer = ByteBuffer.allocate(256 * 1024)
            val startUs = startMs * 1000L
            val endUs = endMs * 1000L
            var written = 0L
            while (true) {
                val time = extractor.sampleTime
                if (time < 0) break
                if (time > endUs) break
                buffer.clear()
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                if (time >= startUs) {
                    val bytes = ByteArray(size)
                    buffer.position(0)
                    buffer.get(bytes)
                    out.write(bytes)
                    written += size.toLong()
                }
                extractor.advance()
            }
            written
        } catch (error: Exception) {
            Log.w("NullMP3", "mp3 extractor cut failed", error)
            0
        } finally {
            try {
                extractor.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun writeMp3Frames(src: File, out: OutputStream, startMs: Long, endMs: Long): Long {
        val raf = RandomAccessFile(src, "r")
        var written = 0L
        try {
            var pos = skipId3(raf)
            var timeMs = 0.0
            val buf = ByteArray(2048)
            val fileLen = raf.length()
            while (pos + 4 < fileLen) {
                raf.seek(pos)
                if (raf.read(buf, 0, 4) < 4) break
                val header = parseHeader(buf)
                if (header == null || header.length < 24 || pos + header.length > fileLen) {
                    pos++
                    continue
                }
                if (!nextFrameLooksValid(raf, pos + header.length.toLong(), fileLen)) {
                    pos++
                    continue
                }
                val frameEnd = timeMs + header.durationMs
                if (frameEnd > startMs && timeMs < endMs) {
                    raf.seek(pos)
                    var left = header.length
                    while (left > 0) {
                        val n = raf.read(buf, 0, minOf(left, buf.size))
                        if (n <= 0) break
                        out.write(buf, 0, n)
                        written += n.toLong()
                        left -= n
                    }
                }
                if (timeMs >= endMs) break
                timeMs = frameEnd
                pos += header.length.toLong()
            }
        } catch (error: Exception) {
            Log.w("NullMP3", "mp3 frame cut failed", error)
        } finally {
            try {
                raf.close()
            } catch (_: Exception) {
            }
        }
        return written
    }

    private fun nextFrameLooksValid(raf: RandomAccessFile, pos: Long, fileLen: Long): Boolean {
        if (pos + 4 > fileLen) return true
        raf.seek(pos)
        val head = ByteArray(4)
        if (raf.read(head) < 4) return true
        val next = parseHeader(head) ?: return false
        return next.length >= 24 && pos + next.length <= fileLen + 1
    }

    private fun writeMp3Range(
        src: File,
        out: OutputStream,
        startMs: Long,
        endMs: Long,
        durationMs: Long,
    ): Long {
        val raf = RandomAccessFile(src, "r")
        return try {
            val start = skipId3(raf)
            val audioLen = raf.length() - start
            if (audioLen < 256) return 0
            val dur = durationMs.coerceAtLeast(endMs.coerceAtLeast(1))
            var from = start + audioLen * startMs / dur
            var to = start + audioLen * endMs / dur
            from = nextSync(raf, from)
            to = nextSync(raf, to.coerceAtLeast(from + 256)).coerceAtLeast(from + 256)
            to = to.coerceAtMost(raf.length())
            raf.seek(from)
            val buf = ByteArray(64 * 1024)
            var left = to - from
            var written = 0L
            while (left > 0) {
                val n = raf.read(buf, 0, minOf(left.toInt(), buf.size))
                if (n <= 0) break
                out.write(buf, 0, n)
                written += n.toLong()
                left -= n.toLong()
            }
            written
        } catch (error: Exception) {
            Log.w("NullMP3", "mp3 range cut failed", error)
            0
        } finally {
            try {
                raf.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun nextSync(raf: RandomAccessFile, start: Long): Long {
        val head = ByteArray(4)
        var pos = start.coerceAtLeast(0)
        val limit = minOf(raf.length(), start + 64 * 1024)
        while (pos + 4 <= limit) {
            raf.seek(pos)
            if (raf.read(head) < 4) break
            val header = parseHeader(head)
            if (header != null && header.length >= 24) return pos
            pos++
        }
        return start
    }

    private fun publishCut(context: Context, src: File, wanted: File, tmp: File): String {
        val beside = File(src.parentFile ?: wanted.parentFile, wanted.name)
        try {
            beside.parentFile?.mkdirs()
            tmp.copyTo(beside, overwrite = true)
            if (beside.exists() && beside.length() == tmp.length()) {
                scan(context, beside.absolutePath)
                return beside.absolutePath
            }
        } catch (error: Exception) {
            Log.w("NullMP3", "copy next to source failed", error)
        }
        publishMediaStore(context, src, wanted.name, mimeOf(src.absolutePath), tmp)?.let { return it }
        val fallbackDir = context.getExternalFilesDir(Environment.DIRECTORY_MUSIC) ?: context.filesDir
        fallbackDir.mkdirs()
        var fallback = File(fallbackDir, wanted.name)
        var n = 2
        while (fallback.exists() && fallback.absolutePath != wanted.absolutePath) {
            val stem = wanted.nameWithoutExtension
            val ext = wanted.extension
            fallback = File(fallbackDir, "$stem ($n).$ext")
            n++
        }
        tmp.copyTo(fallback, overwrite = true)
        scan(context, fallback.absolutePath)
        return fallback.absolutePath
    }

    private fun publishMediaStore(
        context: Context,
        src: File,
        name: String,
        mime: String,
        tmp: File,
    ): String? {
        val relative = relativeDir(src.absolutePath) ?: "Music"
        if (relative.contains("Android/data", ignoreCase = true)) return null
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.Audio.Media.IS_MUSIC, 1)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.IS_PENDING, 1)
                val folder = if (relative.endsWith("/")) relative else "$relative/"
                put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
            }
        }
        val uri = try {
            resolver.insert(collection, values)
        } catch (error: Exception) {
            Log.w("NullMP3", "mediastore insert failed", error)
            null
        } ?: return null
        return try {
            resolver.openOutputStream(uri)?.use { out ->
                tmp.inputStream().use { input -> input.copyTo(out) }
            } ?: throw IllegalStateException("no stream")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val done = ContentValues()
                done.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, done, null, null)
            }
            queryPath(context, uri) ?: src.parentFile?.let { File(it, name).absolutePath }
        } catch (error: Exception) {
            Log.w("NullMP3", "mediastore write failed", error)
            try {
                resolver.delete(uri, null, null)
            } catch (_: Exception) {
            }
            null
        }
    }

    private fun queryPath(context: Context, uri: android.net.Uri): String? {
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

    private fun relativeDir(path: String): String? {
        val normalized = path.replace('\\', '/')
        val roots = listOf("/storage/emulated/0/", "/sdcard/", "/storage/self/primary/")
        val root = roots.firstOrNull { normalized.startsWith(it) } ?: return null
        val parent = normalized.removePrefix(root).substringBeforeLast('/', missingDelimiterValue = "")
        return parent.ifEmpty { "Music" }
    }

    private fun scan(context: Context, path: String) {
        try {
            MediaScannerConnection.scanFile(context, arrayOf(path), null, null)
        } catch (_: Exception) {
        }
    }

    private fun looksLikeMp3(file: File): Boolean {
        val raf = RandomAccessFile(file, "r")
        return try {
            val pos = skipId3(raf)
            raf.seek(pos)
            val head = ByteArray(4)
            raf.read(head) == 4 && frameHeader(head) != null
        } catch (_: Exception) {
            false
        } finally {
            raf.close()
        }
    }

    private fun probeMp3(file: File): Pair<Int, Int>? {
        val raf = RandomAccessFile(file, "r")
        return try {
            val pos = skipId3(raf)
            raf.seek(pos)
            val head = ByteArray(4)
            if (raf.read(head) < 4) return null
            val parsed = parseHeader(head) ?: return null
            parsed.sampleRate to parsed.bitrateKbps * 1000
        } catch (_: Exception) {
            null
        } finally {
            raf.close()
        }
    }

    private fun skipId3(raf: RandomAccessFile): Long {
        var offset = 0L
        val head = ByteArray(10)
        while (offset + 10 <= raf.length()) {
            raf.seek(offset)
            if (raf.read(head) < 10) break
            if (head[0] != 'I'.code.toByte() || head[1] != 'D'.code.toByte() || head[2] != '3'.code.toByte()) break
            if (head[6].toInt() and 0x80 != 0 || head[7].toInt() and 0x80 != 0 ||
                head[8].toInt() and 0x80 != 0 || head[9].toInt() and 0x80 != 0
            ) {
                break
            }
            val size = (head[9].toInt() and 0x7F) or
                ((head[8].toInt() and 0x7F) shl 7) or
                ((head[7].toInt() and 0x7F) shl 14) or
                ((head[6].toInt() and 0x7F) shl 21)
            val footer = if (head[3].toInt() == 4 && head[5].toInt() and 0x10 != 0) 10 else 0
            val total = 10 + size + footer
            if (total <= 10) break
            offset += total.toLong()
        }
        return offset
    }

    private data class Mp3Header(val length: Int, val durationMs: Double, val sampleRate: Int, val bitrateKbps: Int)

    private fun frameHeader(h: ByteArray): Pair<Int, Double>? {
        val parsed = parseHeader(h) ?: return null
        return parsed.length to parsed.durationMs
    }

    private fun parseHeader(h: ByteArray): Mp3Header? {
        if (h.size < 4) return null
        val b0 = h[0].toInt() and 0xFF
        val b1 = h[1].toInt() and 0xFF
        val b2 = h[2].toInt() and 0xFF
        if (b0 != 0xFF || b1 and 0xE0 != 0xE0) return null
        val versionId = (b1 shr 3) and 3
        if (versionId == 1) return null
        val layerBits = (b1 shr 1) and 3
        if (layerBits == 0) return null
        val bitrateIdx = b2 shr 4
        val srIdx = (b2 shr 2) and 3
        if (bitrateIdx == 0 || bitrateIdx == 15 || srIdx == 3) return null
        val padding = (b2 shr 1) and 1
        val mpeg1 = versionId == 3
        val layer3 = layerBits == 1
        val bitrate = bitrateKbps(mpeg1, layer3, layerBits, bitrateIdx) ?: return null
        val sampleRate = sampleRate(versionId, srIdx) ?: return null
        val length = when {
            layer3 -> {
                val scale = if (mpeg1) 144 else 72
                scale * bitrate * 1000 / sampleRate + padding
            }
            layerBits == 2 -> 144 * bitrate * 1000 / sampleRate + padding
            else -> (12 * bitrate * 1000 / sampleRate) * 4 + padding * 4
        }
        val samples = when {
            layer3 && mpeg1 -> 1152
            layer3 -> 576
            layerBits == 3 -> 384
            else -> 1152
        }
        val duration = samples * 1000.0 / sampleRate
        return Mp3Header(length, duration, sampleRate, bitrate)
    }

    private fun bitrateKbps(mpeg1: Boolean, layer3: Boolean, layerBits: Int, index: Int): Int? {
        val table = when {
            mpeg1 && layer3 -> intArrayOf(0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320)
            mpeg1 && layerBits == 2 -> intArrayOf(0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384)
            mpeg1 -> intArrayOf(0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448)
            layer3 -> intArrayOf(0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160)
            else -> return null
        }
        if (index !in table.indices) return null
        val value = table[index]
        return if (value == 0) null else value
    }

    private fun sampleRate(versionId: Int, index: Int): Int? {
        val table = when (versionId) {
            3 -> intArrayOf(44100, 48000, 32000)
            2 -> intArrayOf(22050, 24000, 16000)
            0 -> intArrayOf(11025, 12000, 8000)
            else -> return null
        }
        return table.getOrNull(index)
    }

    private fun id3Tag(title: String, artist: String, album: String): ByteArray {
        val body = ByteArrayOutputStream()
        fun text(id: String, value: String) {
            val text = value.trim()
            if (text.isEmpty()) return
            val payload = ByteArrayOutputStream()
            payload.write(1)
            payload.write(0xFF)
            payload.write(0xFE)
            for (ch in text) {
                val code = ch.code
                payload.write(code and 0xFF)
                payload.write(code shr 8)
            }
            payload.write(0)
            payload.write(0)
            val bytes = payload.toByteArray()
            body.write(id.toByteArray(Charsets.US_ASCII))
            val size = bytes.size
            body.write(size shr 24)
            body.write(size shr 16)
            body.write(size shr 8)
            body.write(size)
            body.write(0)
            body.write(0)
            body.write(bytes)
        }
        text("TIT2", title)
        text("TPE1", artist)
        text("TALB", album)
        val bytes = body.toByteArray()
        val header = ByteArray(10)
        header[0] = 'I'.code.toByte()
        header[1] = 'D'.code.toByte()
        header[2] = '3'.code.toByte()
        header[3] = 3
        val size = bytes.size
        header[6] = ((size shr 21) and 0x7F).toByte()
        header[7] = ((size shr 14) and 0x7F).toByte()
        header[8] = ((size shr 7) and 0x7F).toByte()
        header[9] = (size and 0x7F).toByte()
        return header + bytes
    }

    private fun u16(data: ByteArray, i: Int): Int {
        return (data[i].toInt() and 0xFF) or ((data[i + 1].toInt() and 0xFF) shl 8)
    }

    private fun u32(data: ByteArray, i: Int): Int {
        return (data[i].toInt() and 0xFF) or
            ((data[i + 1].toInt() and 0xFF) shl 8) or
            ((data[i + 2].toInt() and 0xFF) shl 16) or
            ((data[i + 3].toInt() and 0xFF) shl 24)
    }

    private fun putU16(data: ByteArray, i: Int, value: Int) {
        data[i] = (value and 0xFF).toByte()
        data[i + 1] = ((value shr 8) and 0xFF).toByte()
    }

    private fun putU32(data: ByteArray, i: Int, value: Int) {
        data[i] = (value and 0xFF).toByte()
        data[i + 1] = ((value shr 8) and 0xFF).toByte()
        data[i + 2] = ((value shr 16) and 0xFF).toByte()
        data[i + 3] = ((value shr 24) and 0xFF).toByte()
    }
}
