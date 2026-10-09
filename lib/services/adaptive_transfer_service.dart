import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

/// 自适应传输服务
/// 通过探测网络状况动态调整传输参数
/// 确保在最优速度下传输，质量不降低
class AdaptiveTransferService {
  // 探测配置
  static const int _probeChunkSize = 64 * 1024; // 64KB探测包
  static const int _probeCount = 5; // 探测次数
  
  // 传输配置范围
  static const int _minChunkSize = 256 * 1024; // 256KB
  static const int _maxChunkSize = 8 * 1024 * 1024; // 8MB
  static const int _minParallel = 1;
  static const int _maxParallel = 8;
  
  // 拥塞控制
  static const int _congestionWindowIncrease = 2; // 拥塞窗口增长因子
  
  // 速度模式
  static const SpeedMode _defaultSpeedMode = SpeedMode.balanced;
  
  // 极限模式配置
  static const int _extremeChunkSize = 16 * 1024 * 1024; // 16MB
  static const int _extremeParallel = 16;
  
  /// 探测网络状况
  static Future<NetworkProfile> probeNetwork(Socket socket) async {
    final latencies = <double>[];
    final throughputs = <double>[];
    
    for (int i = 0; i < _probeCount; i++) {
      final probeData = _createProbePacket(i);
      final stopwatch = Stopwatch()..start();
      
      try {
        // 发送探测包
        socket.add(probeData);
        await socket.flush();
        
        // 等待响应（简化实现：通过测量发送时间）
        await Future.delayed(const Duration(milliseconds: 50));
        
        stopwatch.stop();
        latencies.add(stopwatch.elapsedMilliseconds.toDouble());
        
        // 计算吞吐量
        final throughput = _probeChunkSize / (stopwatch.elapsedMilliseconds / 1000);
        throughputs.add(throughput);
      } catch (e) {
        // 探测失败，使用保守值
        latencies.add(100.0);
        throughputs.add(_probeChunkSize.toDouble());
      }
    }
    
    // 计算统计值
    latencies.sort();
    throughputs.sort();
    
    final medianLatency = latencies[latencies.length ~/ 2];
    final medianThroughput = throughputs[throughputs.length ~/ 2];
    
    // 计算抖动（延迟标准差）
    final avgLatency = latencies.reduce((a, b) => a + b) / latencies.length;
    final jitter = sqrt(latencies.map((l) => (l - avgLatency) * (l - avgLatency)).reduce((a, b) => a + b) / latencies.length);
    
    return NetworkProfile(
      medianLatency: medianLatency,
      medianThroughput: medianThroughput,
      jitter: jitter,
      timestamp: DateTime.now(),
    );
  }
  
