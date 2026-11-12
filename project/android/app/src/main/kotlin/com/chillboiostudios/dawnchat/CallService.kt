package com.chillboiostudios.dawnchat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground service shown while the user is in a voice call.
 *
 * Port of the Android app's `OngoingCallService`: posts a persistent
 * CallStyle notification with a chronometer plus mute/hang-up actions.
 * Hang-up and mute requests are relayed to Dart over [eventSink].
 */
class CallService : Service() {
    companion object {
        private const val ACTION_START = "dawnchat.call.START"
        private const val ACTION_STOP = "dawnchat.call.STOP"
        private const val ACTION_HANGUP = "dawnchat.call.HANGUP"
        private const val ACTION_TOGGLE_MUTE = "dawnchat.call.TOGGLE_MUTE"
        private const val EXTRA_CHANNEL_ID = "channelId"
        private const val EXTRA_CHANNEL_NAME = "channelName"
        private const val EXTRA_MIC_MUTED = "micMuted"
        private const val NOTIFICATION_ID = 67
        private const val CHANNEL_ID = "dawnchat_calls"

        @Volatile var eventSink: EventChannel.EventSink? = null

        fun start(context: Context, channelId: String, channelName: String?) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, CallService::class.java)
                    .setAction(ACTION_START)
                    .putExtra(EXTRA_CHANNEL_ID, channelId)
                    .putExtra(EXTRA_CHANNEL_NAME, channelName),
            )
        }

        fun updateMicMuted(context: Context, muted: Boolean) {
            try {
                context.startService(
                    Intent(context, CallService::class.java)
                        .setAction(ACTION_TOGGLE_MUTE_STATE)
                        .putExtra(EXTRA_MIC_MUTED, muted),
                )
            } catch (_: IllegalStateException) {}
        }

        fun stop(context: Context) {
            try {
                context.startService(
                    Intent(context, CallService::class.java).setAction(ACTION_STOP),
                )
            } catch (_: IllegalStateException) {}
        }

        private const val ACTION_TOGGLE_MUTE_STATE = "dawnchat.call.MUTE_STATE"
    }

    private var channelName: String = "Voice call"
    private var startedAt = 0L
    private var micMuted = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Ongoing calls",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                channelName =
                    intent.getStringExtra(EXTRA_CHANNEL_NAME) ?: "Voice call"
                startedAt = System.currentTimeMillis()
                ServiceCompat.startForeground(
                    this,
                    NOTIFICATION_ID,
                    buildNotification(),
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL or
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    } else {
                        0
                    },
                )
            }

            ACTION_STOP -> {
                ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
                stopSelf(startId)
            }

            ACTION_HANGUP -> eventSink?.success("hangup")

            ACTION_TOGGLE_MUTE -> eventSink?.success("toggleMute")

            ACTION_TOGGLE_MUTE_STATE -> {
                micMuted = intent.getBooleanExtra(EXTRA_MIC_MUTED, micMuted)
                val nm = getSystemService(NotificationManager::class.java)
                nm.notify(NOTIFICATION_ID, buildNotification())
            }
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        val caller = Person.Builder().setName(channelName).setImportant(true).build()

        val hangup = PendingIntent.getService(
            this,
            0,
            Intent(this, CallService::class.java).setAction(ACTION_HANGUP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val mute = PendingIntent.getService(
            this,
            1,
            Intent(this, CallService::class.java).setAction(ACTION_TOGGLE_MUTE),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val open = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(channelName)
            .setContentText("Ongoing call")
            .setStyle(NotificationCompat.CallStyle.forOngoingCall(caller, hangup))
            .addAction(
                android.R.drawable.ic_lock_silent_mode_off,
                if (micMuted) "Unmute" else "Mute",
                mute,
            )
            .addPerson(caller)
            .setContentIntent(open)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(true)
            .setWhen(startedAt)
            .setUsesChronometer(true)
            .setForegroundServiceBehavior(
                NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE,
            )
            .build()
    }
}
