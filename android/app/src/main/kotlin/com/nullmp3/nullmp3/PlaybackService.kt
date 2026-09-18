package com.nullmp3.nullmp3

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.session.MediaButtonReceiver
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
        var channel: MethodChannel? = null
        var instance: PlaybackService? = null
            private set
        @Volatile
        var pending: Update? = null
    }

    private var session: MediaSessionCompat? = null
    private var playing = false
    private var title = "Null MP3"
    private var artist = ""
    private var durationMs = 0L
    private var positionMs = 0L
    private val mainHandler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null

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
                        toFlutter("play")
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
        val first = pending
        pending = null
        if (first != null) {
            applyUpdate(first.playing, first.title, first.artist, first.durationMs, first.positionMs)
        } else {
            publishNotification()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == Intent.ACTION_MEDIA_BUTTON) {
            MediaButtonReceiver.handleIntent(session, intent)
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
        this.title = title.ifBlank { "Null MP3" }
        this.artist = artist
        this.durationMs = durationMs
        this.positionMs = positionMs
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
    }

    private fun toFlutter(method: String) {
        mainHandler.post {
            try {
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
                    MediaButtonReceiver.buildMediaButtonPendingIntent(
                        this,
                        PlaybackStateCompat.ACTION_PAUSE,
                    ),
                )
            } else {
                NotificationCompat.Action(
                    android.R.drawable.ic_media_play,
                    "Play",
                    MediaButtonReceiver.buildMediaButtonPendingIntent(
                        this,
                        PlaybackStateCompat.ACTION_PLAY,
                    ),
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
            .setOngoing(playing)
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
                    MediaButtonReceiver.buildMediaButtonPendingIntent(
                        this,
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS,
                    ),
                ),
            )
            .addAction(playPauseAction)
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_next,
                    "Next",
                    MediaButtonReceiver.buildMediaButtonPendingIntent(
                        this,
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT,
                    ),
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
        if (playing) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        val lock = wakeLock
        wakeLock = null
        if (lock?.isHeld == true) lock.release()
        session?.isActive = false
        session?.release()
        session = null
        if (instance === this) instance = null
        super.onDestroy()
    }
}
