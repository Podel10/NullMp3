package com.nullmp3.nullmp3

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.session.MediaButtonReceiver
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class PlaybackService : Service() {
    data class Update(
        val playing: Boolean,
        val title: String,
        val artist: String,
        val durationMs: Long,
        val positionMs: Long,
    )

    companion object {
        const val CHANNEL_ID = "nullmp3_playback"
        const val NOTIFICATION_ID = 42
        const val ACTION_PLAY = "com.nullmp3.nullmp3.ACTION_PLAY"
        const val ACTION_PAUSE = "com.nullmp3.nullmp3.ACTION_PAUSE"
        const val ACTION_NEXT = "com.nullmp3.nullmp3.ACTION_NEXT"
        const val ACTION_PREVIOUS = "com.nullmp3.nullmp3.ACTION_PREVIOUS"
        private const val PREFS = "nullmp3_playback"
        private const val KEY_HAS = "has"
        private const val KEY_PLAYING = "playing"
        private const val KEY_TITLE = "title"
        private const val KEY_ARTIST = "artist"
        private const val KEY_DURATION = "durationMs"
        private const val KEY_POSITION = "positionMs"
        var channel: MethodChannel? = null
        var instance: PlaybackService? = null
            private set
        @Volatile
        var pending: Update? = null
    }

    private var session: MediaSessionCompat? = null
    private var playing = false
    private var hasTrack = false
    private var title = "Null MP3"
    private var artist = ""
    private var durationMs = 0L
    private var positionMs = 0L
    private val mainHandler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var otherMedia = false
    private var phoneCall = false
    private var modeListener: AudioManager.OnModeChangedListener? = null
    private val keepAliveTick =
        object : Runnable {
            override fun run() {
                if (!playing) return
                // Android 14+ can demote a quiet media FGS. Touch the
                // notification and wake lock while we still claim playing.
                updateWakeLock()
                publishNotification()
                refreshPhoneCall()
                mainHandler.postDelayed(this, 60_000L)
            }
        }
    private val playbackCallback =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            object : AudioManager.AudioPlaybackCallback() {
                override fun onPlaybackConfigChanged(configs: List<AudioPlaybackConfiguration>) {
                    refreshPhoneCall(configs)
                    val others = otherMediaPlaying(configs)
                    if (others == otherMedia) return
                    otherMedia = others
                    toFlutter(if (others) "otherMediaOn" else "otherMediaOff")
                }
            }
        } else {
            null
        }

    override fun onCreate() {
        super.onCreate()
        instance = this
        ensureChannel()
        session = MediaSessionCompat(this, "NullMP3").apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS,
            )
            setPlaybackToLocal(AudioManager.STREAM_MUSIC)
            setCallback(
                object : MediaSessionCompat.Callback() {
                    override fun onPlay() {
                        sendPlay()
                    }

                    override fun onPause() {
                        toFlutter("pause")
                    }

                    override fun onSkipToNext() {
                        toFlutter("next")
                    }

                    override fun onSkipToPrevious() {
                        toFlutter("previous")
                    }

                    override fun onStop() {
                        // Some OEMs send stop when the activity leaves. Pause is
                        // still available from the notification button.
                    }
                },
                mainHandler,
            )
            isActive = true
        }
        listenOtherMedia(true)
        listenPhoneCall(true)
        val first = pending
        pending = null
        if (first != null) {
            applyUpdate(first.playing, first.title, first.artist, first.durationMs, first.positionMs)
        } else {
            // Process was killed and restarted with START_STICKY. Rebuild the
            // media popup so Play is still reachable without opening the app.
            val saved = loadSaved()
            if (saved != null) {
                applyUpdate(
                    // Never auto-start audio after a kill — just restore the card.
                    false,
                    saved.title,
                    saved.artist,
                    saved.durationMs,
                    saved.positionMs,
                )
            } else {
                publishNotification()
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PLAY -> sendPlay()
            ACTION_PAUSE -> toFlutter("pause")
            ACTION_NEXT -> toFlutter("next")
            ACTION_PREVIOUS -> toFlutter("previous")
            Intent.ACTION_MEDIA_BUTTON -> MediaButtonReceiver.handleIntent(session, intent)
        }
        val extras = intent?.extras
        if (extras != null && extras.containsKey("playing")) {
            applyUpdate(
                extras.getBoolean("playing"),
                extras.getString("title") ?: title,
                extras.getString("artist") ?: artist,
                extras.getLong("durationMs", durationMs),
                extras.getLong("positionMs", positionMs),
            )
        }
        return START_STICKY
    }

    fun applyUpdate(
        playing: Boolean,
        title: String,
        artist: String,
        durationMs: Long,
        positionMs: Long,
    ) {
        this.playing = playing
        this.hasTrack = true
        this.title = title.ifBlank { "Null MP3" }
        this.artist = artist
        this.durationMs = durationMs
        this.positionMs = positionMs
        saveState()
        val actions =
            PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
        val state =
            if (playing) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED
        session?.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(state, positionMs, if (playing) 1f else 0f)
                .build(),
        )
        session?.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, this.title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, this.artist)
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
                .build(),
        )
        session?.isActive = true
        updateWakeLock()
        publishNotification()
        scheduleKeepAlive()
        refreshOtherMedia()
    }

    private fun sendPlay() {
        toFlutter("play")
    }

    private fun toFlutter(method: String) {
        mainHandler.post {
            try {
                FlutterEngineCache.getInstance()
                    .get(MainActivity.ENGINE_ID)
                    ?.lifecycleChannel
                    ?.appIsResumed()
                channel?.invokeMethod(method, null)
            } catch (_: Exception) {
            }
        }
    }

    private fun updateWakeLock() {
        if (playing) {
            val lock = wakeLock
                ?: (getSystemService(POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nullmp3:playback")
                    .apply { setReferenceCounted(false) }
                    .also { wakeLock = it }
            if (!lock.isHeld) lock.acquire(8 * 60 * 60 * 1000L)
        } else {
            val lock = wakeLock ?: return
            if (lock.isHeld) lock.release()
        }
    }

    private fun scheduleKeepAlive() {
        mainHandler.removeCallbacks(keepAliveTick)
        if (playing) mainHandler.postDelayed(keepAliveTick, 60_000L)
    }

    private fun publishNotification() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun actionIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, PlaybackService::class.java).setAction(action)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(this, requestCode, intent, flags)
        } else {
            PendingIntent.getService(this, requestCode, intent, flags)
        }
    }

    private fun buildNotification(): Notification {
        val launch =
            packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java)
        val contentIntent =
            PendingIntent.getActivity(
                this,
                0,
                launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val playPauseAction =
            if (playing) {
                NotificationCompat.Action(
                    android.R.drawable.ic_media_pause,
                    "Pause",
                    actionIntent(ACTION_PAUSE, 2),
                )
            } else {
                NotificationCompat.Action(
                    android.R.drawable.ic_media_play,
                    "Play",
                    actionIntent(ACTION_PLAY, 2),
                )
            }
        val style =
            MediaStyle()
                .setMediaSession(session?.sessionToken)
                .setShowActionsInCompactView(0, 1, 2)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(artist)
            .setContentIntent(contentIntent)
            // Stay pinned while a track is loaded. When only "playing" was
            // ongoing, OEMs cleared the paused card in pocket/doze and left
            // no Play button until the app was opened again.
            .setOngoing(hasTrack || playing)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setStyle(style)
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_previous,
                    "Previous",
                    actionIntent(ACTION_PREVIOUS, 1),
                ),
            )
            .addAction(playPauseAction)
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_next,
                    "Next",
                    actionIntent(ACTION_NEXT, 3),
                ),
            )
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "Playback",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                setShowBadge(false)
                setSound(null, null)
            }
        manager.createNotificationChannel(channel)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Keep playing in the background. Only a phone call (or the user)
        // should stop audio — not clearing the app from recents.
        publishNotification()
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(keepAliveTick)
        listenOtherMedia(false)
        listenPhoneCall(false)
        val lock = wakeLock
        wakeLock = null
        if (lock?.isHeld == true) lock.release()
        session?.isActive = false
        session?.release()
        session = null
        if (instance === this) instance = null
        super.onDestroy()
    }

    private fun saveState() {
        try {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_HAS, true)
                .putBoolean(KEY_PLAYING, playing)
                .putString(KEY_TITLE, title)
                .putString(KEY_ARTIST, artist)
                .putLong(KEY_DURATION, durationMs)
                .putLong(KEY_POSITION, positionMs)
                .apply()
        } catch (_: Exception) {
        }
    }

    private fun loadSaved(): Update? {
        return try {
            val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (!prefs.getBoolean(KEY_HAS, false)) return null
            Update(
                playing = prefs.getBoolean(KEY_PLAYING, false),
                title = prefs.getString(KEY_TITLE, null) ?: "Null MP3",
                artist = prefs.getString(KEY_ARTIST, null) ?: "",
                durationMs = prefs.getLong(KEY_DURATION, 0L),
                positionMs = prefs.getLong(KEY_POSITION, 0L),
            )
        } catch (_: Exception) {
            null
        }
    }

    fun clearSaved() {
        try {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
        } catch (_: Exception) {
        }
        hasTrack = false
    }

    private fun listenOtherMedia(on: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val callback = playbackCallback ?: return
        val manager = getSystemService(AUDIO_SERVICE) as? AudioManager ?: return
        try {
            if (on) {
                manager.registerAudioPlaybackCallback(callback, mainHandler)
                refreshOtherMedia()
                refreshPhoneCall()
            } else {
                manager.unregisterAudioPlaybackCallback(callback)
            }
        } catch (_: Exception) {
        }
    }

    private fun listenPhoneCall(on: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val manager = getSystemService(AUDIO_SERVICE) as? AudioManager ?: return
        try {
            if (on) {
                val listener =
                    AudioManager.OnModeChangedListener { _ -> refreshPhoneCall() }
                modeListener = listener
                manager.addOnModeChangedListener(mainExecutor, listener)
                refreshPhoneCall()
            } else {
                val listener = modeListener ?: return
                modeListener = null
                manager.removeOnModeChangedListener(listener)
            }
        } catch (_: Exception) {
        }
    }

    private fun refreshOtherMedia() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(AUDIO_SERVICE) as? AudioManager ?: return
        val others =
            try {
                otherMediaPlaying(manager.activePlaybackConfigurations)
            } catch (_: Exception) {
                return
            }
        if (others == otherMedia) return
        otherMedia = others
        toFlutter(if (others) "otherMediaOn" else "otherMediaOff")
    }

    private fun refreshPhoneCall(configs: List<AudioPlaybackConfiguration>? = null) {
        val active = phoneCallActive(configs)
        if (active == phoneCall) return
        phoneCall = active
        toFlutter(if (active) "phoneCallOn" else "phoneCallOff")
    }

    private fun phoneCallActive(configs: List<AudioPlaybackConfiguration>? = null): Boolean {
        val manager = getSystemService(AUDIO_SERVICE) as? AudioManager ?: return false
        when (manager.mode) {
            AudioManager.MODE_IN_CALL,
            AudioManager.MODE_IN_COMMUNICATION,
            AudioManager.MODE_RINGTONE,
            -> return true
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val list =
            configs
                ?: try {
                    manager.activePlaybackConfigurations
                } catch (_: Exception) {
                    return false
                }
        for (config in list) {
            when (config.audioAttributes.usage) {
                AudioAttributes.USAGE_VOICE_COMMUNICATION,
                AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING,
                -> return true
            }
        }
        return false
    }

    private fun otherMediaPlaying(configs: List<AudioPlaybackConfiguration>): Boolean {
        var others = 0
        var sawUid = false
        val self = Process.myUid()
        for (config in configs) {
            val usage = config.audioAttributes.usage
            if (usage != AudioAttributes.USAGE_MEDIA && usage != AudioAttributes.USAGE_GAME) {
                continue
            }
            val uid = clientUidOf(config)
            if (uid >= 0) {
                sawUid = true
                if (uid == self) continue
            }
            others++
        }
        // Our video cover also uses USAGE_MEDIA. Ignore this app so a looping
        // cover is not treated as YouTube and does not pause the song.
        if (sawUid) return others >= 1
        return if (playing) others >= 2 else others >= 1
    }

    private fun clientUidOf(config: AudioPlaybackConfiguration): Int {
        return try {
            val value = config.javaClass.getMethod("getClientUid").invoke(config)
            value as? Int ?: -1
        } catch (_: Exception) {
            -1
        }
    }
}