  /// 根据网络状况计算最优传输参数
  static TransferParams calculateOptimalParams(
    NetworkProfile profile, 
    int fileSize, {
    SpeedMode speedMode = _defaultSpeedMode,
  }) {
    // 基础参数
    int chunkSize;
    int parallelChunks;
    
    // 根据速度模式调整
    switch (speedMode) {
      case SpeedMode.balanced:
        // 平衡模式：考虑网络状况
        if (profile.medianLatency < 10 && profile.jitter < 5) {
          chunkSize = _maxChunkSize;
          parallelChunks = _maxParallel;
        } else if (profile.medianLatency < 50) {
          chunkSize = _maxChunkSize ~/ 2;
          parallelChunks = _maxParallel ~/ 2;
        } else {
          chunkSize = _minChunkSize;
          parallelChunks = _minParallel;
        }
        
        // 根据文件大小调整
        if (fileSize < 1024 * 1024) {
          chunkSize = min(chunkSize, _minChunkSize);
          parallelChunks = min(parallelChunks, 2);
        } else if (fileSize > 100 * 1024 * 1024) {
          chunkSize = max(chunkSize, _maxChunkSize);
          parallelChunks = max(parallelChunks, 4);
        }
        
        chunkSize = chunkSize.clamp(_minChunkSize, _maxChunkSize);
        parallelChunks = parallelChunks.clamp(_minParallel, _maxParallel);
        break;
        
      case SpeedMode.maximum:
        // 最大速度模式：忽略网络状况，使用最大参数
        chunkSize = _maxChunkSize;
        parallelChunks = _maxParallel;
        
        // 大文件使用更大块
        if (fileSize > 100 * 1024 * 1024) {
          chunkSize = _maxChunkSize * 2;
          parallelChunks = _maxParallel;
        }
        
        chunkSize = chunkSize.clamp(_minChunkSize, _maxChunkSize * 2);
        parallelChunks = parallelChunks.clamp(_minParallel, _maxParallel);
        break;
        
      case SpeedMode.extreme:
        // 极限模式：强行占用带宽（谨慎使用）
        chunkSize = _extremeChunkSize;
        parallelChunks = _extremeParallel;
        break;
        
      case SpeedMode.conservative:
        // 保守模式：最小化网络影响
        chunkSize = _minChunkSize;
        parallelChunks = _minParallel;
        break;
    }
    
    // 计算拥塞窗口
    int congestionWindow;
    switch (speedMode) {
      case SpeedMode.extreme:
        congestionWindow = 32; // 大窗口
        break;
      case SpeedMode.maximum:
        congestionWindow = 16;
        break;
      case SpeedMode.balanced:
        congestionWindow = (profile.medianThroughput / chunkSize).ceil().clamp(1, 16);
        break;
      case SpeedMode.conservative:
        congestionWindow = 1;
        break;
    }
    
    return TransferParams(
      chunkSize: chunkSize,
      parallelChunks: parallelChunks,
      congestionWindow: congestionWindow,
      initialSpeed: profile.medianThroughput,
      speedMode: speedMode,
    );
  }
  
