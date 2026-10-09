import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import '../protocol/binary_protocol.dart';
import 'network_service.dart';
import 'adaptive_transfer_service.dart';

class TransferProgress {
  final String transferId;
  final String fileName;
  final int fileSize;
  final int transferredBytes;
  final double speed; // bytes per second
  final bool isSending;
  final bool isCompleted;
  final bool isError;
  final String? errorMessage;

  TransferProgress({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.transferredBytes,
    required this.speed,
    required this.isSending,
    this.isCompleted = false,
    this.isError = false,
    this.errorMessage,
  });

  double get progress => fileSize > 0 ? transferredBytes / fileSize : 0;
  String get progressPercent => '${(progress * 100).toStringAsFixed(1)}%';
  String get speedText {
    if (speed < 1024) return '${speed.toStringAsFixed(1)} B/s';
    if (speed < 1024 * 1024) return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    if (speed < 1024 * 1024 * 1024) return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    return '${(speed / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB/s';
  }
}

/// 高性能传输管理器
/// 优化策略：
/// 1. 二进制协议避免JSON开销
/// 2. 大块传输(4MB)减少系统调用
/// 3. TCP_NODELAY减少延迟
/// 4. CRC32校验确保正确性
/// 5. 预分配缓冲区减少GC
/// 6. 自适应传输策略
class TransferManager {
  final NetworkService _networkService;
  final String _syncPath;
  final SpeedMode _speedMode;
  final _uuid = const Uuid();

  final Map<String, TransferProgress> _activeTransfers = {};
  final Map<String, _ReceiveState> _receiveStates = {};
  final StreamController<TransferProgress> _progressController =
      StreamController<TransferProgress>.broadcast();
  final StreamController<String> _fileReceivedController =
      StreamController<String>.broadcast();

  Stream<TransferProgress> get progressStream => _progressController.stream;
  /// 文件接收完成流，emit 文件的相对路径
  Stream<String> get fileReceivedStream => _fileReceivedController.stream;
  Map<String, TransferProgress> get activeTransfers =>
      Map.unmodifiable(_activeTransfers);

  TransferManager({
    required NetworkService networkService,
    required String syncPath,
    SpeedMode speedMode = SpeedMode.balanced,
  }) : _networkService = networkService,
       _syncPath = syncPath,
       _speedMode = speedMode;

  void start() {
    // 监听网络消息
    _networkService.messageStream.listen(_handleMessage);
  }

  void _handleMessage(dynamic message) {
    // 处理二进制协议消息
    if (message is Uint8List) {
      _handleBinaryMessage(message);
    }
  }

  void _handleBinaryMessage(Uint8List data) {
    final packet = BinaryProtocol.parsePacket(data, 0);
    if (packet == null) return;

    switch (packet.type) {
      case BinaryProtocol.typeFileHeader:
        _handleFileHeader(packet);
        break;
      case BinaryProtocol.typeDataChunk:
        _handleDataChunk(packet, data);
        break;
      case BinaryProtocol.typeComplete:
        _handleComplete(packet);
        break;
    }
  }

  /// 发送文件（自适应模式）
  Future<void> sendFile(String filePath, ConnectedDevice device) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    // 检查设备是否已信任（如果启用了配对验证）
    if (!device.isTrusted) {
      // 跳过未信任设备的传输
      return;
    }

    final transferId = _uuid.v4();
    final fileName = path.basename(filePath);
    final fileSize = await file.length();
    final relativePath = path.relative(filePath, from: _syncPath);

    // 创建传输进度
    final progress = TransferProgress(
      transferId: transferId,
      fileName: fileName,
      fileSize: fileSize,
      transferredBytes: 0,
      speed: 0,
      isSending: true,
    );
    _activeTransfers[transferId] = progress;
    _progressController.add(progress);

    // 连接到设备
    final socket = await _networkService.connectToDevice(device);

    // 使用自适应传输服务
    final result = await AdaptiveTransferService.sendFileAdaptive(
      socket: socket,
      filePath: filePath,
      relativePath: relativePath,
      onProgress: (progress) {
        _activeTransfers[transferId] = TransferProgress(
          transferId: transferId,
          fileName: fileName,
          fileSize: fileSize,
          transferredBytes: progress.transferredBytes,
          speed: progress.speed,
          isSending: true,
        );
        _progressController.add(_activeTransfers[transferId]!);
      },
      speedMode: _speedMode,
    );

