import 'package:flutter/material.dart';
import '../services/wear_service.dart';

class PhoneFilesScreen extends StatefulWidget {
  const PhoneFilesScreen({super.key});

  @override
  State<PhoneFilesScreen> createState() => _PhoneFilesScreenState();
}

class _PhoneFilesScreenState extends State<PhoneFilesScreen> {
  List<PhoneFile> _files = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WearService.onFileReceived = (_) => _refresh();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await WearService.listSyncedFiles();
      setState(() {
        _files = files;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deleteFile(PhoneFile file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete file'),
        content: Text('Delete ${file.name} from this phone?'),
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
      await WearService.deleteSyncedFile(file.path);
      _refresh();
    } catch (e) {
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

  String _shotTypeFromName(String name) {
    final parts = name.replaceAll('.csv', '').split('_');
    if (parts.length < 3) return name;
    // filename: imu_forehand_drive_20260924_144901.csv
    // drop 'imu' prefix and timestamp (last 2 parts)
    return parts.skip(1).take(parts.length - 3).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${_files.length} file${_files.length == 1 ? '' : 's'} on phone',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loading ? null : _refresh,
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red)))
                  : _files.isEmpty
                      ? const Center(
                          child: Text('No synced files',
                              style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.separated(
                            itemCount: _files.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final file = _files[i];
                              return ListTile(
                                leading: const Icon(Icons.insert_drive_file,
                                    size: 20, color: Colors.tealAccent),
                                title: Text(
                                  _shotTypeFromName(file.name),
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  '${file.name}  ·  ${_formatSize(file.size)}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20, color: Colors.red),
                                  onPressed: () => _deleteFile(file),
                                  tooltip: 'Delete from phone',
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
