import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;

class FileEvent {
  final String filePath;
  final FileSystemEventType type;
  final DateTime timestamp;

  FileEvent({
    required this.filePath,
    required this.type,
    required this.timestamp,
  });
}

enum FileSystemEventType {
  create,
  modify,
  delete,
}

class FileWatcherService {
  final String watchPath;
  final StreamController<FileEvent> _eventController =
      StreamController<FileEvent>.broadcast();

  Stream<FileEvent> get eventStream => _eventController.stream;

  final Map<String, DateTime> _fileTimestamps = {};
  Timer? _scanTimer;

  FileWatcherService({required this.watchPath});

  Future<void> start() async {
    // 初始扫描现有文件
    await _scanDirectory();

    // 定期扫描以检测变化
    _scanTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _scanDirectory();
    });
  }

  Future<void> stop() async {
    _scanTimer?.cancel();
  }

  Future<void> _scanDirectory() async {
    final directory = Directory(watchPath);
    if (!await directory.exists()) return;

    final currentFiles = <String, DateTime>{};

    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        final filePath = entity.path;
        final fileName = path.basename(filePath);

        // 忽略隐藏文件和临时文件
        if (fileName.startsWith('.') || fileName.endsWith('.tmp')) {
          continue;
        }

        try {
          final stat = await entity.stat();
          currentFiles[filePath] = stat.modified;

          // 检查是否是新文件或修改过的文件
          if (!_fileTimestamps.containsKey(filePath)) {
            _eventController.add(FileEvent(
              filePath: filePath,
              type: FileSystemEventType.create,
              timestamp: DateTime.now(),
            ));
          } else if (_fileTimestamps[filePath] != stat.modified) {
            _eventController.add(FileEvent(
              filePath: filePath,
              type: FileSystemEventType.modify,
              timestamp: DateTime.now(),
            ));
          }
        } catch (e) {
          // 忽略无法访问的文件
        }
      }
    }

    // 检查删除的文件
    for (final filePath in _fileTimestamps.keys) {
      if (!currentFiles.containsKey(filePath)) {
        _eventController.add(FileEvent(
          filePath: filePath,
          type: FileSystemEventType.delete,
          timestamp: DateTime.now(),
        ));
      }
    }

    _fileTimestamps.clear();
    _fileTimestamps.addAll(currentFiles);
  }

  // 获取文件的相对路径
  String getRelativePath(String filePath) {
    return path.relative(filePath, from: watchPath);
  }

  // 检查文件是否应该被同步
  bool shouldSyncFile(String filePath) {
    final fileName = path.basename(filePath);

    // 忽略隐藏文件
    if (fileName.startsWith('.')) return false;

    // 忽略临时文件
    if (fileName.endsWith('.tmp') ||
        fileName.endsWith('.temp') ||
        fileName.endsWith('~')) {
      return false;
    }

    // 忽略系统文件
    if (fileName == 'Thumbs.db' ||
        fileName == 'desktop.ini' ||
        fileName == '.DS_Store') {
      return false;
    }

    return true;
  }
}