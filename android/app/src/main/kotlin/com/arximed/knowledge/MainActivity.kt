package com.arximed.knowledge

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Hands text and photos shared into Bilig ("Share → Bilig") to Dart. */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** What was shared to start the app, until Dart takes it. */
    private var pending: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pending = readShare(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bilig/share").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "takeInitial") {
                    result.success(pending)
                    pending = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val shared = readShare(intent) ?: return
        channel?.invokeMethod("shared", shared)
    }

    private fun readShare(intent: Intent?): Map<String, Any?>? {
        if (intent?.action != Intent.ACTION_SEND) return null
        val type = intent.type ?: return null
        if (type.startsWith("text/")) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
            val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
            // Browsers share a page as "title" + "url"; keep both.
            val joined = if (subject != null && !text.contains(subject)) "$subject\n$text" else text
            return mapOf("text" to joined)
        }
        val uri: Uri? = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
        val bytes = uri?.let {
            try {
                contentResolver.openInputStream(it)?.use { s -> s.readBytes() }
            } catch (e: Exception) {
                null
            }
        } ?: return null
        if (type.startsWith("image/")) return mapOf("image" to bytes)
        // Any other file: a .bilig shared by a classmate, an Anki deck…
        return mapOf("file" to bytes, "name" to displayName(uri))
    }

    private fun displayName(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst()) return c.getString(0) ?: "" }
        return uri.lastPathSegment ?: ""
    }
}
