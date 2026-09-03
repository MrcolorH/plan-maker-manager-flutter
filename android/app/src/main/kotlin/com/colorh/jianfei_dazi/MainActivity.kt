package com.colorh.jianfei_dazi

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * 备份导出支持：把备份文本写入手机公共「Download」目录。
 * - Android 10（API 29）及以上：通过 MediaStore 写入，无需任何存储权限
 * - Android 9 及以下：需要 WRITE_EXTERNAL_STORAGE 运行时权限，直接写文件
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val BACKUP_CHANNEL = "com.colorh.jianfei_dazi/backup"
        private const val REQ_WRITE_STORAGE = 1001
        private const val MIME_TEXT = "text/plain"
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingTask: SaveTask? = null

    private data class SaveTask(val fileName: String, val content: String)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val name = call.argument<String>("fileName")
                        val content = call.argument<String>("content")
                        if (name.isNullOrEmpty() || content == null) {
                            result.error("ARG", "fileName / content 不能为空", null)
                            return@setMethodCallHandler
                        }
                        saveToDownloads(SaveTask(name, content), result)
                    }

                    "downloadsPath" -> result.success(publicDownloadsPath())

                    "readFromDownloads" -> {
                        val name = call.argument<String>("fileName")
                        if (name.isNullOrEmpty()) {
                            result.error("ARG", "fileName 不能为空", null)
                            return@setMethodCallHandler
                        }
                        result.success(readFromDownloads(name))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToDownloads(task: SaveTask, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                result.success(writeViaMediaStore(task))
            } catch (e: Exception) {
                result.error("WRITE_FAILED", e.message ?: "写入 Download 目录失败", null)
            }
            return
        }
        if (hasWritePermission()) {
            try {
                result.success(writeViaFile(task))
            } catch (e: Exception) {
                result.error("WRITE_FAILED", e.message ?: "写入 Download 目录失败", null)
            }
            return
        }
        pendingResult = result
        pendingTask = task
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            REQ_WRITE_STORAGE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_WRITE_STORAGE) return
        val result = pendingResult ?: return
        val task = pendingTask ?: return
        pendingResult = null
        pendingTask = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            try {
                result.success(writeViaFile(task))
            } catch (e: Exception) {
                result.error("WRITE_FAILED", e.message ?: "写入 Download 目录失败", null)
            }
        } else {
            result.error("PERMISSION_DENIED", "需要存储权限才能保存到 Download 目录", null)
        }
    }

    private fun hasWritePermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED

    private fun writeViaFile(task: SaveTask): String {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!dir.exists() && !dir.mkdirs()) throw IOException("无法创建 Download 目录")
        val file = File(dir, task.fileName)
        file.writeText(task.content, Charsets.UTF_8)
        return file.absolutePath
    }

    private fun writeViaMediaStore(task: SaveTask): String {
        val resolver = contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI

        // 同名文件直接覆盖，避免系统自动生成 "xxx (1).txt"
        val existing = findExistingUri(collection, task.fileName)
        if (existing != null) {
            resolver.openOutputStream(existing, "w")?.use {
                it.write(task.content.toByteArray(Charsets.UTF_8))
            } ?: throw IOException("写入文件失败")
            return "${publicDownloadsPath()}/${task.fileName}"
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, task.fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, MIME_TEXT)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: throw IOException("创建文件失败")
        try {
            resolver.openOutputStream(uri)?.use {
                it.write(task.content.toByteArray(Charsets.UTF_8))
            } ?: throw IOException("写入文件失败")
        } finally {
            val done = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, done, null, null)
        }
        return "${publicDownloadsPath()}/${task.fileName}"
    }

    private fun findExistingUri(collection: Uri, displayName: String): Uri? {
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection =
            "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?"
        val args = arrayOf(displayName, "${Environment.DIRECTORY_DOWNLOADS}/")
        contentResolver.query(collection, projection, selection, args, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID))
                return ContentUris.withAppendedId(collection, id)
            }
        }
        return null
    }

    private fun publicDownloadsPath(): String =
        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).path

    /**
     * 读取公共 Download 目录下的备份文本（自动备份恢复用），不存在或不可读返回 null。
     * Android 10+：优先按 MediaStore 查文件名（本应用写入的文件可直接读）；
     * Android 9 及以下：直接读文件路径。
     * 任何异常（跨设备拷贝来的文件无归属权限等）都按「无备份」处理，由 Dart 层降级。
     */
    private fun readFromDownloads(displayName: String): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val uri = findExistingUri(MediaStore.Downloads.EXTERNAL_CONTENT_URI, displayName)
                    ?: return null
                contentResolver.openInputStream(uri)?.use {
                    it.readBytes().toString(Charsets.UTF_8)
                }
            } else {
                val file = File(publicDownloadsPath(), displayName)
                if (file.exists()) file.readText(Charsets.UTF_8) else null
            }
        } catch (e: Exception) {
            null
        }
    }
}
