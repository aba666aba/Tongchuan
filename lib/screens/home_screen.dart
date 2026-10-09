import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../main.dart';
import '../widgets/pairing_dialog.dart';
import 'devices_screen.dart';
import 'transfers_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  StreamSubscription? _pairingSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      appState.initialize();
      _listenPairingRequests(appState);
    });
  }

  void _listenPairingRequests(AppState appState) {
    _pairingSubscription?.cancel();
    final securityService = appState.securityService;
    if (securityService == null) return;

    _pairingSubscription = securityService.pairingRequestStream.listen((request) {
      if (!mounted) return;
      _showPairingDialog(request, appState);
    });
  }

  Future<void> _showPairingDialog(dynamic request, AppState appState) async {
    final accepted = await PairingDialog.show(
      context: context,
      request: request,
    );

    if (accepted) {
      await appState.networkService?.confirmPairing(request.deviceId, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${request.deviceName} 已被信任')),
        );
      }
    } else {
      appState.networkService?.confirmPairing(request.deviceId, false);
    }
  }

  @override
  void dispose() {
    _pairingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    
    final screens = [
      _buildMainScreen(appState),
      const DevicesScreen(),
      const TransfersScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.devices_outlined),
            selectedIcon: Icon(Icons.devices),
            label: '设备',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz),
            label: '传输',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }

  Widget _buildMainScreen(AppState appState) {
    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('局域网同步'),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildStatusCard(appState),
              const SizedBox(height: 16),
              _buildSyncFolderCard(appState),
              const SizedBox(height: 16),
              _buildQuickActionsCard(appState),
              const SizedBox(height: 16),
              _buildDeviceInfoCard(appState),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  appState.isRunning ? Icons.sync : Icons.sync_disabled,
                  color: appState.isRunning ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  appState.isRunning ? '同步中' : '已停止',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              appState.isRunning
                  ? '已连接 ${appState.devices.length} 台设备'
                  : '选择文件夹后开始同步',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncFolderCard(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '同步文件夹',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    appState.syncPath.isEmpty
                        ? '未选择文件夹'
                        : appState.syncPath,
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _selectFolder(appState),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('选择'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '快捷操作',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: appState.isRunning ? null : () => _startSync(appState),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: appState.isRunning ? () => _stopSync(appState) : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('停止'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfoCard(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '设备信息',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.computer),
              title: Text(appState.deviceName),
              subtitle: const Text('本机'),
              contentPadding: EdgeInsets.zero,
            ),
            if (appState.devices.isNotEmpty) ...[
              const Divider(),
              Text(
                '已连接设备',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              ...appState.devices.map((device) => ListTile(
                leading: Icon(
                  device.platform == 'windows' ? Icons.computer : Icons.phone_android,
                ),
                title: Text(device.deviceName),
                subtitle: Text(device.platform),
                contentPadding: EdgeInsets.zero,
              )),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _selectFolder(AppState appState) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      await appState.setSyncPath(result);
    }
  }

  Future<void> _startSync(AppState appState) async {
    try {
      await appState.startSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('同步已开始')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('错误: $e')),
        );
      }
    }
  }

  Future<void> _stopSync(AppState appState) async {
    await appState.stopSync();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('同步已停止')),
      );
    }
  }
}