  /// 自适应发送文件
  static Future<TransferResult> sendFileAdaptive({
    required Socket socket,
    required String filePath,
    required String relativePath,
    required Function(TransferProgress) onProgress,
    Function(NetworkProfile)? onNetworkProbe,
    SpeedMode speedMode = _defaultSpeedMode,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return TransferResult(success: false, error: 'File not found');
    }
    
    final fileSize = await file.length();
    final fileName = path.basename(filePath);
    final transferId = const Uuid().v4();
    
    // 探测网络（极限模式跳过探测以节省时间）
    NetworkProfile networkProfile;
    if (speedMode == SpeedMode.extreme) {
      networkProfile = NetworkProfile(
        medianLatency: 0,
        medianThroughput: double.infinity,
        jitter: 0,
        timestamp: DateTime.now(),
      );
    } else {
      networkProfile = await probeNetwork(socket);
      onNetworkProbe?.call(networkProfile);
    }
    
    // 计算最优参数
    final params = calculateOptimalParams(networkProfile, fileSize, speedMode: speedMode);
    
    // 配置socket
    _configureSocket(socket, params);
    
    final stopwatch = Stopwatch()..start();
    int transferredBytes = 0;
    int currentChunk = 0;
    final totalChunks = (fileSize / params.chunkSize).ceil();
    
    // 拥塞控制状态
    int currentParallel = params.parallelChunks;
    int currentWindow = params.congestionWindow;
    int consecutiveSuccess = 0;
    int consecutiveFailure = 0;
    
    try {
      // 发送文件头
      final header = _createFileHeader(transferId, fileName, fileSize, relativePath, params);
      socket.add(header);
      
      // 读取文件
      final randomAccess = await file.open(mode: FileMode.read);
      final buffer = Uint8List(params.chunkSize);
      
      // 并行发送控制
      final sendQueue = <Future<bool>>[];
      
      while (transferredBytes < fileSize) {
        // 检查拥塞窗口
        if (sendQueue.length >= currentWindow) {
          // 等待最旧的发送完成
          final result = await sendQueue.removeAt(0);
          if (result) {
            consecutiveSuccess++;
            consecutiveFailure = 0;
            // 慢启动：成功时增加窗口
            if (consecutiveSuccess >= 3) {
              currentWindow = min(currentWindow + _congestionWindowIncrease, 16);
              consecutiveSuccess = 0;
            }
          } else {
            consecutiveFailure++;
            consecutiveSuccess = 0;
            // 拥塞避免：失败时减少窗口
            if (consecutiveFailure >= 2) {
              currentWindow = max(currentWindow ~/ 2, 1);
              consecutiveFailure = 0;
            }
          }
        }
        
        final remaining = fileSize - transferredBytes;
        final readSize = min(params.chunkSize, remaining);
        
        // 读取数据
        final bytesRead = await randomAccess.readInto(buffer, 0, readSize);
        if (bytesRead <= 0) break;
        
        // 异步发送chunk
        final chunkFuture = _sendChunkAsync(
          socket,
          buffer,
          bytesRead,
          currentChunk,
          totalChunks,
          transferId,
        );
        sendQueue.add(chunkFuture);
        
        transferredBytes += bytesRead;
        currentChunk++;
        
        // 更新进度
        final elapsed = stopwatch.elapsedMilliseconds / 1000;
        final speed = elapsed > 0 ? transferredBytes / elapsed : 0.0;
        
        onProgress(TransferProgress(
          transferId: transferId,
          fileName: fileName,
          fileSize: fileSize,
          transferredBytes: transferredBytes,
          speed: speed,
          isSending: true,
          chunkSize: params.chunkSize,
          parallelChunks: currentParallel,
          congestionWindow: currentWindow,
        ));
        
        // 动态调整并行度
        if (currentChunk % 10 == 0) {
          currentParallel = _adjustParallelism(speed, params.initialSpeed, currentParallel);
        }
        
        // 让出CPU
        await Future.delayed(Duration.zero);
      }
      
      // 等待所有发送完成
      for (final future in sendQueue) {
        await future;
      }
      
      await randomAccess.close();
      
      // 发送完成标记
      final completeMarker = _createCompleteMarker(transferId, true);
      socket.add(completeMarker);
      await socket.flush();
      
      stopwatch.stop();
      final totalTime = stopwatch.elapsedMilliseconds / 1000;
      final avgSpeed = totalTime > 0 ? (fileSize / totalTime).toDouble() : 0.0;

      return TransferResult(
        success: true,
        transferId: transferId,
        bytesTransferred: transferredBytes,
        averageSpeed: avgSpeed,
        totalTime: totalTime,
        networkProfile: networkProfile,
        transferParams: params,
      );
    } catch (e) {
      return TransferResult(success: false, error: e.toString());
    }
  }
  
