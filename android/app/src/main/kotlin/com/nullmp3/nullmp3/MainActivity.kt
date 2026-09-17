package com.nullmp3.nullmp3

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val channelName = "com.nullmp3.nullmp3/files"
    private val sessionChannelName = "com.nullmp3.nullmp3/session"
    private val deleteRequestCode = 4401
    private val pickImageRequestCode = 4402
    private var pendingDelete: MethodChannel.Result? = null
    private var pendingPickImage: MethodChannel.Result? = null
    private val editorExecutor = Executors.newSingleThreadExecutor()
    // GIF jobs run for a while, so they get their own lane and never hold up
    // the audio editor.
    private val gifExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deleteFile" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("bad_path", "Missing path", null)
                        } else {
                            deleteFile(path, result)
                        }
                    }
                    "listAudio" -> {
                        val folders = mutableListOf<String>()
                        val raw = call.argument<List<*>>("folders")
                        if (raw != null) {
                            for (item in raw) {
                                if (item != null) folders.add(item.toString())
                            }
                        }
                        listAudio(folders, result)
                    }
                    "listAudioFolders" -> listAudioFolders(result)
                    "renameFile" -> {
                        val path = call.argument<String>("path")
                        val newName = call.argument<String>("newName")
                        if (path.isNullOrEmpty() || newName.isNullOrEmpty()) {
                            result.error("bad_path", "Missing path", null)
                        } else {
                            renameFile(path, newName, result)
                        }
                    }
                    "pickImage" -> pickImage(result)
                    "waveform" -> {
                        val path = call.argument<String>("path")
                        val bars = call.argument<Int>("bars") ?: 800
                        if (path.isNullOrEmpty()) {
                            result.error("bad_path", "Missing path", null)
                        } else {
                            editorExecutor.execute {
                                try {
                                    val data = AudioEditor.waveform(path, bars)
                                    mainHandler.post { result.success(data) }
                                } catch (error: Exception) {
                                    mainHandler.post { result.error("wave", error.message, null) }
                                }
                            }
                        }
                    }
                    "materializeAudio" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("bad_path", "Missing path", null)
                        } else {
                            val replied = AtomicBoolean(false)
                            fun reply(block: () -> Unit) {
                                if (replied.compareAndSet(false, true)) {
                                    mainHandler.post(block)
                                }
                            }
                            Thread({
                                try {
                                    reply { result.success(AudioEditor.materialize(this, path)) }
                                } catch (error: Exception) {
                                    reply { result.error("cut", error.message, null) }
                                }
                            }, "nullmp3-copy").also { worker ->
                                worker.isDaemon = true
                                worker.start()
                                Thread({
                                    try {
                                        worker.join(12_000)
                                    } catch (_: InterruptedException) {
                                    }
                                    reply { result.error("timeout", "copy timed out", null) }
                                }, "nullmp3-copy-watch").apply {
                                    isDaemon = true
                                    start()
                                }
                            }
                        }
                    }
                    "cutAudio" -> {
                        val path = call.argument<String>("path")
                        val destPath = call.argument<String>("destPath") ?: ""
                        val sourceExt = call.argument<String>("ext") ?: ""
                        val startMs = (call.argument<Number>("startMs")?.toLong()) ?: 0L
                        val endMs = (call.argument<Number>("endMs")?.toLong()) ?: 0L
                        val durationMs = (call.argument<Number>("durationMs")?.toLong()) ?: 0L
                        val title = call.argument<String>("title") ?: ""
                        val artist = call.argument<String>("artist") ?: ""
                        val album = call.argument<String>("album") ?: ""
                        if (path.isNullOrEmpty()) {
                            result.error("bad_path", "Missing path", null)
                        } else {
                            val replied = AtomicBoolean(false)
                            fun reply(block: () -> Unit) {
                                if (replied.compareAndSet(false, true)) {
                                    mainHandler.post(block)
                                }
                            }
                            Thread({
                                try {
                                    val saved = AudioEditor.cut(
                                        this,
                                        path,
                                        destPath,
                                        sourceExt,
                                        startMs,
                                        endMs,
                                        durationMs,
                                        title,
                                        artist,
                                        album,
                                    )
                                    reply { result.success(saved) }
                                } catch (error: Exception) {
                                    reply { result.error("cut", error.message, null) }
                                }
                            }, "nullmp3-cut").also { worker ->
                                worker.isDaemon = true
                                worker.start()
                                Thread({
                                    try {
                                        // Decoding a long track can take a while.
                                        worker.join(45_000)
                                    } catch (_: InterruptedException) {
                                    }
                                    reply { result.error("timeout", "cut timed out", null) }
                                }, "nullmp3-cut-watch").apply {
                                    isDaemon = true
                                    start()
                                }
                            }
                        }
                    }
                    "publishCut" -> {
                        val path = call.argument<String>("path")
                        val originalPath = call.argument<String>("originalPath")
                        val destName = call.argument<String>("destName")
                        if (path.isNullOrEmpty() || originalPath.isNullOrEmpty() || destName.isNullOrEmpty()) {
                            result.error("bad_path", "Missing path", null)
                        } else {
                            editorExecutor.execute {
                                try {
                                    val saved = AudioEditor.publishExisting(this, path, originalPath, destName)
                                    mainHandler.post { result.success(saved) }
                                } catch (error: Exception) {
                                    mainHandler.post { result.error("cut", error.message, null) }
                                }
                            }
                        }
                    }
                    "videoInfo" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("bad_path", "Missing path", null)
                        } else {
                            editorExecutor.execute {
                                try {
                                    val info = VideoGif.info(this, path)
                                    mainHandler.post { result.success(info) }
                                } catch (error: Exception) {
                                    mainHandler.post { result.error("video", error.message, null) }
                                }
                            }
                        }
                    }
                    "makeGif" -> {
                        val path = call.argument<String>("path")
                        val startMs = (call.argument<Number>("startMs")?.toLong()) ?: 0L
                        val endMs = (call.argument<Number>("endMs")?.toLong()) ?: 0L
                        val fps = call.argument<Int>("fps") ?: 12
                        val maxWidth = call.argument<Int>("maxWidth") ?: 320
                        val name = call.argument<String>("name") ?: "nullmp3"
                        if (path.isNullOrEmpty()) {
                            result.error("bad_path", "Missing path", null)
                        } else {
                            gifExecutor.execute {
                                try {
                                    val gif = VideoGif.make(this, path, startMs, endMs, fps, maxWidth, name)
                                    mainHandler.post { result.success(gif) }
                                } catch (error: Exception) {
                                    mainHandler.post { result.error("gif", error.message, null) }
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        val sessionChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, sessionChannelName)
        PlaybackService.channel = sessionChannel
        sessionChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val playing = call.argument<Boolean>("playing") ?: false
                    val title = call.argument<String>("title") ?: "Null MP3"
                    val artist = call.argument<String>("artist") ?: ""
                    val durationMs = (call.argument<Number>("durationMs")?.toLong()) ?: 0L
                    val positionMs = (call.argument<Number>("positionMs")?.toLong()) ?: 0L
                    val update = PlaybackService.Update(playing, title, artist, durationMs, positionMs)
                    val intent = Intent(this, PlaybackService::class.java).apply {
                        putExtra("playing", playing)
                        putExtra("title", title)
                        putExtra("artist", artist)
                        putExtra("durationMs", durationMs)
                        putExtra("positionMs", positionMs)
                    }
                    val service = PlaybackService.instance
                    if (service == null) {
                        PlaybackService.pending = update
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                        } catch (_: Exception) {
                            PlaybackService.pending = null
                        }
                    } else {
                        service.applyUpdate(playing, title, artist, durationMs, positionMs)
                    }
                    result.success(null)
                }
                "clear" -> {
                    try {
                        stopService(Intent(this, PlaybackService::class.java))
                    } catch (_: Exception) {
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nullmp3.nullmp3/halo")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val id = (call.argument<Number>("sessionId")?.toInt()) ?: 0
                        val force = call.argument<Boolean>("force") ?: false
                        result.success(AudioHalo.start(id, force))
                    }
                    "pause" -> {
                        AudioHalo.pause()
                        result.success(null)
                    }
                    "stop" -> {
                        AudioHalo.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nullmp3.nullmp3/haloEvents")
            .setStreamHandler(AudioHalo)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nullmp3.nullmp3/gifEvents")
            .setStreamHandler(GifProgress)
    }

    private val audioExtensions = setOf(
        ".mp3", ".m4a", ".aac", ".flac", ".wav", ".ogg", ".opus", ".wma", ".aiff", ".aif", ".alac",
    )

    private fun listAudio(folders: List<String>, result: MethodChannel.Result) {
        if (folders.isEmpty()) {
            result.success(ArrayList<HashMap<String, Any?>>())
            return
        }
        val items = LinkedHashMap<String, HashMap<String, Any?>>()
        queryMusic(folders, items)
        result.success(ArrayList(items.values))
    }

    private fun listAudioFolders(result: MethodChannel.Result) {
        val counts = LinkedHashMap<String, Int>()
        val names = LinkedHashMap<String, String>()
        val seen = HashSet<String>()
        fun addFolder(relative: String?, display: String?, mime: String?) {
            if (relative.isNullOrBlank()) return
            if (!isAudioFile(display, mime)) return
            val rel = relative.replace('\\', '/').trim('/')
            if (rel.isEmpty()) return
            if (rel.startsWith("Android/data", ignoreCase = true)) return
            if (rel.startsWith("Alarms", ignoreCase = true)) return
            if (rel.startsWith("Notifications", ignoreCase = true)) return
            if (rel.startsWith("Ringtones", ignoreCase = true)) return
            if (rel.startsWith("CallRecorder", ignoreCase = true)) return
            if (rel.contains("Telegram Audio", ignoreCase = true)) return
            if (rel.contains("Recordings", ignoreCase = true)) return
            val path = "/storage/emulated/0/$rel"
            val key = canonicalPath(path)
            val fileKey = "$key/${display?.lowercase() ?: ""}"
            if (!seen.add(fileKey)) return
            counts[key] = (counts[key] ?: 0) + 1
            names.putIfAbsent(key, path)
        }
        val projection = arrayOf(
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.RELATIVE_PATH,
        )
        val uris = mutableListOf(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI)
        for (uri in uris) {
            try {
                contentResolver.query(
                    uri,
                    projection,
                    "${MediaStore.Audio.Media.IS_MUSIC}!=0",
                    null,
                    null,
                )?.use { cursor ->
                    val displayI = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                    val mimeI = cursor.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
                    val relativeI = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
                    while (cursor.moveToNext()) {
                        addFolder(
                            if (relativeI >= 0) cursor.getString(relativeI) else null,
                            if (displayI >= 0) cursor.getString(displayI) else null,
                            if (mimeI >= 0) cursor.getString(mimeI) else null,
                        )
                    }
                }
            } catch (_: Exception) {
            }
        }
        val items = counts.entries
            .filter { it.value >= 2 }
            .sortedByDescending { it.value }
            .take(16)
            .map { entry ->
                hashMapOf(
                    "path" to (names[entry.key] ?: entry.key),
                    "count" to entry.value,
                )
            }
        result.success(ArrayList(items))
    }

    private fun queryMusic(folders: List<String>, items: LinkedHashMap<String, HashMap<String, Any?>>) {
        val projection = mutableListOf(
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.YEAR,
            MediaStore.Audio.Media.DISPLAY_NAME,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection.add(MediaStore.Audio.Media.RELATIVE_PATH)
        } else {
            projection.add(MediaStore.Audio.Media.DATA)
        }
        try {
            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection.toTypedArray(),
                "${MediaStore.Audio.Media.IS_MUSIC}!=0",
                null,
                "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
            )?.use { cursor ->
                val titleI = cursor.getColumnIndex(MediaStore.Audio.Media.TITLE)
                val artistI = cursor.getColumnIndex(MediaStore.Audio.Media.ARTIST)
                val albumI = cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM)
                val durationI = cursor.getColumnIndex(MediaStore.Audio.Media.DURATION)
                val modifiedI = cursor.getColumnIndex(MediaStore.Audio.Media.DATE_MODIFIED)
                val trackI = cursor.getColumnIndex(MediaStore.Audio.Media.TRACK)
                val yearI = cursor.getColumnIndex(MediaStore.Audio.Media.YEAR)
                val displayI = cursor.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
                val relativeI = cursor.getColumnIndex(MediaStore.Audio.Media.RELATIVE_PATH)
                val pathI = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
                while (cursor.moveToNext()) {
                    val relative = if (relativeI >= 0) cursor.getString(relativeI) else null
                    val display = if (displayI >= 0) cursor.getString(displayI) else null
                    val path = resolvePath(if (pathI >= 0) cursor.getString(pathI) else null, relative, display)
                        ?: continue
                    if (folders.isNotEmpty() && !pathIsUnderFolders(path, relative, folders)) continue
                    addItem(
                        items,
                        path,
                        pickTitle(if (titleI >= 0) cursor.getString(titleI) else null, display),
                        if (artistI >= 0) cursor.getString(artistI) else null,
                        if (albumI >= 0) cursor.getString(albumI) else null,
                        if (durationI >= 0) cursor.getLong(durationI) else 0L,
                        if (modifiedI >= 0) cursor.getLong(modifiedI) else 0L,
                        if (trackI >= 0 && !cursor.isNull(trackI)) cursor.getString(trackI)?.substringBefore('/')?.toIntOrNull() else null,
                        if (yearI >= 0) cursor.getInt(yearI) else 0,
                    )
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun pickTitle(title: String?, display: String?): String? {
        val fileName = display?.substringBeforeLast('.')?.trim().orEmpty()
        val media = title?.trim().orEmpty()
        if (media.isEmpty() || media.equals("<unknown>", ignoreCase = true)) {
            return fileName.ifEmpty { display }
        }
        if (fileName.contains(media, ignoreCase = true) && fileName.length > media.length + 2) {
            return fileName
        }
        return media
    }

    private fun resolvePath(data: String?, relative: String?, display: String?): String? {
        if (!data.isNullOrEmpty()) return data
        if (relative.isNullOrEmpty() || display.isNullOrEmpty()) return null
        return "/storage/emulated/0/${relative.trimEnd('/')}/$display".replace("//", "/")
    }

    private fun addItem(
        items: LinkedHashMap<String, HashMap<String, Any?>>,
        path: String,
        title: String?,
        artist: String?,
        album: String?,
        duration: Long,
        modified: Long,
        trackNumber: Int?,
        year: Int,
    ) {
        val key = canonicalPath(path)
        if (items.containsKey(key)) return
        items[key] = hashMapOf(
            "path" to path,
            "title" to title,
            "artist" to artist,
            "album" to album,
            "durationMs" to duration,
            "modifiedMs" to modified * 1000,
            "trackNumber" to trackNumber,
            "year" to if (year > 0) year else null,
        )
    }

    private fun isAudioFile(name: String?, mime: String?): Boolean {
        val type = mime?.lowercase() ?: ""
        if (type.contains("mpegurl") || type.contains("x-mpegurl")) return false
        if (type.startsWith("audio/")) return true
        val lower = name?.lowercase() ?: return false
        return audioExtensions.any { lower.endsWith(it) }
    }

    private fun pathIsUnderFolders(path: String, relative: String?, folders: List<String>): Boolean {
        val normalized = canonicalPath(path)
        val rel = relative?.replace('\\', '/')?.trim('/')?.lowercase() ?: ""
        for (folder in folders) {
            val prefix = canonicalPath(folder).trimEnd('/')
            if (normalized == prefix || normalized.startsWith("$prefix/")) return true
            val folderRel = relativeFromRoot(folder)?.lowercase()
            if (!folderRel.isNullOrEmpty() && rel.isNotEmpty()) {
                if (rel == folderRel || rel.startsWith("$folderRel/")) return true
            }
        }
        return false
    }

    private fun relativeFromRoot(folder: String): String? {
        val normalized = folder.replace('\\', '/').trimEnd('/')
        val roots = listOf("/storage/emulated/0/", "/sdcard/", "/storage/self/primary/")
        for (root in roots) {
            if (normalized.startsWith(root)) return normalized.removePrefix(root)
        }
        return null
    }

    private fun canonicalPath(path: String): String {
        var normalized = path.replace('\\', '/').lowercase()
        val aliases = listOf(
            "/storage/self/primary",
            "/storage/emulated/0",
            "/mnt/user/0/primary",
            "/mnt/sdcard",
            "/sdcard",
        )
        for (alias in aliases) {
            if (normalized == alias || normalized.startsWith("$alias/")) {
                normalized = "/storage/emulated/0" + normalized.removePrefix(alias)
                break
            }
        }
        return normalized
    }

    private fun deleteFile(path: String, result: MethodChannel.Result) {
        val file = File(path)
        try {
            if (file.exists() && file.delete()) {
                result.success("ok")
                return
            }
        } catch (_: Exception) {
        }

        val uri = findMediaUri(path)
        if (uri == null) {
            result.success(if (file.exists()) "failed" else "ok")
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                pendingDelete?.success("failed")
                pendingDelete = result
                val request = MediaStore.createDeleteRequest(contentResolver, listOf(uri))
                startIntentSenderForResult(
                    request.intentSender,
                    deleteRequestCode,
                    null,
                    0,
                    0,
                    0,
                )
            } catch (error: Exception) {
                pendingDelete = null
                result.success(if (tryLegacyDelete(uri, file)) "ok" else "failed")
            }
            return
        }

        result.success(if (tryLegacyDelete(uri, file)) "ok" else "failed")
    }

    private fun tryLegacyDelete(uri: Uri, file: File): Boolean {
        val removed = try {
            contentResolver.delete(uri, null, null) > 0
        } catch (_: Exception) {
            false
        }
        if (removed || !file.exists()) return true
        return file.exists() && file.delete()
    }

    private fun findMediaUri(path: String): Uri? {
        val variants = pathVariants(path)
        val collections = mutableListOf(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Files.getContentUri("external"),
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            collections.add(MediaStore.Downloads.EXTERNAL_CONTENT_URI)
        }

        for (collection in collections) {
            for (variant in variants) {
                queryUri(collection, MediaStore.MediaColumns.DATA, variant)?.let { return it }
            }
        }

        val name = File(path).name
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val relative = relativePath(path)
            if (relative != null) {
                for (collection in collections) {
                    queryUri(
                        collection,
                        "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?",
                        arrayOf(name, relative),
                    )?.let { return it }
                    queryUri(
                        collection,
                        "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?",
                        arrayOf(name, "$relative/"),
                    )?.let { return it }
                }
            }
        }

        for (collection in collections) {
            queryUri(collection, MediaStore.MediaColumns.DISPLAY_NAME, name)?.let { return it }
        }
        return null
    }

    private fun queryUri(collection: Uri, column: String, value: String): Uri? {
        return queryUri(collection, "$column=?", arrayOf(value))
    }

    private fun queryUri(collection: Uri, selection: String, args: Array<String>): Uri? {
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        return try {
            contentResolver.query(collection, projection, selection, args, null)?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                val id = cursor.getLong(0)
                ContentUris.withAppendedId(collection, id)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun pathVariants(path: String): List<String> {
        val trimmed = path.trim()
        val slash = trimmed.replace('\\', '/')
        return listOf(
            slash,
            slash.replace("/storage/emulated/0", "/sdcard"),
            slash.replace("/sdcard", "/storage/emulated/0"),
            slash.replace("/storage/emulated/0", "/storage/self/primary"),
        ).distinct()
    }

    private fun relativePath(path: String): String? {
        val normalized = path.replace('\\', '/')
        val root = listOf("/storage/emulated/0/", "/sdcard/", "/storage/self/primary/")
            .firstOrNull { normalized.startsWith(it) } ?: return null
        val relative = normalized.removePrefix(root).substringBeforeLast('/', missingDelimiterValue = "")
        return relative.ifEmpty { null }
    }

    private fun renameFile(path: String, newName: String, result: MethodChannel.Result) {
        val source = File(path)
        val parent = source.parentFile
        if (parent == null) {
            result.success("failed")
            return
        }
        val dest = File(parent, newName)
        if (source.absolutePath.equals(dest.absolutePath, ignoreCase = true)) {
            result.success(source.absolutePath)
            return
        }
        try {
            if (source.renameTo(dest) && dest.exists()) {
                result.success(dest.absolutePath)
                return
            }
        } catch (_: Exception) {
        }
        val uri = findMediaUri(path)
        if (uri != null) {
            try {
                val values = ContentValues()
                values.put(MediaStore.MediaColumns.DISPLAY_NAME, newName)
                if (contentResolver.update(uri, values, null, null) > 0) {
                    val renamed = File(parent, newName)
                    result.success(if (renamed.exists()) renamed.absolutePath else dest.absolutePath)
                    return
                }
            } catch (_: Exception) {
            }
        }
        result.success("failed")
    }

    private fun pickImage(result: MethodChannel.Result) {
        pendingPickImage?.success(null)
        pendingPickImage = result
        val mimeTypes = arrayOf(
            "image/gif",
            "image/webp",
            "image/jpeg",
            "image/png",
            "video/mp4",
            "video/webm",
            "image/*",
        )
        val intents = mutableListOf(
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes)
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                )
            },
            Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "*/*"
                addCategory(Intent.CATEGORY_OPENABLE)
                putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            },
            Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI),
            Intent(Intent.ACTION_PICK, MediaStore.Video.Media.EXTERNAL_CONTENT_URI),
        )
        for (intent in intents) {
            try {
                startActivityForResult(Intent.createChooser(intent, "Cover"), pickImageRequestCode)
                return
            } catch (_: ActivityNotFoundException) {
            } catch (_: Exception) {
            }
        }
        pendingPickImage = null
        result.error("no_picker", "No gallery app", null)
    }

    private fun originalOpenExtras(): Bundle {
        val extras = Bundle()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            extras.putBoolean(MediaStore.EXTRA_ACCEPT_ORIGINAL_MEDIA_FORMAT, true)
        }
        return extras
    }

    private fun mediaStoreUri(uri: Uri): Uri {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return uri
        if (uri.authority?.contains("media", ignoreCase = true) != true) return uri
        return try {
            MediaStore.setRequireOriginal(uri)
        } catch (_: Exception) {
            uri
        }
    }

    private fun readFromMediaPath(uri: Uri): ByteArray? {
        val projection = arrayOf(
            MediaStore.MediaColumns.DATA,
            OpenableColumns.DISPLAY_NAME,
        )
        try {
            contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                val dataIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                if (dataIdx >= 0) {
                    val path = cursor.getString(dataIdx)
                    if (!path.isNullOrEmpty()) {
                        val file = File(path)
                        if (file.exists() && file.canRead()) return file.readBytes()
                    }
                }
            }
        } catch (_: Exception) {
        }
        return null
    }

    private fun readPickedBytes(uri: Uri): ByteArray? {
        val extras = originalOpenExtras()
        val targets = listOf(mediaStoreUri(uri), uri).distinct()
        val mimes = listOf(
            contentResolver.getType(uri),
            "*/*",
            "image/*",
            "video/*",
            "image/gif",
            "image/webp",
            "video/mp4",
            "video/webm",
        ).filterNotNull().distinct()
        for (target in targets) {
            for (mime in mimes) {
                try {
                    contentResolver.openTypedAssetFileDescriptor(target, mime, extras)?.use { afd ->
                        return afd.createInputStream().use { it.readBytes() }
                    }
                } catch (_: Exception) {
                }
            }
            try {
                contentResolver.openAssetFileDescriptor(target, "r")?.use { afd ->
                    return afd.createInputStream().use { it.readBytes() }
                }
            } catch (_: Exception) {
            }
            try {
                contentResolver.openInputStream(target)?.use { return it.readBytes() }
            } catch (_: Exception) {
            }
        }
        return readFromMediaPath(uri)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == deleteRequestCode) {
            pendingDelete?.success(if (resultCode == Activity.RESULT_OK) "ok" else "cancelled")
            pendingDelete = null
            return
        }
        if (requestCode == pickImageRequestCode) {
            val pending = pendingPickImage
            pendingPickImage = null
            if (resultCode != Activity.RESULT_OK) {
                pending?.success(null)
                return
            }
            val uri = data?.data
            if (uri == null) {
                pending?.success(null)
                return
            }
            try {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                } catch (_: Exception) {
                }
                val bytes = readPickedBytes(uri)
                if (bytes == null) {
                    pending?.error("pick_failed", "Could not read image", null)
                } else {
                    pending?.success(bytes)
                }
            } catch (error: Exception) {
                pending?.error("pick_failed", error.message, null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
