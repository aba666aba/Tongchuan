import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as path;

/// 安全服务
/// 提供：
/// 1. 配对码确认机制
/// 2. 设备白名单管理
/// 3. TLS加密上下文
class SecurityService {
  static const int _pairingCodeLength = 6;
  static const Duration _pairingTimeout = Duration(seconds: 60);
  static const String _whitelistFileName = 'trusted_devices.json';

  final String _storagePath;
  final Map<String, TrustedDevice> _trustedDevices = {};
  final Map<String, PairingRequest> _pendingRequests = {};
  final StreamController<PairingRequest> _pairingRequestController =
      StreamController<PairingRequest>.broadcast();

  String? _currentPairingCode;
  String? _publicKey;

  SecurityService({required String storagePath})
      : _storagePath = storagePath;

  Stream<PairingRequest> get pairingRequestStream =>
      _pairingRequestController.stream;
  Map<String, TrustedDevice> get trustedDevices =>
      Map.unmodifiable(_trustedDevices);
  String? get publicKey => _publicKey;

  /// 初始化：加载白名单
  Future<void> initialize() async {
    await _loadWhitelist();
  }

  /// 生成6位配对码
  String generatePairingCode() {
    final random = Random.secure();
    final code = List.generate(
      _pairingCodeLength,
      (_) => random.nextInt(10),
    ).join();
    _currentPairingCode = code;
    return code;
  }

  /// 验证配对码
  bool verifyPairingCode(String code) {
    return _currentPairingCode != null && _currentPairingCode == code;
  }

  /// 发起配对请求（接收端调用，生成配对码并通知UI）
  void requestPairing(
    String deviceId,
    String deviceName,
    String platform,
    String pairingCode,
  ) {
    final request = PairingRequest(
      deviceId: deviceId,
      deviceName: deviceName,
      platform: platform,
      pairingCode: pairingCode,
      timestamp: DateTime.now(),
    );

    _pendingRequests[deviceId] = request;
    _pairingRequestController.add(request);

    // 超时自动清除
    Future.delayed(_pairingTimeout, () {
      _pendingRequests.remove(deviceId);
    });
  }

  /// 获取待处理的配对请求
  PairingRequest? getPendingRequest(String deviceId) {
    return _pendingRequests[deviceId];
  }

  /// 确认配对（接收端点击"接受"）
  Future<void> confirmPairing(String deviceId) async {
    final request = _pendingRequests.remove(deviceId);
    if (request == null) return;

    await addTrustedDevice(TrustedDevice(
      deviceId: deviceId,
      deviceName: request.deviceName,
      platform: request.platform,
      addedAt: DateTime.now(),
    ));
  }

  /// 拒绝配对
  void rejectPairing(String deviceId) {
    _pendingRequests.remove(deviceId);
  }

  /// 验证配对码并确认
  Future<bool> verifyAndConfirm({
    required String deviceId,
    required String pairingCode,
  }) async {
    if (!verifyPairingCode(pairingCode)) {
      return false;
    }
    await confirmPairing(deviceId);
    return true;
  }

  /// 检查设备是否已信任
  bool isDeviceTrusted(String deviceId) {
    return _trustedDevices.containsKey(deviceId);
  }

  /// 添加信任设备
  Future<void> addTrustedDevice(TrustedDevice device) async {
    _trustedDevices[device.deviceId] = device;
    await _saveWhitelist();
  }

  /// 移除信任设备
  Future<void> removeTrustedDevice(String deviceId) async {
    _trustedDevices.remove(deviceId);
    await _saveWhitelist();
  }

  /// 清空所有信任设备
  Future<void> clearTrustedDevices() async {
    _trustedDevices.clear();
    await _saveWhitelist();
  }

  /// 创建TLS安全上下文（自签名证书）
  static Future<SecurityContext> createServerSecurityContext({
    required String certPath,
    required String keyPath,
  }) async {
    final context = SecurityContext()
      ..useCertificateChain(certPath)
      ..usePrivateKey(keyPath);
    return context;
  }

  /// 创建TLS客户端上下文（信任自签名证书）
  static Future<SecurityContext> createClientSecurityContext({
    required String certPath,
  }) async {
    final context = SecurityContext()
      ..setTrustedCertificates(certPath);
    return context;
  }

  /// 生成自签名证书（使用Dart内置方式）
  static Future<void> generateSelfSignedCertificate({
    required String outputDir,
    required String hostName,
  }) async {
    // 证书和密钥文件路径
    final certPath = path.join(outputDir, 'cert.pem');
    final keyPath = path.join(outputDir, 'key.pem');

    // 检查证书是否已存在
    if (File(certPath).existsSync() && File(keyPath).existsSync()) {
      return;
    }

    // 使用 openssl 命令生成自签名证书
    final result = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-keyout',
      keyPath,
      '-out',
      certPath,
      '-days',
      '365',
      '-nodes',
      '-subj',
      '/CN=$hostName/O=LAN Sync/C=CN',
    ]);

    if (result.exitCode != 0) {
      throw Exception('Failed to generate certificate: ${result.stderr}');
    }
  }

  /// 保存白名单到文件
  Future<void> _saveWhitelist() async {
    final filePath = path.join(_storagePath, _whitelistFileName);
    final file = File(filePath);

    final data = _trustedDevices.map(
      (key, value) => MapEntry(key, value.toJson()),
    );

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }

  /// 从文件加载白名单
  Future<void> _loadWhitelist() async {
    final filePath = path.join(_storagePath, _whitelistFileName);
    final file = File(filePath);

    if (!await file.exists()) return;

    try {
      final content = await file.readAsString();
      final data = Map<String, dynamic>.from(
        jsonDecode(content) as Map,
      );

      for (final entry in data.entries) {
        final device = TrustedDevice.fromJson(
          entry.key,
          Map<String, dynamic>.from(entry.value as Map),
        );
        _trustedDevices[device.deviceId] = device;
      }
    } catch (e) {
      // 文件损坏，忽略
    }
  }
}

/// 可信设备
class TrustedDevice {
  final String deviceId;
  final String? deviceName;
  final String? platform;
  final DateTime addedAt;

  TrustedDevice({
    required this.deviceId,
    this.deviceName,
    this.platform,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'deviceName': deviceName,
        'platform': platform,
        'addedAt': addedAt.toIso8601String(),
      };

  factory TrustedDevice.fromJson(String deviceId, Map<String, dynamic> json) {
    return TrustedDevice(
      deviceId: deviceId,
      deviceName: json['deviceName'] as String?,
      platform: json['platform'] as String?,
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }
}

/// 配对请求
class PairingRequest {
  final String deviceId;
  final String deviceName;
  final String platform;
  final String pairingCode;
  final DateTime timestamp;

  PairingRequest({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.pairingCode,
    required this.timestamp,
  });
}
