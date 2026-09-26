package com.spudbyte.imu_collector

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.util.Log
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val WATCH_CHANNEL = "com.spudbyte.imu_collector/watch"
        const val PHONE_CHANNEL = "com.spudbyte.imu_collector/phone"
        const val TAG = "IMUCollector"
    }

    private var phoneChannel: MethodChannel? = null

    private val wearReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val payload = intent.getStringExtra(WearDataService.EXTRA_PAYLOAD)
            when (intent.action) {
                WearDataService.ACTION_FILE_LIST ->
                    phoneChannel?.invokeMethod("onWatchFileList", payload ?: "")
                WearDataService.ACTION_SYNC_DONE ->
                    phoneChannel?.invokeMethod("onSyncComplete", null)
                WearDataService.ACTION_FILE_RECEIVED ->
                    phoneChannel?.invokeMethod("onFileReceived", payload)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WATCH_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "listFiles"        -> listFiles(result)
                "deleteFile"       -> deleteFile(call.argument("path"), result)
                "sendFileToPhone"  -> sendFileToPhone(call.argument("path"), result)
                else               -> result.notImplemented()
            }
        }

        phoneChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PHONE_CHANNEL
        ).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getConnectedNodes" -> getConnectedNodes(result)
                    "requestFileList"   -> requestFileList(result)
                    "deleteWatchFile"   -> deleteWatchFile(call.argument("path"), result)
                    "syncAllFiles"      -> syncAllFiles(call.argument<Boolean>("deleteAfterSync") ?: false, result)
                    "listSyncedFiles"   -> listSyncedFiles(result)
                    "deleteSyncedFile"  -> deleteSyncedFile(call.argument("path"), result)
                    else                -> result.notImplemented()
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(WearDataService.ACTION_FILE_LIST)
            addAction(WearDataService.ACTION_SYNC_DONE)
            addAction(WearDataService.ACTION_FILE_RECEIVED)
        }
        LocalBroadcastManager.getInstance(this).registerReceiver(wearReceiver, filter)
    }

    override fun onDestroy() {
        LocalBroadcastManager.getInstance(this).unregisterReceiver(wearReceiver)
        super.onDestroy()
    }

    // ── Watch-side ────────────────────────────────────────────────────────

    private fun listFiles(result: MethodChannel.Result) {
        Thread {
            try {
                val dir = getExternalFilesDir(null) ?: filesDir
                val files = dir.listFiles { f -> f.name.endsWith(".csv") }
                    ?.map { mapOf("name" to it.name, "path" to it.absolutePath, "size" to it.length()) }
                    ?: emptyList()
                runOnUiThread { result.success(files) }
            } catch (e: Exception) {
                runOnUiThread { result.error("LIST_ERROR", e.message, null) }
            }
        }.start()
    }

    private fun deleteFile(path: String?, result: MethodChannel.Result) {
        if (path == null) { result.error("NULL_PATH", "Path is null", null); return }
        Thread {
            val deleted = File(path).delete()
            runOnUiThread {
                if (deleted) result.success(true)
                else result.error("DELETE_ERROR", "Could not delete $path", null)
            }
        }.start()
    }

    private fun sendFileToPhone(path: String?, result: MethodChannel.Result) {
        if (path == null) { result.error("NULL_PATH", "Path is null", null); return }
        Thread {
            try {
                val nodes = Tasks.await(Wearable.getNodeClient(this).connectedNodes)
                if (nodes.isEmpty()) { runOnUiThread { result.error("NO_NODE", "No phone found", null) }; return@Thread }
                val file = File(path)
                if (!file.exists()) { runOnUiThread { result.error("NO_FILE", "Not found: $path", null) }; return@Thread }
                val channelClient = Wearable.getChannelClient(this)
                val channel = Tasks.await(channelClient.openChannel(nodes.first().id, "/imu_file/${file.name}"))
                val out = Tasks.await(channelClient.getOutputStream(channel))
                file.inputStream().use { i -> out.use { o -> i.copyTo(o) } }
                Tasks.await(channelClient.close(channel))
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                Log.e(TAG, "sendFileToPhone", e)
                runOnUiThread { result.error("SEND_ERROR", e.message, null) }
            }
        }.start()
    }

    // ── Phone-side ────────────────────────────────────────────────────────

    private fun getConnectedNodes(result: MethodChannel.Result) {
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                result.success(nodes.map { mapOf("id" to it.id, "displayName" to it.displayName) })
            }
            .addOnFailureListener { result.error("NODE_ERROR", it.message, null) }
    }

    private fun requestFileList(result: MethodChannel.Result) {
        Thread {
            try {
                val nodes = Tasks.await(Wearable.getNodeClient(this).connectedNodes)
                if (nodes.isEmpty()) { runOnUiThread { result.error("NO_NODE", "No watch connected", null) }; return@Thread }
                Tasks.await(Wearable.getMessageClient(this).sendMessage(nodes.first().id, "/list_files", ByteArray(0)))
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("MSG_ERROR", e.message, null) }
            }
        }.start()
    }

    private fun deleteWatchFile(path: String?, result: MethodChannel.Result) {
        if (path == null) { result.error("NULL_PATH", "Path is null", null); return }
        Thread {
            try {
                val nodes = Tasks.await(Wearable.getNodeClient(this).connectedNodes)
                if (nodes.isEmpty()) { runOnUiThread { result.error("NO_NODE", "No watch connected", null) }; return@Thread }
                Tasks.await(Wearable.getMessageClient(this).sendMessage(nodes.first().id, "/delete_file", path.toByteArray()))
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("MSG_ERROR", e.message, null) }
            }
        }.start()
    }

    private fun syncAllFiles(deleteAfterSync: Boolean, result: MethodChannel.Result) {
        Thread {
            try {
                val nodes = Tasks.await(Wearable.getNodeClient(this).connectedNodes)
                if (nodes.isEmpty()) { runOnUiThread { result.error("NO_NODE", "No watch connected", null) }; return@Thread }
                // Tell the watch which files are already on this phone so it skips them.
                val dir = getExternalFilesDir(null) ?: filesDir
                val existing = dir.listFiles { f -> f.name.endsWith(".csv") }
                    ?.joinToString("|") { it.name } ?: ""
                val mode = if (deleteAfterSync) "delete" else "keep"
                val payload = "$mode\n$existing"
                Tasks.await(Wearable.getMessageClient(this).sendMessage(nodes.first().id, "/sync_all", payload.toByteArray()))
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("SYNC_ERROR", e.message, null) }
            }
        }.start()
    }

    private fun listSyncedFiles(result: MethodChannel.Result) {
        Thread {
            try {
                val dir = getExternalFilesDir(null) ?: filesDir
                val files = dir.listFiles { f -> f.name.endsWith(".csv") }
                    ?.map { mapOf("name" to it.name, "path" to it.absolutePath, "size" to it.length()) }
                    ?: emptyList()
                runOnUiThread { result.success(files) }
            } catch (e: Exception) {
                runOnUiThread { result.error("LIST_ERROR", e.message, null) }
            }
        }.start()
    }

    private fun deleteSyncedFile(path: String?, result: MethodChannel.Result) {
        if (path == null) { result.error("NULL_PATH", "Path is null", null); return }
        Thread {
            val deleted = File(path).delete()
            runOnUiThread {
                if (deleted) result.success(true)
                else result.error("DELETE_ERROR", "Could not delete $path", null)
            }
        }.start()
    }
}
