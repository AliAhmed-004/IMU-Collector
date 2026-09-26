package com.spudbyte.imu_collector

import android.content.Intent
import android.util.Log
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.google.android.gms.wearable.ChannelClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import com.google.android.gms.tasks.Tasks
import java.io.File

class WearDataService : WearableListenerService() {

    companion object {
        const val TAG = "WearDataService"
        const val ACTION_FILE_LIST   = "com.spudbyte.imu_collector.FILE_LIST"
        const val ACTION_SYNC_DONE   = "com.spudbyte.imu_collector.SYNC_DONE"
        const val ACTION_FILE_RECEIVED = "com.spudbyte.imu_collector.FILE_RECEIVED"
        const val EXTRA_PAYLOAD      = "payload"
    }

    private fun broadcast(action: String, payload: String? = null) {
        val intent = Intent(action)
        if (payload != null) intent.putExtra(EXTRA_PAYLOAD, payload)
        LocalBroadcastManager.getInstance(this).sendBroadcast(intent)
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        Log.d(TAG, "Message received: ${messageEvent.path}")
        when (messageEvent.path) {

            "/list_files" -> {
                val dir = getExternalFilesDir(null) ?: filesDir
                val files = dir.listFiles { f -> f.name.endsWith(".csv") }
                    ?.joinToString("|") { "${it.name}::${it.absolutePath}::${it.length()}" }
                    ?: ""
                Tasks.await(
                    Wearable.getMessageClient(this).sendMessage(
                        messageEvent.sourceNodeId,
                        "/file_list_response",
                        files.toByteArray()
                    )
                )
            }

            "/delete_file" -> {
                val path = String(messageEvent.data)
                File(path).delete()
                Log.d(TAG, "Deleted: $path")
            }

            "/sync_all" -> {
                val parts = String(messageEvent.data).split("\n", limit = 2)
                val deleteAfterSync = parts[0] == "delete"
                val skip = if (parts.size > 1 && parts[1].isNotEmpty())
                    parts[1].split("|").toSet() else emptySet()
                val dir = getExternalFilesDir(null) ?: filesDir
                val files = dir.listFiles { f -> f.name.endsWith(".csv") } ?: return
                val channelClient = Wearable.getChannelClient(this)
                for (file in files) {
                    if (file.name in skip) {
                        Log.d(TAG, "Skip already-synced ${file.name}")
                        continue
                    }
                    try {
                        val channel = Tasks.await(
                            channelClient.openChannel(
                                messageEvent.sourceNodeId,
                                "/imu_file/${file.name}"
                            )
                        )
                        val outputStream = Tasks.await(channelClient.getOutputStream(channel))
                        file.inputStream().use { input ->
                            outputStream.use { output -> input.copyTo(output) }
                        }
                        Tasks.await(channelClient.close(channel))
                        if (deleteAfterSync) file.delete()
                        Log.d(TAG, "Synced: ${file.name}")
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to sync ${file.name}", e)
                    }
                }
                Tasks.await(
                    Wearable.getMessageClient(this).sendMessage(
                        messageEvent.sourceNodeId,
                        "/sync_complete",
                        ByteArray(0)
                    )
                )
            }

            "/file_list_response" -> {
                val payload = String(messageEvent.data)
                Log.d(TAG, "File list received: $payload")
                broadcast(ACTION_FILE_LIST, payload)
            }

            "/sync_complete" -> {
                broadcast(ACTION_SYNC_DONE)
            }
        }
    }

    override fun onChannelOpened(channel: ChannelClient.Channel) {
        Log.d(TAG, "Channel opened: ${channel.path}")
        if (channel.path.startsWith("/imu_file/")) {
            val filename = channel.path.removePrefix("/imu_file/")
            Thread {
                try {
                    val channelClient = Wearable.getChannelClient(this)
                    val inputStream = Tasks.await(channelClient.getInputStream(channel))
                    val dir = getExternalFilesDir(null) ?: filesDir
                    val outFile = File(dir, filename)
                    inputStream.use { input ->
                        outFile.outputStream().use { output -> input.copyTo(output) }
                    }
                    Tasks.await(channelClient.close(channel))
                    Log.d(TAG, "Saved: ${outFile.absolutePath}")
                    broadcast(ACTION_FILE_RECEIVED, outFile.absolutePath)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to receive file $filename", e)
                }
            }.start()
        }
    }
}
