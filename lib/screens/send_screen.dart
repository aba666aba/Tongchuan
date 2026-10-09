import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/network_service.dart';
import '../services/transfer_manager.dart';

class SendApp extends StatelessWidget {
  final String filePath;
  
  const SendApp({super.key, required this.filePath});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: '局域网同步 - 发送',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: SendScreen(filePath: filePath),
      ),
    );
  }
}

class SendScreen extends StatefulWidget {
  final String filePath;
  
  const SendScreen({super.key, required this.filePath});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  bool _isSearching = true;
  List<ConnectedDevice> _devices = [];
  ConnectedDevice? _selectedDevice;
  bool _isSending = false;
  double _progress = 0;
  String _status = '正在搜索设备...';

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    final appState = context.read<AppState>();
    await appState.initialize();
    
    // 启动网络服务
    final networkService = NetworkService(
      deviceName: appState.deviceName,
      platform: Platform.isWindows ? 'windows' : 'android',
    );
    
    await networkService.start();
    
    // 监听设备发现
    networkService.deviceStream.listen((device) {
      setState(() {
        if (!_devices.any((d) => d.deviceId == device.deviceId)) {
          _devices.add(device);
        }
      });
    });
    
    // 等待一段时间发现设备
    await Future.delayed(const Duration(seconds: 3));
    
    setState(() {
      _isSearching = false;
      if (_devices.isEmpty) {
        _status = '未发现设备，请确保其他设备在同一网络中。';
      } else {
        _status = '选择要发送的设备：';
      }
    });
  }

  Future<void> _sendFile() async {
    if (_selectedDevice == null) return;
    
    setState(() {
      _isSending = true;
      _status = '正在发送文件...';
    });
    
    try {
      final appState = context.read<AppState>();
      final transferManager = TransferManager(
        networkService: appState.networkService!,
        syncPath: Directory(widget.filePath).parent.path,
      );
      
      transferManager.progressStream.listen((progress) {
        setState(() {
          _progress = progress.progress;
          if (progress.isCompleted) {
            _status = '文件发送成功！';
            _isSending = false;
          }
          if (progress.isError) {
            _status = '错误: ${progress.errorMessage}';
            _isSending = false;
          }
        });
      });
      
      await transferManager.sendFile(widget.filePath, _selectedDevice!);
    } catch (e) {
      setState(() {
        _status = '错误: $e';
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.filePath.split(Platform.pathSeparator).last;
    final isFolder = FileSystemEntity.isDirectorySync(widget.filePath);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isFolder ? '发送文件夹' : '发送文件'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isSearching ? null : () {
              setState(() {
                _devices.clear();
                _isSearching = true;
                _status = '正在搜索设备...';
              });
              _startDiscovery();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 文件信息卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isFolder ? Icons.folder : Icons.file_present,
                          size: 32,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fileName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                isFolder ? '文件夹' : '文件',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.filePath,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // 状态文本
            Text(
              _status,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            
            // 设备列表或进度条
            if (_isSearching)
              const Center(
                child: CircularProgressIndicator(),
              )
            else if (_isSending)
              Column(
                children: [
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text('${(_progress * 100).toStringAsFixed(1)}%'),
                ],
              )
            else if (_devices.isEmpty)
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.devices_other,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    const Text('未发现设备'),
                    const SizedBox(height: 8),
                    const Text(
                      '请确保其他设备已打开局域网同步',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    final isSelected = _selectedDevice?.deviceId == device.deviceId;
                    
                    return Card(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: ListTile(
                        leading: Icon(
                          device.platform == 'windows'
                              ? Icons.computer
                              : Icons.phone_android,
                        ),
                        title: Text(device.deviceName),
                        subtitle: Text(device.platform),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedDevice = device;
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
            
            // 发送按钮
            if (!_isSearching && _devices.isNotEmpty && !_isSending)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: FilledButton.icon(
                  onPressed: _selectedDevice != null ? _sendFile : null,
                  icon: const Icon(Icons.send),
                  label: const Text('发送'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}