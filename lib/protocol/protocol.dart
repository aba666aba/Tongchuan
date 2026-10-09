import 'dart:typed_data';
import 'dart:convert';

enum MessageType {
  discovery, // 设备发现
  discoveryResponse, // 设备发现响应
  fileTransferRequest, // 文件传输请求
  fileTransferResponse, // 文件传输响应
  fileChunk, // 文件数据块
  fileTransferComplete, // 文件传输完成
  fileTransferResume, // 断点续传请求
  error, // 错误
}

class ProtocolMessage {
  final MessageType type;
  final Map<String, dynamic> data;
  final Uint8List? payload;

  ProtocolMessage({
    required this.type,
    required this.data,
    this.payload,
  });

  // 序列化消息
  Uint8List serialize() {
    final header = {
      'type': type.index,
      'data': data,
      'payloadLength': payload?.length ?? 0,
    };
    final headerBytes = utf8.encode(jsonEncode(header));
    final headerLength = ByteData(4)..setInt32(0, headerBytes.length);
    
    final buffer = BytesBuilder();
    buffer.add(headerLength.buffer.asUint8List());
    buffer.add(headerBytes);
    if (payload != null) {
      buffer.add(payload!);
    }
    return buffer.toBytes();
  }

  // 反序列化消息
  static ProtocolMessage? deserialize(Uint8List bytes) {
    if (bytes.length < 4) return null;
    
    final headerLength = ByteData.sublistView(bytes, 0, 4).getInt32(0);
    if (bytes.length < 4 + headerLength) return null;
    
    final headerBytes = bytes.sublist(4, 4 + headerLength);
    final header = jsonDecode(utf8.decode(headerBytes));
    
    final payloadLength = header['payloadLength'] as int;
    if (bytes.length < 4 + headerLength + payloadLength) return null;
    
    Uint8List? payload;
    if (payloadLength > 0) {
      payload = bytes.sublist(4 + headerLength, 4 + headerLength + payloadLength);
    }
    
    return ProtocolMessage(
      type: MessageType.values[header['type'] as int],
      data: Map<String, dynamic>.from(header['data']),
      payload: payload,
    );
  }
}

// 设备发现消息
class DiscoveryMessage {
  final String deviceId;
  final String deviceName;
  final String platform; // 'windows' or 'android'
  final int port;

  DiscoveryMessage({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.port,
  });

  ProtocolMessage toMessage() {
    return ProtocolMessage(
      type: MessageType.discovery,
      data: {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'platform': platform,
        'port': port,
      },
    );
  }

  factory DiscoveryMessage.fromMessage(ProtocolMessage message) {
    return DiscoveryMessage(
      deviceId: message.data['deviceId'],
      deviceName: message.data['deviceName'],
      platform: message.data['platform'],
      port: message.data['port'],
    );
  }
}

// 文件传输请求消息
class FileTransferRequest {
  final String transferId;
  final String fileName;
  final int fileSize;
  final String relativePath; // 相对路径

  FileTransferRequest({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.relativePath,
  });

  ProtocolMessage toMessage() {
    return ProtocolMessage(
      type: MessageType.fileTransferRequest,
      data: {
        'transferId': transferId,
        'fileName': fileName,
        'fileSize': fileSize,
        'relativePath': relativePath,
      },
    );
  }

  factory FileTransferRequest.fromMessage(ProtocolMessage message) {
    return FileTransferRequest(
      transferId: message.data['transferId'],
      fileName: message.data['fileName'],
      fileSize: message.data['fileSize'],
      relativePath: message.data['relativePath'],
    );
  }
}

// 文件传输响应消息
class FileTransferResponse {
  final String transferId;
  final bool accepted;
  final String? errorMessage;

  FileTransferResponse({
    required this.transferId,
    required this.accepted,
    this.errorMessage,
  });

  ProtocolMessage toMessage() {
    return ProtocolMessage(
      type: MessageType.fileTransferResponse,
      data: {
        'transferId': transferId,
        'accepted': accepted,
        'errorMessage': errorMessage,
      },
    );
  }

  factory FileTransferResponse.fromMessage(ProtocolMessage message) {
    return FileTransferResponse(
      transferId: message.data['transferId'],
      accepted: message.data['accepted'],
      errorMessage: message.data['errorMessage'],
    );
  }
}

// 文件数据块消息
class FileChunkMessage {
  final String transferId;
  final int chunkIndex;
  final int totalChunks;
  final Uint8List data;

  FileChunkMessage({
    required this.transferId,
    required this.chunkIndex,
    required this.totalChunks,
    required this.data,
  });

  ProtocolMessage toMessage() {
    return ProtocolMessage(
      type: MessageType.fileChunk,
      data: {
        'transferId': transferId,
        'chunkIndex': chunkIndex,
        'totalChunks': totalChunks,
      },
      payload: data,
    );
  }

  factory FileChunkMessage.fromMessage(ProtocolMessage message) {
    return FileChunkMessage(
      transferId: message.data['transferId'],
      chunkIndex: message.data['chunkIndex'],
      totalChunks: message.data['totalChunks'],
      data: message.payload!,
    );
  }
}

// 文件传输完成消息
class FileTransferComplete {
  final String transferId;
  final bool success;
  final String? errorMessage;

  FileTransferComplete({
    required this.transferId,
    required this.success,
    this.errorMessage,
  });

  ProtocolMessage toMessage() {
    return ProtocolMessage(
      type: MessageType.fileTransferComplete,
      data: {
        'transferId': transferId,
        'success': success,
        'errorMessage': errorMessage,
      },
    );
  }

  factory FileTransferComplete.fromMessage(ProtocolMessage message) {
    return FileTransferComplete(
      transferId: message.data['transferId'],
      success: message.data['success'],
      errorMessage: message.data['errorMessage'],
    );
  }
}

// 断点续传请求消息
class FileTransferResumeRequest {
  final String transferId;
  final String fileName;
  final int fileSize;
  final String relativePath;
  final int resumeOffset; // 从哪个位置继续

  FileTransferResumeRequest({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.relativePath,
    required this.resumeOffset,
  });

  ProtocolMessage toMessage() {
    return ProtocolMessage(
      type: MessageType.fileTransferResume,
      data: {
        'transferId': transferId,
        'fileName': fileName,
        'fileSize': fileSize,
        'relativePath': relativePath,
        'resumeOffset': resumeOffset,
      },
    );
  }

  factory FileTransferResumeRequest.fromMessage(ProtocolMessage message) {
    return FileTransferResumeRequest(
      transferId: message.data['transferId'],
      fileName: message.data['fileName'],
      fileSize: message.data['fileSize'],
      relativePath: message.data['relativePath'],
      resumeOffset: message.data['resumeOffset'],
    );
  }
}