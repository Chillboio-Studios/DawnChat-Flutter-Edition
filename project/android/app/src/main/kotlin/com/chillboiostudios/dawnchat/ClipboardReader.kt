package com.chillboiostudios.dawnchat

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/// Robust clipboard reader — the pasteboard plugin only handles
/// ClipData.Item.uri on the first item, which misses intents, text
/// URIs and multi-item clips that many apps produce.
object ClipboardReader {
    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readImage" -> result.success(readImage(context))
            "readFiles" -> result.success(readFiles(context))
            else -> result.notImplemented()
        }
    }

    private fun clipItems(context: Context): List<Uri> {
        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            ?: return emptyList()
        val clip = cm.primaryClip ?: return emptyList()
        val uris = mutableListOf<Uri>()
        for (i in 0 until clip.itemCount) {
            val item = clip.getItemAt(i)
            @Suppress("DEPRECATION")
            val uri = item.uri
                ?: (item.intent?.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri)
                ?: item.text?.toString()?.let { text ->
                    val t = text.trim()
                    if (t.startsWith("content://") || t.startsWith("file://")) {
                        runCatching { Uri.parse(t) }.getOrNull()
                    } else {
                        null
                    }
                }
            if (uri != null) uris.add(uri)
        }
        return uris
    }

    private fun displayName(context: Context, uri: Uri): String? {
        if (uri.scheme == "content") {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { c ->
                if (c.moveToFirst()) {
                    val name = c.getString(0)
                    if (!name.isNullOrEmpty()) return name
                }
            }
        }
        return uri.lastPathSegment
    }

    private fun mimeOf(context: Context, uri: Uri): String? =
        context.contentResolver.getType(uri)
            ?: displayName(context, uri)?.let {
                android.webkit.MimeTypeMap.getSingleton()
                    .getMimeTypeFromExtension(it.substringAfterLast('.', "").lowercase())
            }

    /// First image found on the clipboard, or null.
    /// Returns mapOf("bytes" to ByteArray, "mime" to String, "name" to String).
    private fun readImage(context: Context): Map<String, Any>? {
        val cr = context.contentResolver
        for (uri in clipItems(context)) {
            val mime = mimeOf(context, uri) ?: continue
            if (!mime.startsWith("image/")) continue
            val bytes = runCatching {
                cr.openInputStream(uri)?.use { it.readBytes() }
            }.getOrNull() ?: continue
            if (bytes.isEmpty()) continue
            val name = displayName(context, uri)
                ?: "clipboard.${mime.substringAfter('/')}.png"
            return mapOf("bytes" to bytes, "mime" to mime, "name" to name)
        }
        return null
    }

    /// Non-image files on the clipboard, copied into the app cache so
    /// Dart can read them as plain files.
    /// Returns List<Map("path","name","mime","size")>.
    private fun readFiles(context: Context): List<Map<String, Any>> {
        val cr = context.contentResolver
        val dir = File(context.cacheDir, "clipboard").apply { mkdirs() }
        val out = mutableListOf<Map<String, Any>>()
        for (uri in clipItems(context)) {
            val mime = mimeOf(context, uri) ?: continue
            if (mime.startsWith("image/")) continue
            val name = displayName(context, uri) ?: "file_${UUID.randomUUID()}"
            val safe = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
            val dest = File(dir, "${System.currentTimeMillis()}_$safe")
            val ok = runCatching {
                cr.openInputStream(uri)?.use { input ->
                    FileOutputStream(dest).use { output -> input.copyTo(output) }
                } != null
            }.getOrDefault(false)
            if (!ok || !dest.exists() || dest.length() == 0L) continue
            out.add(
                mapOf(
                    "path" to dest.absolutePath,
                    "name" to name,
                    "mime" to mime,
                    "size" to dest.length(),
                ),
            )
        }
        return out
    }
}
