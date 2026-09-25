package com.spudbyte.imu_collector

import android.util.Log
import com.google.android.gms.wearable.ChannelClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import com.google.android.gms.tasks.Tasks
import java.io.File

class WearDataService : WearableListenerService() {

    companion object {
        const val TAG = "WearDataService"
    }

    // Handles messages from the other device
    override fun onMessageReceived(messageEvent: MessageEvent) {
        Log.d(TAG, "Message received: ${messageEvent.path}")
        when (messageEvent.path) {

            // Phone → Watch: list your files and send back
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

            // Phone → Watch: delete a specific file
            "/delete_file" -> {
                val path = String(messageEvent.data)
                File(path).delete()
                Log.d(TAG, "Deleted: $path")
            }

            // Phone → Watch: sync all files, then optionally delete
            "/sync_all" -> {
                val deleteAfterSync = String(messageEvent.data) == "delete"
                val dir = getExternalFilesDir(null) ?: filesDir
                val files = dir.listFiles { f -> f.name.endsWith(".csv") } ?: return
                val channelClient = Wearable.getChannelClient(this)
                for (file in files) {
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
                // Notify phone that sync is complete
                Tasks.await(
                    Wearable.getMessageClient(this).sendMessage(
                        messageEvent.sourceNodeId,
                        "/sync_complete",
                        ByteArray(0)
                    )
                )
            }

            // Watch → Phone: file list response (phone-side receives this)
            "/file_list_response" -> {
                val payload = String(messageEvent.data)
                Log.d(TAG, "File list received: $payload")
                // Broadcast to Flutter via a local broadcast or store for polling
                // MainActivity handles this via the channel
                WearFileListHolder.update(payload)
            }

            // Watch → Phone: sync complete notification
            "/sync_complete" -> {
                WearFileListHolder.notifySyncComplete()
            }
        }
    }

    // Handles incoming file channel (phone receiving a file from watch)
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
                    Log.d(TAG, "Saved received file: ${outFile.absolutePath}")
                    WearFileListHolder.notifyFileReceived(outFile.absolutePath)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to receive file $filename", e)
                }
            }.start()
        }
    }
}
