import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../protocol/protocol.dart';
import 'security_service.dart';

class ConnectedDevice {
  final String deviceId;
  final String deviceName;
  final String platform;
  final InternetAddress address;
  Socket? socket;
  bool isTrusted;

  ConnectedDevice({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.address,
    this.socket,
    this.isTrusted = false,
  });
}

/// 连接请求（用于配对流程）
class ConnectionRequest {
  final String deviceId;
  final String deviceName;
  final String platform;
  final String pairingCode;
  final InternetAddress address;

  ConnectionRequest({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.pairingCode,
    required this.address,
  });
}

class NetworkService {
  static const int discoveryPort = 8888;
  static const int transferPort = 8889;
  static const String discoveryMagic = 'LAN_SYNC_DISCOVERY';

  final _uuid = const Uuid();
  late String _deviceId;
  late String _deviceName;
  late String _platform;
  SecurityService? _securityService;
  bool _requirePairing = true;

  ServerSocket? _transferServer;
  RawDatagramSocket? _discoverySocket;

  final Map<String, ConnectedDevice> _connectedDevices = {};
  final StreamController<ConnectedDevice> _deviceController =
      StreamController<ConnectedDevice>.broadcast();
  final StreamController<Uint8List> _messageController =
      StreamController<Uint8List>.broadcast();
  final StreamController<ConnectionRequest> _connectionRequestController =
      StreamController<ConnectionRequest>.broadcast();

  Stream<ConnectedDevice> get deviceStream => _deviceController.stream;
  Stream<Uint8List> get messageStream => _messageController.stream;
  Stream<ConnectionRequest> get connectionRequestStream =>
      _connectionRequestController.stream;
  Map<String, ConnectedDevice> get connectedDevices =>
      Map.unmodifiable(_connectedDevices);

  NetworkService({
    required String deviceName,
    required String platform,
    SecurityService? securityService,
    bool requirePairing = true,
  }) {
    _deviceId = _uuid.v4();
    _deviceName = deviceName;
    _platform = platform;
    _securityService = securityService;
    _requirePairing = requirePairing;
  }

  Future<void> start() async {
    await _startDiscoveryServer();
    await _startTransferServer();
    _startDiscoveryBroadcast();
  }

  Future<void> stop() async {
    await _transferServer?.close();
    _discoverySocket?.close();
    for (var device in _connectedDevices.values) {
      await device.socket?.close();
    }
    _connectedDevices.clear();
  }

  Future<void> _startDiscoveryServer() async {
    _discoverySocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );

