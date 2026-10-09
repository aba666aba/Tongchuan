import 'dart:typed_data';

/// 高性能二进制协议
/// 避免JSON序列化，直接使用二进制格式
/// 
/// 协议格式：
/// [4字节magic][4字节类型][4字节数据长度][变长数据]
/// 
/// 文件传输格式：
/// [4字节magic][4字节类型=0x10][8字节文件大小][4字节文件名长度][变长文件名][4字节路径长度][变长路径]
/// 
/// 数据块格式：
/// [4字节magic][4字节类型=0x11][4字节块序号][4字块总数][4字节CRC32][4字节数据长度][变长数据]
/// 
/// 完成标记：
/// [4字节magic][4字节类型=0x12][4字节状态(1=成功,0=失败)]
class BinaryProtocol {
  static const int magic = 0x4C53594E; // "LSYN"
  static const int typeFileHeader = 0x10;
  static const int typeDataChunk = 0x11;
  static const int typeComplete = 0x12;
  static const int typeProgress = 0x13;
  
  /// 创建文件头数据包
  static Uint8List createFileHeader({
    required String transferId,
    required String fileName,
    required int fileSize,
    required String relativePath,
  }) {
    final fileNameBytes = _stringToBytes(fileName);
    final pathBytes = _stringToBytes(relativePath);
    final idBytes = _stringToBytes(transferId);
    
    // 计算总大小
    final totalSize = 4 + 4 + 8 + 4 + idBytes.length + 4 + fileNameBytes.length + 4 + pathBytes.length;
    final buffer = ByteData(totalSize);
    var offset = 0;
    
    // Magic
    buffer.setInt32(offset, magic, Endian.big);
    offset += 4;
    
    // 类型
    buffer.setInt32(offset, typeFileHeader, Endian.big);
    offset += 4;
    
    // 文件大小 (8字节)
    buffer.setInt64(offset, fileSize, Endian.big);
    offset += 8;
    
    // Transfer ID
    buffer.setInt32(offset, idBytes.length, Endian.big);
    offset += 4;
    _copyBytes(buffer, offset, idBytes);
    offset += idBytes.length;
    
    // 文件名
    buffer.setInt32(offset, fileNameBytes.length, Endian.big);
    offset += 4;
    _copyBytes(buffer, offset, fileNameBytes);
    offset += fileNameBytes.length;
    
    // 相对路径
    buffer.setInt32(offset, pathBytes.length, Endian.big);
    offset += 4;
    _copyBytes(buffer, offset, pathBytes);
    
    return buffer.buffer.asUint8List();
  }
  
  /// 创建数据块数据包
  static Uint8List createDataChunk({
    required int chunkIndex,
    required int totalChunks,
    required int crc32,
    required Uint8List data,
    required int dataLength,
  }) {
    // 头部大小: 4+4+4+4+4+4 = 24字节
    const headerSize = 24;
    final totalSize = headerSize + dataLength;
    final buffer = ByteData(headerSize);
    var offset = 0;
    
    // Magic
    buffer.setInt32(offset, magic, Endian.big);
    offset += 4;
    
    // 类型
    buffer.setInt32(offset, typeDataChunk, Endian.big);
    offset += 4;
    
    // 块序号
    buffer.setInt32(offset, chunkIndex, Endian.big);
    offset += 4;
    
    // 总块数
    buffer.setInt32(offset, totalChunks, Endian.big);
    offset += 4;
    
    // CRC32
    buffer.setInt32(offset, crc32, Endian.big);
    offset += 4;
    
    // 数据长度
    buffer.setInt32(offset, dataLength, Endian.big);
    
    // 组合头部和数据
    final result = Uint8List(totalSize);
    result.setRange(0, headerSize, buffer.buffer.asUint8List());
    result.setRange(headerSize, headerSize + dataLength, data.sublist(0, dataLength));

    return result;
  }
  
  /// 创建完成标记
  static Uint8List createCompleteMarker({required bool success}) {
    final buffer = ByteData(12);
    var offset = 0;
    
    // Magic
    buffer.setInt32(offset, magic, Endian.big);
    offset += 4;
    
    // 类型
    buffer.setInt32(offset, typeComplete, Endian.big);
    offset += 4;
    
    // 状态
    buffer.setInt32(offset, success ? 1 : 0, Endian.big);
    
    return buffer.buffer.asUint8List();
  }
  
