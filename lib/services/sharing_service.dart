import 'dart:async';
import 'dart:io';

class SharedFile {
  final String path;
  final String name;
  final String? mimeType;
  final bool isFolder;

  SharedFile({
    required this.path,
    required this.name,
    this.mimeType,
    this.isFolder = false,
  });
}

class SharingService {
  final StreamController<List<SharedFile>> _sharedFilesController =
      StreamController<List<SharedFile>>.broadcast();

  Stream<List<SharedFile>> get sharedFilesStream => _sharedFilesController.stream;

  void startListening() {
    // Android分享功能通过intent-filter自动处理
    // 具体实现在Android原生代码中
  }

  void handleSharedFiles(List<String> filePaths) {
    final sharedFiles = filePaths.map((filePath) {
      final name = filePath.split(Platform.pathSeparator).last;
      
      return SharedFile(
        path: filePath,
        name: name,
      );
    }).toList();

    _sharedFilesController.add(sharedFiles);
  }

  void stopListening() {
    // 清理资源
  }

  void dispose() {
    _sharedFilesController.close();
  }
}