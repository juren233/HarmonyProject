package com.krustykrab.petnote

import android.app.Activity
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class PetNoteNativePetPhotoPickerBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "petnote/native_pet_photo_picker"
        private const val PHOTO_DIRECTORY_NAME = "pet_photos"
    }

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var pendingResult: MethodChannel.Result? = null
    private val pickerLauncher =
        (activity as androidx.activity.ComponentActivity).registerForActivityResult(
            ActivityResultContracts.PickVisualMedia(),
        ) { uri ->
            handlePickedUri(uri)
        }
    private val multiplePickerLauncher =
        (activity as androidx.activity.ComponentActivity).registerForActivityResult(
            ActivityResultContracts.PickMultipleVisualMedia(),
        ) { uris ->
            handlePickedUris(uris)
        }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickPetPhoto" -> {
                if (pendingResult != null) {
                    result.success(
                        errorPayload(
                            errorCode = "invalidResponse",
                            message = "Another native pet photo request is already running.",
                        ),
                    )
                    return
                }
                pendingResult = result
                pickerLauncher.launch(
                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                )
            }

            "pickPetPhotos" -> {
                if (pendingResult != null) {
                    result.success(
                        errorPayload(
                            errorCode = "invalidResponse",
                            message = "Another native pet photo request is already running.",
                        ),
                    )
                    return
                }
                pendingResult = result
                multiplePickerLauncher.launch(
                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                )
            }

            "deletePetPhoto" -> {
                val arguments = call.arguments as? Map<*, *>
                val path = arguments?.get("path") as? String
                deletePetPhoto(path)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun handlePickedUri(uri: Uri?) {
        val result = pendingResult ?: return
        pendingResult = null
        if (uri == null) {
            result.success(cancelledPayload())
            return
        }

        try {
            val localPath = copyToSandbox(uri)
            result.success(successPayload(localPath))
        } catch (error: Exception) {
            result.success(
                errorPayload(
                    errorCode = "platformError",
                    message = error.message ?: "Failed to import the selected photo.",
                ),
            )
        }
    }

    private fun handlePickedUris(uris: List<Uri>) {
        val result = pendingResult ?: return
        pendingResult = null
        if (uris.isEmpty()) {
            result.success(cancelledPayload())
            return
        }

        try {
            val localPaths = uris.map { uri -> copyToSandbox(uri) }
            result.success(successPayload(localPaths))
        } catch (error: Exception) {
            result.success(
                errorPayload(
                    errorCode = "platformError",
                    message = error.message ?: "Failed to import the selected photos.",
                ),
            )
        }
    }

    private fun copyToSandbox(uri: Uri): String {
        val directory = File(activity.filesDir, PHOTO_DIRECTORY_NAME).apply {
            if (!exists()) {
                mkdirs()
            }
        }
        val extension = resolveFileExtension(uri)
        val target = File(
            directory,
            "pet_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}.$extension",
        )

        activity.contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(target).use { output ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Unable to read the selected photo URI.")

        return target.absolutePath
    }

    private fun resolveFileExtension(uri: Uri): String {
        val displayName = queryDisplayName(uri)
        if (!displayName.isNullOrBlank() && displayName.contains('.')) {
            return displayName.substringAfterLast('.').lowercase().ifBlank { "jpg" }
        }
        val mimeType = activity.contentResolver.getType(uri)
        return when (mimeType) {
            "image/png" -> "png"
            "image/webp" -> "webp"
            "image/heic" -> "heic"
            "image/heif" -> "heif"
            else -> "jpg"
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        val cursor: Cursor? = activity.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )
        cursor?.use {
            if (it.moveToFirst()) {
                val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    return it.getString(index)
                }
            }
        }
        return null
    }

    private fun deletePetPhoto(path: String?) {
        if (path.isNullOrBlank()) {
            return
        }
        val directory = File(activity.filesDir, PHOTO_DIRECTORY_NAME)
        val target = File(path)
        val safeDirectoryPath = directory.canonicalFile.absolutePath
        val safeTargetPath = try {
            target.canonicalFile.absolutePath
        } catch (_: Exception) {
            return
        }
        if (!safeTargetPath.startsWith(safeDirectoryPath)) {
            return
        }
        if (target.exists()) {
            target.delete()
        }
    }

    private fun successPayload(localPath: String): Map<String, Any?> {
        return mapOf(
            "status" to "success",
            "localPath" to localPath,
        )
    }

    private fun successPayload(localPaths: List<String>): Map<String, Any?> {
        return mapOf(
            "status" to "success",
            "localPaths" to localPaths,
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
}