    _discoverySocket!.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = _discoverySocket!.receive();
        if (datagram != null) {
          _handleDiscoveryMessage(datagram);
        }
      }
    });
  }

  Future<void> _startTransferServer() async {
    _transferServer = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      transferPort,
      shared: true,
    );

    _transferServer!.listen((Socket socket) {
      _configureSocketForHighPerformance(socket);
      _handleIncomingConnection(socket);
    });
  }

  void _startDiscoveryBroadcast() {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final message = DiscoveryMessage(
          deviceId: _deviceId,
          deviceName: _deviceName,
          platform: _platform,
          port: transferPort,
        );

        final data = message.toMessage().serialize();

        // 枚举所有网络接口，向每个子网的广播地址发送
        try {
          final interfaces = await NetworkInterface.list(
            type: InternetAddressType.IPv4,
            includeLinkLocal: false,
          );

          for (final interface in interfaces) {
            for (final addr in interface.addresses) {
              try {
                final broadcastAddr = _getSubnetBroadcast(addr.address);
                final socket = await RawDatagramSocket.bind(
                  InternetAddress.anyIPv4,
                  0,
                  reuseAddress: true,
                );
                socket.broadcastEnabled = true;
                socket.send(data, InternetAddress(broadcastAddr), discoveryPort);
                socket.close();
              } catch (_) {}
            }
          }
        } catch (_) {}

        // 同时发送受限广播作为兜底
        try {
          final socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            0,
            reuseAddress: true,
          );
          socket.broadcastEnabled = true;
          socket.send(data, InternetAddress('255.255.255.255'), discoveryPort);
          socket.close();
        } catch (_) {}
      } catch (e) {
        // Ignore broadcast errors
      }
    });
  }

  /// 根据 IP 计算子网广播地址（假设 /24 子网）
  String _getSubnetBroadcast(String ip) {
    final parts = ip.split('.');
    return '${parts[0]}.${parts[1]}.${parts[2]}.255';
  }

  void _handleDiscoveryMessage(Datagram datagram) {
    try {
      final message =
          ProtocolMessage.deserialize(Uint8List.fromList(datagram.data));
      if (message == null || message.type != MessageType.discovery) return;

      final discovery = DiscoveryMessage.fromMessage(message);
      if (discovery.deviceId == _deviceId) return;

      if (!_connectedDevices.containsKey(discovery.deviceId)) {
        final isTrusted = _securityService?.isDeviceTrusted(discovery.deviceId) ?? false;
        final device = ConnectedDevice(
          deviceId: discovery.deviceId,
          deviceName: discovery.deviceName,
          platform: discovery.platform,
          address: datagram.address,
          isTrusted: isTrusted,
        );

        _connectedDevices[discovery.deviceId] = device;
        _deviceController.add(device);
      }
    } catch (e) {
      print('Error handling discovery message: $e');
    }
  }

  Future<void> _handleIncomingConnection(Socket socket) async {
    socket.listen(
      (Uint8List data) {
        _messageController.add(data);
      },
      onDone: () {
        // Connection closed
      },
      onError: (error) {
        // Ignore socket errors
      },
    );
  }

  /// 请求连接到设备（含配对验证）
  Future<bool> requestConnection(ConnectedDevice device) async {
    // 如果不需要配对，直接允许
    if (!_requirePairing) {
      return true;
    }

    // 无安全服务，跳过验证
    if (_securityService == null) {
      return true;
    }

    // 设备已信任，直接允许
    if (_securityService!.isDeviceTrusted(device.deviceId)) {
      device.isTrusted = true;
      return true;
    }

    // 需要配对：生成配对码
    final pairingCode = _securityService!.generatePairingCode();
    _securityService!.requestPairing(
      device.deviceId,
      device.deviceName,
      device.platform,
      pairingCode,
    );

    // 返回 true 表示配对码已生成，UI 层需要监听 connectionRequestStream
    return true;
  }

  /// 连接到设备（需先确认已信任）
  Future<Socket> connectToDevice(ConnectedDevice device) async {
    // 检查是否需要配对验证
    if (_requirePairing && _securityService != null) {
      if (!_securityService!.isDeviceTrusted(device.deviceId)) {
        throw Exception('Device not trusted. Please pair first.');
      }
    }

    final socket = await Socket.connect(device.address, transferPort);
    _configureSocketForHighPerformance(socket);

    socket.listen(
      (Uint8List data) {
        _messageController.add(data);
      },
      onDone: () {
        _connectedDevices.remove(device.deviceId);
      },
      onError: (error) {
        // Ignore connection errors
      },
    );

    return socket;
  }

  /// 确认配对请求（接收端调用）
  Future<void> confirmPairing(String deviceId, bool accepted) async {
    if (_securityService == null) return;

    final request = _securityService!.getPendingRequest(deviceId);
    if (request == null) return;

    if (accepted) {
      _securityService!.confirmPairing(deviceId);
    } else {
      _securityService!.rejectPairing(deviceId);
    }
  }

  /// 配置Socket为高性能传输模式
  void _configureSocketForHighPerformance(Socket socket) {
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {
      // 某些平台可能不支持所有选项
    }
  }

  Future<void> sendMessage(Socket socket, ProtocolMessage message) async {
    final data = message.serialize();
    socket.add(data);
    await socket.flush();
  }

  String get deviceId => _deviceId;
  String get deviceName => _deviceName;
  String get platform => _platform;
}
