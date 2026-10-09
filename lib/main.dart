import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:device_info_plus/device_info_plus.dart';
import 'services/network_service.dart';
import 'services/file_watcher_service.dart';
import 'services/transfer_manager.dart';
import 'services/sharing_service.dart';
import 'services/adaptive_transfer_service.dart' hide TransferProgress;
import 'services/security_service.dart';
import 'screens/home_screen.dart';
import 'screens/send_screen.dart';

void main(List<String> args) {
  // 处理命令行参数（从右键菜单调用）
  if (args.isNotEmpty) {
    final command = args[0];
    final path = args.length > 1 ? args[1] : '';
    
    if (command == '--send' || command == '--send-folder') {
      // 启动发送模式
      runApp(SendApp(filePath: path));
      return;
    }
  }
  
  // 正常启动
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: '局域网同步',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}

class AppState extends ChangeNotifier {
  NetworkService? _networkService;
  FileWatcherService? _fileWatcher;
  TransferManager? _transferManager;
  SharingService? _sharingService;
  SecurityService? _securityService;

  String _syncPath = '';
  String _deviceName = '';
  bool _isRunning = false;
  bool _requirePairing = true;
  SpeedMode _speedMode = SpeedMode.balanced;
  List<ConnectedDevice> _devices = [];
  List<TransferProgress> _transfers = [];
  List<SharedFile> _sharedFiles = [];

  // 防止回环：记录最近收到的文件，避免重新发送
  final Set<String> _recentlyReceivedFiles = {};
  Timer? _cleanupTimer;
  // 设备最后活跃时间，用于清理离线设备
  final Map<String, DateTime> _deviceLastSeen = {};

  NetworkService? get networkService => _networkService;
  FileWatcherService? get fileWatcher => _fileWatcher;
  TransferManager? get transferManager => _transferManager;
  SharingService? get sharingService => _sharingService;
  SecurityService? get securityService => _securityService;
  String get syncPath => _syncPath;
  String get deviceName => _deviceName;
  bool get isRunning => _isRunning;
  bool get requirePairing => _requirePairing;
  SpeedMode get speedMode => _speedMode;
  List<ConnectedDevice> get devices => _devices;
  List<TransferProgress> get transfers => _transfers;
  List<SharedFile> get sharedFiles => _sharedFiles;
  Map<String, TrustedDevice> get trustedDevices =>
      _securityService?.trustedDevices ?? {};

  Future<void> initialize() async {
    // 获取设备品牌型号
    _deviceName = await _getDeviceName();
    
    // 初始化安全服务
    final appDir = Directory.current.path;
    final securityDir = Directory('$appDir/lan_sync_security');
    if (!securityDir.existsSync()) {
      securityDir.createSync(recursive: true);
    }
    _securityService = SecurityService(storagePath: securityDir.path);
    await _securityService!.initialize();

    // 初始化分享服务（Android）
    if (Platform.isAndroid) {
      _sharingService = SharingService();
      _sharingService!.startListening();
      _sharingService!.sharedFilesStream.listen((files) {
        _sharedFiles = files;
        notifyListeners();
      });
    }

    notifyListeners();
  }

