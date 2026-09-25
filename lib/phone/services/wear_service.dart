import 'package:flutter/services.dart';

class WearService {
  static const _channel = MethodChannel('com.spudbyte.imu_collector/phone');

  // Callbacks set by the UI layer
  static void Function(List<WatchFile>)? onWatchFileList;
  static void Function()? onSyncComplete;
  static void Function(String path)? onFileReceived;

  static void init() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onWatchFileList':
          final payload = call.arguments as String? ?? '';
          final files = _parseFileList(payload);
          onWatchFileList?.call(files);
          break;
        case 'onSyncComplete':
          onSyncComplete?.call();
          break;
        case 'onFileReceived':
          final path = call.arguments as String? ?? '';
          onFileReceived?.call(path);
          break;
      }
    });
  }

  static List<WatchFile> _parseFileList(String payload) {
    if (payload.isEmpty) return [];
    return payload.split('|').map((entry) {
      final parts = entry.split('::');
      return WatchFile(
        name: parts[0],
        path: parts[1],
        size: int.tryParse(parts[2]) ?? 0,
      );
    }).toList();
  }

  // Connection
  static Future<List<WearNode>> getConnectedNodes() async {
    final result = await _channel.invokeMethod<List>('getConnectedNodes');
    return (result ?? [])
        .map((e) => WearNode(id: e['id'], displayName: e['displayName']))
        .toList();
  }

  // Watch file operations
  static Future<void> requestFileList() async {
    await _channel.invokeMethod('requestFileList');
  }

  static Future<void> deleteWatchFile(String path) async {
    await _channel.invokeMethod('deleteWatchFile', {'path': path});
  }

  static Future<void> syncAllFiles({required bool deleteAfterSync}) async {
    await _channel.invokeMethod('syncAllFiles', {
      'deleteAfterSync': deleteAfterSync,
    });
  }

  // Phone file operations
  static Future<List<PhoneFile>> listSyncedFiles() async {
    final result = await _channel.invokeMethod<List>('listSyncedFiles');
    return (result ?? [])
        .map(
            (e) => PhoneFile(name: e['name'], path: e['path'], size: e['size']))
        .toList();
  }

  static Future<void> deleteSyncedFile(String path) async {
    await _channel.invokeMethod('deleteSyncedFile', {'path': path});
  }
}

class WearNode {
  final String id;
  final String displayName;
  const WearNode({required this.id, required this.displayName});
}

class WatchFile {
  final String name;
  final String path;
  final int size;
  const WatchFile({required this.name, required this.path, required this.size});
}

class PhoneFile {
  final String name;
  final String path;
  final int size;
  const PhoneFile({required this.name, required this.path, required this.size});
}
