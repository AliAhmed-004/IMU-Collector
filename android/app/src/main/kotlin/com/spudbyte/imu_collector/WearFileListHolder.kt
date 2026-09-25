package com.spudbyte.imu_collector

object WearFileListHolder {
    var lastFileListPayload: String = ""
    var onFileListUpdated: (() -> Unit)? = null
    var onSyncComplete: (() -> Unit)? = null
    var onFileReceived: ((String) -> Unit)? = null

    fun update(payload: String) {
        lastFileListPayload = payload
        onFileListUpdated?.invoke()
    }

    fun notifySyncComplete() {
        onSyncComplete?.invoke()
    }

    fun notifyFileReceived(path: String) {
        onFileReceived?.invoke(path)
    }
}