  /// 异步发送chunk
  static Future<bool> _sendChunkAsync(
    Socket socket,
    Uint8List data,
    int length,
    int chunkIndex,
    int totalChunks,
    String transferId,
  ) async {
    try {
      final crc = _crc32(data, length);
      final packet = _createChunkPacket(data, length, crc, chunkIndex, totalChunks, transferId);
      socket.add(packet);
      await socket.flush();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// 动态调整并行度
  static int _adjustParallelism(double currentSpeed, double expectedSpeed, int currentParallel) {
    final ratio = currentSpeed / expectedSpeed;
    
    if (ratio > 1.2) {
      // 速度超过预期，可以增加并行度
      return min(currentParallel + 1, _maxParallel);
    } else if (ratio < 0.8) {
      // 速度低于预期，减少并行度
      return max(currentParallel - 1, _minParallel);
    }
    
    return currentParallel;
  }
  
  /// 配置Socket
  static void _configureSocket(Socket socket, TransferParams params) {
    try {
      // 启用TCP_NODELAY减少延迟
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {
      // 某些平台可能不支持
    }
  }
  
  /// 创建探测包
  static Uint8List _createProbePacket(int sequence) {
    final buffer = ByteData(16);
    buffer.setInt32(0, 0x50524F42, Endian.big); // "PROB"
    buffer.setInt32(4, sequence, Endian.big);
    buffer.setInt64(8, DateTime.now().millisecondsSinceEpoch, Endian.big);
    return buffer.buffer.asUint8List();
  }
  
  /// 创建文件头
  static Uint8List _createFileHeader(
    String transferId,
    String fileName,
    int fileSize,
    String relativePath,
    TransferParams params,
  ) {
    final idBytes = Uint8List.fromList(transferId.codeUnits);
    final nameBytes = Uint8List.fromList(fileName.codeUnits);
    final pathBytes = Uint8List.fromList(relativePath.codeUnits);
    
    // [4字节magic][4字节类型=0x10][8字节文件大小][4字节chunk大小][4字节并行度]
    // [4字节id长度][id][4字节name长度][name][4字节path长度][path]
    final totalSize = 4 + 4 + 8 + 4 + 4 + 4 + idBytes.length + 4 + nameBytes.length + 4 + pathBytes.length;
    final buffer = ByteData(totalSize);
    var offset = 0;
    
    // Magic
    buffer.setInt32(offset, 0x4C53594E, Endian.big);
    offset += 4;
    
    // 类型
    buffer.setInt32(offset, 0x10, Endian.big);
    offset += 4;
    
    // 文件大小
    buffer.setInt64(offset, fileSize, Endian.big);
    offset += 8;
    
    // Chunk大小
    buffer.setInt32(offset, params.chunkSize, Endian.big);
    offset += 4;
    
    // 并行度
    buffer.setInt32(offset, params.parallelChunks, Endian.big);
    offset += 4;
    
    // Transfer ID
    buffer.setInt32(offset, idBytes.length, Endian.big);
    offset += 4;
    _copyBytes(buffer, offset, idBytes);
    offset += idBytes.length;
    
    // 文件名
    buffer.setInt32(offset, nameBytes.length, Endian.big);
    offset += 4;
    _copyBytes(buffer, offset, nameBytes);
    offset += nameBytes.length;
    
    // 路径
    buffer.setInt32(offset, pathBytes.length, Endian.big);
    offset += 4;
    _copyBytes(buffer, offset, pathBytes);
    
    return buffer.buffer.asUint8List();
  }
  
  /// 创建chunk包
  static Uint8List _createChunkPacket(
    Uint8List data,
    int length,
    int crc,
    int chunkIndex,
    int totalChunks,
    String transferId,
  ) {
    final idBytes = Uint8List.fromList(transferId.codeUnits);
    
    // [4字节magic][4字节类型=0x11][4字节chunkIndex][4字节totalChunks][4字节CRC]
    // [4字节id长度][id][4字节数据长度][数据]
    const headerSize = 4 + 4 + 4 + 4 + 4 + 4 + 4; // 固定部分
    final totalSize = headerSize + idBytes.length + 4 + length;
    final buffer = ByteData(headerSize);
    var offset = 0;
    
    // Magic
    buffer.setInt32(offset, 0x4C53594E, Endian.big);
    offset += 4;
    
    // 类型
    buffer.setInt32(offset, 0x11, Endian.big);
    offset += 4;
    
    // Chunk索引
    buffer.setInt32(offset, chunkIndex, Endian.big);
    offset += 4;
    
    // 总chunk数
    buffer.setInt32(offset, totalChunks, Endian.big);
    offset += 4;
    
    // CRC32
    buffer.setInt32(offset, crc, Endian.big);
    offset += 4;
    
    // ID长度
    buffer.setInt32(offset, idBytes.length, Endian.big);
    offset += 4;
    
    // 数据长度
    buffer.setInt32(offset, length, Endian.big);
    
    // 组合数据
    final result = Uint8List(totalSize);
    result.setRange(0, headerSize, buffer.buffer.asUint8List());
    result.setRange(headerSize, headerSize + idBytes.length, idBytes);
    
    // 数据长度
    final dataLengthBytes = ByteData(4)..setInt32(0, length, Endian.big);
    result.setRange(headerSize + idBytes.length, headerSize + idBytes.length + 4, dataLengthBytes.buffer.asUint8List());

    // 数据
    result.setRange(headerSize + idBytes.length + 4, totalSize, data.sublist(0, length));

    return result;
  }
  
  /// 创建完成标记
  static Uint8List _createCompleteMarker(String transferId, bool success) {
    final idBytes = Uint8List.fromList(transferId.codeUnits);
    
    // [4字节magic][4字节类型=0x12][4字节状态][4字节id长度][id]
    final totalSize = 4 + 4 + 4 + 4 + idBytes.length;
    final buffer = ByteData(totalSize);
    var offset = 0;
    
    // Magic
    buffer.setInt32(offset, 0x4C53594E, Endian.big);
    offset += 4;
    
    // 类型
    buffer.setInt32(offset, 0x12, Endian.big);
    offset += 4;
    
    // 状态
    buffer.setInt32(offset, success ? 1 : 0, Endian.big);
    offset += 4;
    
    // ID长度
    buffer.setInt32(offset, idBytes.length, Endian.big);
    offset += 4;
    
    // ID
    _copyBytes(buffer, offset, idBytes);
    
    return buffer.buffer.asUint8List();
  }
  
  /// 复制字节
  static void _copyBytes(ByteData buffer, int offset, Uint8List data) {
    for (int i = 0; i < data.length; i++) {
      buffer.setUint8(offset + i, data[i]);
    }
  }
  
  /// CRC32校验
  static int _crc32(Uint8List data, int length) {
    int crc = 0xFFFFFFFF;
    
    for (int i = 0; i < length; i++) {
      crc ^= data[i];
      for (int j = 0; j < 8; j++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc >>= 1;
        }
      }
    }
    
    return crc ^ 0xFFFFFFFF;
  }
}

/// 网络状况描述
class NetworkProfile {
  final double medianLatency; // 毫秒
  final double medianThroughput; // 字节/秒
  final double jitter; // 毫秒
  final DateTime timestamp;
  
  NetworkProfile({
    required this.medianLatency,
    required this.medianThroughput,
    required this.jitter,
    required this.timestamp,
  });
  
  String get quality {
    if (medianLatency < 10 && jitter < 5) return '优秀';
    if (medianLatency < 50 && jitter < 20) return '良好';
    if (medianLatency < 100) return '一般';
    return '较差';
  }
}

/// 速度模式
enum SpeedMode {
  /// 保守模式：最小化网络影响，适合共享网络
  conservative,
  
  /// 平衡模式：根据网络状况自动调整（默认）
  balanced,
  
  /// 最大速度模式：优先速度，可能影响其他设备
  maximum,
  
  /// 极限模式：强行占用带宽（谨慎使用，可能触发网络保护）
  extreme,
}

/// 传输参数
class TransferParams {
  final int chunkSize;
  final int parallelChunks;
  final int congestionWindow;
  final double initialSpeed;
  final SpeedMode speedMode;
  
  TransferParams({
    required this.chunkSize,
    required this.parallelChunks,
    required this.congestionWindow,
    required this.initialSpeed,
    required this.speedMode,
  });
}

/// 传输进度
class TransferProgress {
  final String transferId;
  final String fileName;
  final int fileSize;
  final int transferredBytes;
  final double speed;
  final bool isSending;
  final bool isCompleted;
  final bool isError;
  final String? errorMessage;
  final int? chunkSize;
  final int? parallelChunks;
  final int? congestionWindow;
  
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
    this.chunkSize,
    this.parallelChunks,
    this.congestionWindow,
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

/// 传输结果
class TransferResult {
  final bool success;
  final String? transferId;
  final int? bytesTransferred;
  final double? averageSpeed;
  final double? totalTime;
  final String? error;
  final NetworkProfile? networkProfile;
  final TransferParams? transferParams;
  
  TransferResult({
    required this.success,
    this.transferId,
    this.bytesTransferred,
    this.averageSpeed,
    this.totalTime,
    this.error,
    this.networkProfile,
    this.transferParams,
  });
}