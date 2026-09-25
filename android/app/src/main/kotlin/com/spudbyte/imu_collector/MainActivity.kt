package com.spudbyte.imu_collector

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.ChannelClient
import com.google.android.gms.tasks.Tasks
import android.util.Log
import java.io.File
import java.io.InputStream

class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val WATCH_CHANNEL = "com.spudbyte.imu_collector/watch"
        const val PHONE_CHANNEL = "com.spudbyte.imu_collector/phone"
        const val TAG = "IMUCollector"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Watch-side channel ────────────────────────────────────────────
        // List files, delete files, send files to phone.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WATCH_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "listFiles" -> listFiles(result)

                "deleteFile" -> {
                    val path = call.argument<String>("path")
                    deleteFile(path, result)
                }

                "sendFileToPhone" -> {
                    val path = call.argument<String>("path")
                    sendFileToPhone(path, result)
                }

                else -> result.notImplemented()
            }
        }

        // ── Phone-side channel ────────────────────────────────────────────
        // Connection status, list synced files, delete synced files.
        val phoneChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PHONE_CHANNEL
        )

        phoneChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getConnectedNodes" -> getConnectedNodes(result)

                "requestFileList" -> requestFileList(result)

                "deleteWatchFile" -> {
                    val path = call.argument<String>("path")
                    deleteWatchFile(path, result)
                }

                "syncAllFiles" -> {
                    val deleteAfterSync =
                        call.argument<Boolean>("deleteAfterSync") ?: false

                    syncAllFiles(deleteAfterSync, result)
                }

                "listSyncedFiles" -> listSyncedFiles(result)

                "deleteSyncedFile" -> {
                    val path = call.argument<String>("path")
                    deleteSyncedFile(path, result)
                }

                else -> result.notImplemented()
            }
        }

        // ── WearFileListHolder callbacks ──────────────────────────────────
        // These callbacks receive updates from the Wear OS side and forward
        // them to Flutter through the phone channel.

        WearFileListHolder.onFileListUpdated = {
            runOnUiThread {
                phoneChannel.invokeMethod(
                    "onWatchFileList",
                    WearFileListHolder.lastFileListPayload
                )
            }
        }

        WearFileListHolder.onSyncComplete = {
            runOnUiThread {
                phoneChannel.invokeMethod(
                    "onSyncComplete",
                    null
                )
            }
        }

        WearFileListHolder.onFileReceived = { path ->
            runOnUiThread {
                phoneChannel.invokeMethod(
                    "onFileReceived",
                    path
                )
            }
        }
    }

    // ── Watch-side implementations ───────────────────────────────────────

    private fun listFiles(result: MethodChannel.Result) {
        Thread {
            try {
                val dir = getExternalFilesDir(null) ?: filesDir

                val files = dir.listFiles { f ->
                    f.name.endsWith(".csv")
                }
                    ?.map {
                        mapOf(
                            "name" to it.name,
                            "path" to it.absolutePath,
                            "size" to it.length()
                        )
                    }
                    ?: emptyList()

                runOnUiThread {
                    result.success(files)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error(
                        "LIST_ERROR",
                        e.message,
                        null
                    )
                }
            }
        }.start()
    }

    private fun deleteFile(
        path: String?,
        result: MethodChannel.Result
    ) {
        if (path == null) {
            result.error(
                "NULL_PATH",
                "Path is null",
                null
            )
            return
        }

        Thread {
            val deleted = File(path).delete()

            runOnUiThread {
                if (deleted) {
                    result.success(true)
                } else {
                    result.error(
                        "DELETE_ERROR",
                        "Could not delete $path",
                        null
                    )
                }
            }
        }.start()
    }

    private fun sendFileToPhone(
        path: String?,
        result: MethodChannel.Result
    ) {
        if (path == null) {
            result.error(
                "NULL_PATH",
                "Path is null",
                null
            )
            return
        }

        Thread {
            try {
                val nodes = Tasks.await(
                    Wearable.getNodeClient(this).connectedNodes
                )

                if (nodes.isEmpty()) {
                    runOnUiThread {
                        result.error(
                            "NO_NODE",
                            "No connected phone found",
                            null
                        )
                    }
                    return@Thread
                }

                val file = File(path)

                if (!file.exists()) {
                    runOnUiThread {
                        result.error(
                            "NO_FILE",
                            "File not found: $path",
                            null
                        )
                    }
                    return@Thread
                }

                val nodeId = nodes.first().id

                val channelClient = Wearable.getChannelClient(this)

                val channel = Tasks.await(
                    channelClient.openChannel(
                        nodeId,
                        "/imu_file/${file.name}"
                    )
                )

                val outputStream = Tasks.await(
                    channelClient.getOutputStream(channel)
                )

                file.inputStream().use { input ->
                    outputStream.use { output ->
                        input.copyTo(output)
                    }
                }

                Tasks.await(
                    channelClient.close(channel)
                )

                runOnUiThread {
                    result.success(true)
                }
            } catch (e: Exception) {
                Log.e(
                    TAG,
                    "sendFileToPhone error",
                    e
                )

                runOnUiThread {
                    result.error(
                        "SEND_ERROR",
                        e.message,
                        null
                    )
                }
            }
        }.start()
    }

    // ── Phone-side implementations ───────────────────────────────────────

    private fun getConnectedNodes(
        result: MethodChannel.Result
    ) {
        Wearable.getNodeClient(this)
            .connectedNodes
            .addOnSuccessListener { nodes ->
                val list = nodes.map {
                    mapOf(
                        "id" to it.id,
                        "displayName" to it.displayName
                    )
                }

                result.success(list)
            }
            .addOnFailureListener {
                result.error(
                    "NODE_ERROR",
                    it.message,
                    null
                )
            }
    }

    private fun requestFileList(
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                val nodes = Tasks.await(
                    Wearable.getNodeClient(this).connectedNodes
                )

                if (nodes.isEmpty()) {
                    runOnUiThread {
                        result.error(
                            "NO_NODE",
                            "No watch connected",
                            null
                        )
                    }
                    return@Thread
                }

                val nodeId = nodes.first().id

                Tasks.await(
                    Wearable.getMessageClient(this).sendMessage(
                        nodeId,
                        "/list_files",
                        ByteArray(0)
                    )
                )

                runOnUiThread {
                    result.success(true)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error(
                        "MSG_ERROR",
                        e.message,
                        null
                    )
                }
            }
        }.start()
    }

    private fun deleteWatchFile(
        path: String?,
        result: MethodChannel.Result
    ) {
        if (path == null) {
            result.error(
                "NULL_PATH",
                "Path is null",
                null
            )
            return
        }

        Thread {
            try {
                val nodes = Tasks.await(
                    Wearable.getNodeClient(this).connectedNodes
                )

                if (nodes.isEmpty()) {
                    runOnUiThread {
                        result.error(
                            "NO_NODE",
                            "No watch connected",
                            null
                        )
                    }
                    return@Thread
                }

                val nodeId = nodes.first().id

                Tasks.await(
                    Wearable.getMessageClient(this).sendMessage(
                        nodeId,
                        "/delete_file",
                        path.toByteArray()
                    )
                )

                runOnUiThread {
                    result.success(true)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error(
                        "MSG_ERROR",
                        e.message,
                        null
                    )
                }
            }
        }.start()
    }

    private fun syncAllFiles(
        deleteAfterSync: Boolean,
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                val nodes = Tasks.await(
                    Wearable.getNodeClient(this).connectedNodes
                )

                if (nodes.isEmpty()) {
                    runOnUiThread {
                        result.error(
                            "NO_NODE",
                            "No watch connected",
                            null
                        )
                    }
                    return@Thread
                }

                val nodeId = nodes.first().id

                val payload = if (deleteAfterSync) {
                    "delete"
                } else {
                    "keep"
                }

                Tasks.await(
                    Wearable.getMessageClient(this).sendMessage(
                        nodeId,
                        "/sync_all",
                        payload.toByteArray()
                    )
                )

                runOnUiThread {
                    result.success(true)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error(
                        "SYNC_ERROR",
                        e.message,
                        null
                    )
                }
            }
        }.start()
    }

    private fun listSyncedFiles(
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                val dir = getExternalFilesDir(null) ?: filesDir

                val files = dir.listFiles { f ->
                    f.name.endsWith(".csv")
                }
                    ?.map {
                        mapOf(
                            "name" to it.name,
                            "path" to it.absolutePath,
                            "size" to it.length()
                        )
                    }
                    ?: emptyList()

                runOnUiThread {
                    result.success(files)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error(
                        "LIST_ERROR",
                        e.message,
                        null
                    )
                }
            }
        }.start()
    }

    private fun deleteSyncedFile(
        path: String?,
        result: MethodChannel.Result
    ) {
        if (path == null) {
            result.error(
                "NULL_PATH",
                "Path is null",
                null
            )
            return
        }

        Thread {
            val deleted = File(path).delete()

            runOnUiThread {
                if (deleted) {
                    result.success(true)
                } else {
                    result.error(
                        "DELETE_ERROR",
                        "Could not delete $path",
                        null
                    )
                }
            }
        }.start()
    }
}