  /// 获取设备品牌型号
  Future<String> _getDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        return '${android.brand} ${android.model}';
      } else if (Platform.isWindows) {
        final windows = await deviceInfo.windowsInfo;
        return windows.computerName;
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        return '${ios.name} ${ios.model}';
      } else if (Platform.isLinux) {
        final linux = await deviceInfo.linuxInfo;
        return linux.name;
      } else if (Platform.isMacOS) {
        final mac = await deviceInfo.macOsInfo;
        return mac.computerName;
      }
    } catch (_) {}
    return '我的设备';
  }

  Future<void> setSyncPath(String path) async {
    _syncPath = path;
    notifyListeners();
  }

  Future<void> startSync() async {
    if (_syncPath.isEmpty) {
      throw Exception('请先选择同步文件夹');
    }

    _networkService = NetworkService(
      deviceName: _deviceName,
      platform: Platform.isWindows ? 'windows' : 'android',
      securityService: _securityService,
      requirePairing: _requirePairing,
    );

    _fileWatcher = FileWatcherService(watchPath: _syncPath);

    _transferManager = TransferManager(
      networkService: _networkService!,
      syncPath: _syncPath,
      speedMode: _speedMode,
    );

    await _networkService!.start();
    await _fileWatcher!.start();
    _transferManager!.start();

    _networkService!.deviceStream.listen((device) {
      _deviceLastSeen[device.deviceId] = DateTime.now();

      // 去重：按 deviceId 更新已有设备
      final existingIndex = _devices.indexWhere((d) => d.deviceId == device.deviceId);
      if (existingIndex >= 0) {
        _devices[existingIndex] = device;
      } else {
        _devices.add(device);
        // 新设备发现后，发送所有已有文件
        _sendAllExistingFiles(device);
      }
      notifyListeners();
    });

    // 定期清理离线设备（30秒无响应视为离线）
    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final now = DateTime.now();
      _devices.removeWhere((device) {
        final lastSeen = _deviceLastSeen[device.deviceId];
        if (lastSeen != null && now.difference(lastSeen).inSeconds > 30) {
          _deviceLastSeen.remove(device.deviceId);
          return true;
        }
        return false;
      });
      notifyListeners();
    });

    // 监听文件接收完成，记录到防回环集合
    _transferManager!.fileReceivedStream.listen((relativePath) {
      _recentlyReceivedFiles.add(relativePath);
      // 5 秒后移除，防止文件修改事件丢失
      Timer(const Duration(seconds: 5), () {
        _recentlyReceivedFiles.remove(relativePath);
      });
    });

    _fileWatcher!.eventStream.listen((event) {
      if (event.type == FileSystemEventType.create ||
          event.type == FileSystemEventType.modify) {
        final relativePath = p.relative(event.filePath, from: _syncPath);
        // 跳过最近收到的文件，防止回环
        if (_recentlyReceivedFiles.contains(relativePath)) return;
        // 跳过临时文件
        if (relativePath.startsWith('.tmp_')) return;

        for (var device in _devices) {
          _transferManager!.sendFile(event.filePath, device);
        }
      }
    });

    _transferManager!.progressStream.listen((progress) {
      final index = _transfers.indexWhere((t) => t.transferId == progress.transferId);
      if (index >= 0) {
        _transfers[index] = progress;
      } else {
        _transfers.add(progress);
      }
      notifyListeners();
    });

    _isRunning = true;
    notifyListeners();
  }

  Future<void> stopSync() async {
    await _networkService?.stop();
    await _fileWatcher?.stop();
    _cleanupTimer?.cancel();

    _isRunning = false;
    _devices.clear();
    _transfers.clear();
    _recentlyReceivedFiles.clear();
    notifyListeners();
  }

  /// 向指定设备发送同步文件夹中的所有已有文件
  Future<void> _sendAllExistingFiles(ConnectedDevice device) async {
    final directory = Directory(_syncPath);
    if (!directory.existsSync()) return;

    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        final filePath = entity.path;
        final fileName = p.basename(filePath);

        // 跳过隐藏文件、临时文件、系统文件
        if (fileName.startsWith('.') ||
            fileName.endsWith('.tmp') ||
            fileName.endsWith('.temp') ||
            fileName.endsWith('~') ||
            fileName == 'Thumbs.db' ||
            fileName == 'desktop.ini' ||
            fileName == '.DS_Store') {
          continue;
        }

        try {
          await _transferManager!.sendFile(filePath, device);
        } catch (_) {}
      }
    }
  }

  void updateDeviceName(String name) {
    _deviceName = name;
    notifyListeners();
  }

  void updateSpeedMode(SpeedMode mode) {
    _speedMode = mode;
    notifyListeners();
  }

  void updateRequirePairing(bool value) {
    _requirePairing = value;
    notifyListeners();
  }

  Future<void> removeTrustedDevice(String deviceId) async {
    await _securityService?.removeTrustedDevice(deviceId);
    notifyListeners();
  }

  Future<void> clearTrustedDevices() async {
    await _securityService?.clearTrustedDevices();
    notifyListeners();
  }

  /// 手动信任设备（用户点击确认）
  Future<void> trustDevice(ConnectedDevice device) async {
    if (_securityService != null) {
      await _securityService!.addTrustedDevice(TrustedDevice(
        deviceId: device.deviceId,
        deviceName: device.deviceName,
        platform: device.platform,
        addedAt: DateTime.now(),
      ));
    }
    device.isTrusted = true;
    notifyListeners();
    // 信任后立即发送所有已有文件
    _sendAllExistingFiles(device);
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();