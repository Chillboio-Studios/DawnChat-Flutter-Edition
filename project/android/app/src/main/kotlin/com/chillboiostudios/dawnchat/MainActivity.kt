package com.chillboiostudios.dawnchat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dawnchat/call_service",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    CallService.start(
                        this,
                        call.argument<String>("channelId") ?: "",
                        call.argument<String>("channelName"),
                    )
                    result.success(null)
                }
                "stop" -> {
                    CallService.stop(this)
                    result.success(null)
                }
                "setMicMuted" -> {
                    CallService.updateMicMuted(
                        this,
                        call.argument<Boolean>("muted") ?: false,
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dawnchat/clipboard",
        ).setMethodCallHandler { call, result ->
            ClipboardReader.handle(this, call, result)
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dawnchat/call_events",
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    CallService.eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    CallService.eventSink = null
                }
            },
        )
    }
}
