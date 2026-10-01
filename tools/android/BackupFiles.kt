package com.wanderlust.wanderlust

import android.app.Activity
import android.content.Intent
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Stream large backups through Android's document picker, never the method codec. */
class BackupFiles(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var source: File? = null
    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var cancelled = false
    private val limit = 2L * 1024 * 1024 * 1024

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancel") {
            cancelled = true
            result.success(null)
            return
        }
        if (call.method != "pick" && call.method != "save") {
            result.notImplemented()
            return
        }
        if (pending != null) {
            result.error("busy", "A document operation is already running.", null)
            return
        }
        cancelled = false
        try {
            val saving = call.method == "save"
            source = if (saving) File(requireNotNull(call.argument<String>("path"))).canonicalFile else null
            source?.let {
                // Flutter can use codeCacheDir for Directory.systemTemp on Android.
                require(listOf(activity.cacheDir, activity.codeCacheDir).any { root ->
                    it.path.startsWith(root.canonicalPath + File.separator)
                })
                require(it.isFile && it.length() <= limit)
            }
            val intent = Intent(if (saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType(if (saving) "application/octet-stream" else "*/*")
            if (saving) intent.putExtra(Intent.EXTRA_TITLE, "wanderlust-backup.wanderlust")
            pending = result
            activity.startActivityForResult(intent, if (saving) 4202 else 4201)
        } catch (error: Exception) {
            pending = null
            source = null
            result.error("document", "Could not open the document picker.", null)
        }
    }

    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != 4201 && request != 4202) return false
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null || cancelled) {
            finish(null)
            return true
        }
        val saving = request == 4202
        val inputFile = source
        executor.execute {
            var temporary: File? = null
            try {
                if (!saving) temporary = File.createTempFile("wanderlust-import-", ".backup", activity.cacheDir)
                val input = if (saving) requireNotNull(inputFile).inputStream()
                    else requireNotNull(activity.contentResolver.openInputStream(uri))
                input.use { from ->
                    val output = if (saving) requireNotNull(activity.contentResolver.openOutputStream(uri, "wt"))
                        else requireNotNull(temporary).outputStream()
                    output.use { to ->
                        val buffer = ByteArray(64 * 1024)
                        var total = 0L
                        while (true) {
                            if (cancelled) throw InterruptedException()
                            val read = from.read(buffer)
                            if (read < 0) break
                            total += read
                            require(total <= limit)
                            to.write(buffer, 0, read)
                        }
                    }
                }
                if (cancelled) throw InterruptedException()
                val value = if (saving) "saved" else requireNotNull(temporary).path
                activity.runOnUiThread { finish(value) }
            } catch (error: Exception) {
                temporary?.delete()
                if (saving) {
                    try { DocumentsContract.deleteDocument(activity.contentResolver, uri) } catch (_: Exception) {}
                }
                activity.runOnUiThread {
                    if (cancelled) finish(null)
                    else {
                        pending?.error("document", "Could not copy backup. Check file access and free space.", null)
                        pending = null
                        source = null
                    }
                }
            }
        }
        return true
    }

    private fun finish(value: String?) {
        pending?.success(value)
        pending = null
        source = null
    }

    fun close() {
        cancelled = true
        finish(null)
        executor.shutdown()
    }
}
