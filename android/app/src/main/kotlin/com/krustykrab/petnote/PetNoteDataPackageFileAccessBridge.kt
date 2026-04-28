package com.krustykrab.petnote

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class PetNoteDataPackageFileAccessBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "petnote/data_package_file_access"
        private const val REQUEST_CODE = 12041
        private const val IMPORT_CACHE_DIRECTORY_NAME = "data_package_imports"
    }

    private enum class RequestKind {
        PICK_BACKUP,
        SAVE_BACKUP,
    }

    private data class PendingRequest(
        val kind: RequestKind,
        val sourceFilePath: String? = null,
    )

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var pendingResult: MethodChannel.Result? = null
    private var pendingRequest: PendingRequest? = null

    fun handleActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != REQUEST_CODE) {
            return false
        }

        val request = pendingRequest ?: return false
        pendingRequest = null

        if (resultCode != Activity.RESULT_OK) {
            finishPendingRequest(cancelledPayload())
            return true
        }

        val uri = data?.data
        if (uri == null) {
            finishPendingRequest(
                errorPayload(
                    errorCode = "invalidResponse",
                    message = "System file manager did not return a document URI.",
                ),
            )
            return true
        }

        ioExecutor.execute {
            val payload = try {
                when (request.kind) {
                    RequestKind.PICK_BACKUP -> readPickedFile(uri)

                    RequestKind.SAVE_BACKUP -> writeBackupFile(
                        uri = uri,
                        sourceFilePath = request.sourceFilePath.orEmpty(),
                    )
                }
            } catch (error: Throwable) {
                errorPayload(
                    errorCode = when (request.kind) {
                        RequestKind.SAVE_BACKUP -> "writeFailed"
                        else -> "readFailed"
                    },
                    message = error.message ?: "Unknown file manager error.",
                )
            }
            activity.runOnUiThread {
                finishPendingRequest(payload)
            }
        }
        return true
    }

    init {
        channel.setMethodCallHandler(this)
    }

    fun close() {
        channel.setMethodCallHandler(null)
        ioExecutor.shutdown()
        pendingResult = null
        pendingRequest = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.success(
                errorPayload(
                    errorCode = "invalidResponse",
                    message = "Another file manager request is already in progress.",
                ),
            )
            return
        }

        when (call.method) {
            "pickBackupFile" -> launchOpenDocument(
                result = result,
                kind = RequestKind.PICK_BACKUP,
            )

            "saveBackupFile" -> {
                val arguments = call.arguments as? Map<*, *>
                val suggestedFileName = arguments?.get("suggestedFileName") as? String
                val sourceFilePath = arguments?.get("sourceFilePath") as? String
                if (suggestedFileName.isNullOrBlank() || sourceFilePath.isNullOrBlank()) {
                    result.success(
                        errorPayload(
                            errorCode = "invalidResponse",
                            message = "Missing suggestedFileName or sourceFilePath.",
                        ),
                    )
                    return
                }
                launchCreateDocument(
                    result = result,
                    suggestedFileName = suggestedFileName,
                    sourceFilePath = sourceFilePath,
                )
            }

            else -> result.notImplemented()
        }
    }

    private fun launchOpenDocument(
        result: MethodChannel.Result,
        kind: RequestKind,
    ) {
        pendingResult = result
        pendingRequest = PendingRequest(kind = kind)
        activity.startActivityForResult(
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
            },
            REQUEST_CODE,
        )
    }

    private fun launchCreateDocument(
        result: MethodChannel.Result,
        suggestedFileName: String,
        sourceFilePath: String,
    ) {
        pendingResult = result
        pendingRequest = PendingRequest(
            kind = RequestKind.SAVE_BACKUP,
            sourceFilePath = sourceFilePath,
        )
        activity.startActivityForResult(
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, suggestedFileName)
            },
            REQUEST_CODE,
        )
    }

    private fun readPickedFile(uri: Uri): Map<String, Any?> {
        takePersistablePermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val displayName = queryDisplayName(uri) ?: uri.lastPathSegment ?: "selected.json"
        val directory = File(activity.cacheDir, IMPORT_CACHE_DIRECTORY_NAME).apply {
            mkdirs()
        }
        val localFile = File(directory, "${System.currentTimeMillis()}_${displayName.sanitizeFileName()}")
        activity.contentResolver.openInputStream(uri)?.use { input ->
            localFile.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Unable to open selected file.")

        return successPayload(
            displayName = displayName,
            locationLabel = uri.authority ?: uri.scheme ?: "Documents",
            byteLength = localFile.length(),
            localFilePath = localFile.absolutePath,
        )
    }

    private fun writeBackupFile(
        uri: Uri,
        sourceFilePath: String,
    ): Map<String, Any?> {
        takePersistablePermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
        val sourceFile = File(sourceFilePath)
        if (!sourceFile.isFile) {
            throw IllegalStateException("Backup source file is not readable.")
        }
        val byteLength = sourceFile.length()
        sourceFile.inputStream().use { input ->
            activity.contentResolver.openOutputStream(uri, "wt")?.use { output ->
                input.copyTo(output)
            } ?: throw IllegalStateException("Unable to open destination file.")
        }

        val displayName = queryDisplayName(uri) ?: uri.lastPathSegment ?: "backup.json"
        return successPayload(
            displayName = displayName,
            locationLabel = uri.authority ?: uri.scheme ?: "Documents",
            byteLength = byteLength,
        )
    }

    private fun queryDisplayName(uri: Uri): String? {
        return activity.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) {
                cursor.getString(index)
            } else {
                null
            }
        }
    }

    private fun takePersistablePermission(uri: Uri, flags: Int) {
        try {
            activity.contentResolver.takePersistableUriPermission(uri, flags)
        } catch (_: SecurityException) {
            return
        } catch (_: UnsupportedOperationException) {
            return
        }
    }

    private fun finishPendingRequest(payload: Map<String, Any?>) {
        val callback = pendingResult ?: return
        pendingResult = null
        callback.success(payload)
    }

    private fun successPayload(
        displayName: String,
        locationLabel: String,
        byteLength: Long,
        localFilePath: String? = null,
    ): Map<String, Any?> {
        return mutableMapOf<String, Any?>(
            "status" to "success",
            "displayName" to displayName,
            "locationLabel" to locationLabel,
            "byteLength" to byteLength,
            "localFilePath" to localFilePath,
        )
    }

    private fun cancelledPayload(): Map<String, Any?> {
        return mapOf(
            "status" to "cancelled",
            "errorCode" to "cancelled",
        )
    }

    private fun errorPayload(
        errorCode: String,
        message: String,
    ): Map<String, Any?> {
        return mapOf(
            "status" to "error",
            "errorCode" to errorCode,
            "errorMessage" to message,
        )
    }

    private fun String.sanitizeFileName(): String {
        return replace(Regex("[\\\\/:*?\"<>|]"), "_").ifBlank { "selected.json" }
    }
}
