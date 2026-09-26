import 'package:flutter/material.dart';
import '../services/wear_service.dart';

class WatchFilesScreen extends StatefulWidget {
  final bool watchConnected;
  const WatchFilesScreen({super.key, required this.watchConnected});

  @override
  State<WatchFilesScreen> createState() => _WatchFilesScreenState();
}

class _WatchFilesScreenState extends State<WatchFilesScreen> {
  List<WatchFile> _files = [];
  Set<String> _syncedNames = {};
  bool _loading = false;
  bool _syncing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WearService.onWatchFileList = (files) {
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    };
    WearService.onSyncComplete = () {
      if (mounted) {
        setState(() => _syncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync complete')),
        );
        _refresh();
      }
    };
    if (widget.watchConnected) _refresh();
  }

  @override
  void didUpdateWidget(WatchFilesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.watchConnected && widget.watchConnected) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!widget.watchConnected) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Load names already on this phone so we can flag synced watch files.
      final synced = await WearService.listSyncedFiles();
      if (mounted) {
        setState(() => _syncedNames = synced.map((f) => f.name).toSet());
      }
      await WearService.requestFileList();
      // Response comes back via WearService.onWatchFileList callback.
      // If the watch never replies, stop the spinner and show an error.
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted && _loading) {
          setState(() {
            _loading = false;
            _error = 'No response from watch. Is the app open on the watch?';
          });
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deleteFile(WatchFile file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete file'),
        content: Text('Delete ${file.name} from watch?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await WearService.deleteWatchFile(file.path);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _syncAll() async {
    bool deleteAfterSync = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Sync all files'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Copy all watch files to this phone?'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteAfterSync,
                onChanged: (v) =>
                    setDialogState(() => deleteAfterSync = v ?? false),
                title: const Text('Delete from watch after sync'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sync')),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    setState(() => _syncing = true);
    try {
      await WearService.syncAllFiles(deleteAfterSync: deleteAfterSync);
    } catch (e) {
      setState(() => _syncing = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.watchConnected) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.watch_off_rounded, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('Watch not connected', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 8),
            Text(
              'Make sure your watch is nearby\nand the IMU Collector app is open.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // ── Toolbar ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${_files.length} file${_files.length == 1 ? '' : 's'} on watch',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const Spacer(),
              if (_syncing)
                const Row(children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Syncing...', style: TextStyle(fontSize: 12)),
                ])
              else ...[
                IconButton(
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh',
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: _files.isEmpty ? null : _syncAll,
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Sync all'),
                ),
              ],
            ],
          ),
        ),

        const Divider(height: 1),

        // ── File list ─────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red)))
                  : _files.isEmpty
                      ? const Center(
                          child: Text('No files on watch',
                              style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.separated(
                            itemCount: _files.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final file = _files[i];
                              final synced = _syncedNames.contains(file.name);
                              return ListTile(
                                leading: Icon(
                                    synced
                                        ? Icons.cloud_done
                                        : Icons.insert_drive_file_outlined,
                                    size: 20,
                                    color: synced ? Colors.green : null),
                                title: Text(
                                  file.name,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Row(
                                  children: [
                                    Text(
                                      _formatSize(file.size),
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.grey),
                                    ),
                                    if (synced) ...[
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Synced',
                                        style: TextStyle(
                                            fontSize: 11, color: Colors.green),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20, color: Colors.red),
                                  onPressed: () => _deleteFile(file),
                                  tooltip: 'Delete from watch',
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