    if (result.success) {
      final finalProgress = TransferProgress(
        transferId: transferId,
        fileName: fileName,
        fileSize: fileSize,
        transferredBytes: fileSize,
        speed: 0,
        isSending: true,
        isCompleted: true,
      );
      _activeTransfers[transferId] = finalProgress;
      _progressController.add(finalProgress);
    } else {
      final errorProgress = TransferProgress(
        transferId: transferId,
        fileName: fileName,
        fileSize: fileSize,
        transferredBytes: 0,
        speed: 0,
        isSending: true,
        isError: true,
        errorMessage: result.error,
      );
      _activeTransfers[transferId] = errorProgress;
      _progressController.add(errorProgress);
    }
  }

  void _handleFileHeader(PacketInfo packet) {
    final state = _ReceiveState(
      transferId: packet.transferId!,
      fileName: packet.fileName!,
      fileSize: packet.fileSize!,
      relativePath: packet.relativePath!,
    );
    _receiveStates[packet.transferId!] = state;

    // 创建进度记录
    final progress = TransferProgress(
      transferId: packet.transferId!,
      fileName: packet.fileName!,
      fileSize: packet.fileSize!,
      transferredBytes: 0,
      speed: 0,
      isSending: false,
    );
    _activeTransfers[packet.transferId!] = progress;
    _progressController.add(progress);
  }

  void _handleDataChunk(PacketInfo packet, Uint8List rawData) {
    final state = _receiveStates[packet.transferId];
    if (state == null) return;

    // CRC校验
    final dataStart = packet.dataOffset!;
    final dataEnd = dataStart + packet.dataLength!;
    final actualCrc = BinaryProtocol.crc32(rawData, dataStart, packet.dataLength!);
    
    if (actualCrc != packet.crc32) {
      // CRC校验失败，请求重传
      return;
    }

    // 写入文件
    _writeChunkToFile(state, rawData.sublist(dataStart, dataEnd));

    state.receivedBytes += packet.dataLength!;
    state.receivedChunks++;

    // 更新进度
    final progress = _activeTransfers[state.transferId];
    if (progress != null) {
      final updatedProgress = TransferProgress(
        transferId: state.transferId,
        fileName: state.fileName,
        fileSize: state.fileSize,
        transferredBytes: state.receivedBytes,
        speed: progress.speed,
        isSending: false,
        isCompleted: state.receivedBytes >= state.fileSize,
      );
      _activeTransfers[state.transferId] = updatedProgress;
      _progressController.add(updatedProgress);
    }
  }

  void _handleComplete(PacketInfo packet) {
    final state = _receiveStates.remove(packet.transferId);
    if (state == null) return;

    // 重命名临时文件为最终文件名
    final tempPath = path.join(_syncPath, '.tmp_${state.transferId}_${state.fileName}');
    final finalPath = path.join(_syncPath, state.relativePath);
    final tempFile = File(tempPath);

    if (tempFile.existsSync()) {
      // 确保目标目录存在
      final finalDir = Directory(path.dirname(finalPath));
      if (!finalDir.existsSync()) {
        finalDir.createSync(recursive: true);
      }

      final finalFile = File(finalPath);
      if (finalFile.existsSync()) {
        finalFile.deleteSync();
      }
      tempFile.renameSync(finalPath);
    }

    // 通知文件接收完成
    _fileReceivedController.add(state.relativePath);

    // 更新进度为完成
    final progress = _activeTransfers[state.transferId];
    if (progress != null) {
      final finalProgress = TransferProgress(
        transferId: state.transferId,
        fileName: state.fileName,
        fileSize: state.fileSize,
        transferredBytes: state.fileSize,
        speed: 0,
        isSending: false,
        isCompleted: true,
      );
      _activeTransfers[state.transferId] = finalProgress;
      _progressController.add(finalProgress);
    }
  }

  Future<void> _writeChunkToFile(_ReceiveState state, Uint8List data) async {
    final filePath = path.join(_syncPath, '.tmp_${state.transferId}_${state.fileName}');
    final file = File(filePath);

    final sink = file.openSync(mode: FileMode.append);
    sink.writeFromSync(data);
    sink.closeSync();
  }

  void cleanupCompletedTransfers() {
    _activeTransfers.removeWhere((key, value) => value.isCompleted);
  }
}

/// 接收状态
class _ReceiveState {
  final String transferId;
  final String fileName;
  final int fileSize;
  final String relativePath;
  int receivedBytes = 0;
  int receivedChunks = 0;

  _ReceiveState({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.relativePath,
  });
}