  /// 创建进度数据包
  static Uint8List createProgressPacket({
    required int transferredBytes,
    required int speed,
  }) {
    final buffer = ByteData(16);
    var offset = 0;
    
    // Magic
    buffer.setInt32(offset, magic, Endian.big);
    offset += 4;
    
    // 类型
    buffer.setInt32(offset, typeProgress, Endian.big);
    offset += 4;
    
    // 已传输字节
    buffer.setInt32(offset, transferredBytes, Endian.big);
    offset += 4;
    
    // 速度
    buffer.setInt32(offset, speed, Endian.big);
    
    return buffer.buffer.asUint8List();
  }
  
  /// 解析数据包
  static PacketInfo? parsePacket(Uint8List data, int offset) {
    if (data.length - offset < 8) return null;
    
    // 检查magic
    final packetMagic = _readInt32(data, offset);
    if (packetMagic != magic) return null;
    
    final type = _readInt32(data, offset + 4);
    
    switch (type) {
      case typeFileHeader:
        return _parseFileHeader(data, offset);
      case typeDataChunk:
        return _parseDataChunk(data, offset);
      case typeComplete:
        return _parseComplete(data, offset);
      default:
        return null;
    }
  }
  
  /// 解析文件头
  static PacketInfo _parseFileHeader(Uint8List data, int offset) {
    var pos = offset + 8; // 跳过magic和类型
    
    // 文件大小
    final fileSize = _readInt64(data, pos);
    pos += 8;
    
    // Transfer ID
    final idLength = _readInt32(data, pos);
    pos += 4;
    final transferId = _bytesToString(data, pos, idLength);
    pos += idLength;
    
    // 文件名
    final nameLength = _readInt32(data, pos);
    pos += 4;
    final fileName = _bytesToString(data, pos, nameLength);
    pos += nameLength;
    
    // 路径
    final pathLength = _readInt32(data, pos);
    pos += 4;
    final relativePath = _bytesToString(data, pos, pathLength);
    pos += pathLength;
    
    return PacketInfo(
      type: typeFileHeader,
      totalSize: pos - offset,
      fileSize: fileSize,
      fileName: fileName,
      transferId: transferId,
      relativePath: relativePath,
    );
  }
  
  /// 解析数据块
  static PacketInfo _parseDataChunk(Uint8List data, int offset) {
    var pos = offset + 8; // 跳过magic和类型
    
    final chunkIndex = _readInt32(data, pos);
    pos += 4;
    
    final totalChunks = _readInt32(data, pos);
    pos += 4;
    
    final crc32 = _readInt32(data, pos);
    pos += 4;
    
    final dataLength = _readInt32(data, pos);
    pos += 4;
    
    return PacketInfo(
      type: typeDataChunk,
      totalSize: 24 + dataLength,
      chunkIndex: chunkIndex,
      totalChunks: totalChunks,
      crc32: crc32,
      dataLength: dataLength,
      dataOffset: pos,
    );
  }
  
  /// 解析完成标记
  static PacketInfo _parseComplete(Uint8List data, int offset) {
    final success = _readInt32(data, offset + 8) == 1;
    
    return PacketInfo(
      type: typeComplete,
      totalSize: 12,
      success: success,
    );
  }
  
  // 辅助方法
  static Uint8List _stringToBytes(String str) {
    return Uint8List.fromList(str.codeUnits);
  }
  
  static String _bytesToString(Uint8List data, int offset, int length) {
    return String.fromCharCodes(data.sublist(offset, offset + length));
  }
  
  static void _copyBytes(ByteData buffer, int offset, Uint8List data) {
    for (int i = 0; i < data.length; i++) {
      buffer.setUint8(offset + i, data[i]);
    }
  }
  
  static int _readInt32(Uint8List data, int offset) {
    return (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];
  }
  
  static int _readInt64(Uint8List data, int offset) {
    return (_readInt32(data, offset) << 32) | _readInt32(data, offset + 4);
  }
  
  /// CRC32校验
  static int crc32(Uint8List data, int offset, int length) {
    int crc = 0xFFFFFFFF;
    
    for (int i = offset; i < offset + length; i++) {
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

/// 数据包信息
class PacketInfo {
  final int type;
  final int totalSize;
  final int? fileSize;
  final String? fileName;
  final String? transferId;
  final String? relativePath;
  final int? chunkIndex;
  final int? totalChunks;
  final int? crc32;
  final int? dataLength;
  final int? dataOffset;
  final bool? success;

  PacketInfo({
    required this.type,
    required this.totalSize,
    this.fileSize,
    this.fileName,
    this.transferId,
    this.relativePath,
    this.chunkIndex,
    this.totalChunks,
    this.crc32,
    this.dataLength,
    this.dataOffset,
    this.success,
  });
}