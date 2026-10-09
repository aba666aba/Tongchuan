import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/adaptive_transfer_service.dart';
import '../services/security_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      _nameController.text = appState.deviceName;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('设置'),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildDeviceSettingsCard(appState),
              const SizedBox(height: 16),
              _buildSecurityCard(appState),
              const SizedBox(height: 16),
              _buildNetworkSettingsCard(appState),
              const SizedBox(height: 16),
              _buildAboutCard(),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceSettingsCard(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '设备设置',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '设备名称',
                hintText: '输入设备名称',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                appState.updateDeviceName(value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityCard(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '安全设置',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('需要配对确认'),
              subtitle: const Text('新设备连接时显示配对码'),
              value: appState.requirePairing,
              onChanged: (value) {
                appState.updateRequirePairing(value);
              },
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(),
            Text(
              '受信设备',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _buildTrustedDevicesList(appState),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showClearTrustedDevicesDialog(appState),
                  icon: const Icon(Icons.delete_sweep),
                  label: const Text('全部清除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustedDevicesList(AppState appState) {
    final trustedDevices = appState.trustedDevices;

    if (trustedDevices.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, 
              color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              '暂无受信设备',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: trustedDevices.entries.map((entry) {
        final device = entry.value;
        return ListTile(
          leading: Icon(
            _getDeviceIcon(device.platform),
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(device.deviceName ?? '未知设备'),
          subtitle: Text(
            '添加于: ${_formatDate(device.addedAt)}',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            color: Theme.of(context).colorScheme.error,
            onPressed: () => _removeTrustedDevice(appState, entry.key),
          ),
          contentPadding: EdgeInsets.zero,
        );
      }).toList(),
    );
  }

  void _removeTrustedDevice(AppState appState, String deviceId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除设备'),
        content: const Text('确定将此设备从受信列表中移除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              appState.removeTrustedDevice(deviceId);
              Navigator.pop(context);
            },
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }

  void _showClearTrustedDevicesDialog(AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除所有设备'),
        content: const Text('确定清除所有受信设备？清除后需要重新配对。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              appState.clearTrustedDevices();
              Navigator.pop(context);
            },
            child: const Text('全部清除'),
          ),
        ],
      ),
    );
  }

  IconData _getDeviceIcon(String? platform) {
    switch (platform?.toLowerCase()) {
      case 'android':
        return Icons.phone_android;
      case 'ios':
        return Icons.phone_iphone;
      case 'windows':
        return Icons.computer;
      case 'macos':
        return Icons.laptop_mac;
      case 'linux':
        return Icons.computer;
      default:
        return Icons.device_unknown;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildNetworkSettingsCard(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '网络设置',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.wifi),
              title: const Text('发现端口'),
              subtitle: const Text('8888'),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('传输端口'),
              subtitle: const Text('8889'),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: const Icon(Icons.speed),
              title: const Text('数据块大小'),
              subtitle: const Text('自适应 (256KB - 16MB)'),
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(),
            Text(
              '传输速度模式',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _buildSpeedModeSelector(),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedModeSelector() {
    final appState = context.watch<AppState>();
    return Column(
      children: SpeedMode.values.map((mode) {
        return RadioListTile<SpeedMode>(
          title: Text(_getSpeedModeTitle(mode)),
          subtitle: Text(_getSpeedModeDescription(mode)),
          value: mode,
          groupValue: appState.speedMode,
          onChanged: (value) {
            appState.updateSpeedMode(value!);
          },
          secondary: Icon(_getSpeedModeIcon(mode)),
          contentPadding: EdgeInsets.zero,
        );
      }).toList(),
    );
  }

  String _getSpeedModeTitle(SpeedMode mode) {
    switch (mode) {
      case SpeedMode.conservative:
        return '保守';
      case SpeedMode.balanced:
        return '均衡';
      case SpeedMode.maximum:
        return '极速';
      case SpeedMode.extreme:
        return '极限 (⚠️)';
    }
  }

  String _getSpeedModeDescription(SpeedMode mode) {
    switch (mode) {
      case SpeedMode.conservative:
        return '网络影响最小，适合共享网络';
      case SpeedMode.balanced:
        return '根据网络状况自动调整';
      case SpeedMode.maximum:
        return '优先速度，可能影响其他设备';
      case SpeedMode.extreme:
        return '强制最大带宽 - 请谨慎使用！';
    }
  }

  IconData _getSpeedModeIcon(SpeedMode mode) {
    switch (mode) {
      case SpeedMode.conservative:
        return Icons.speed;
      case SpeedMode.balanced:
        return Icons.tune;
      case SpeedMode.maximum:
        return Icons.fast_forward;
      case SpeedMode.extreme:
        return Icons.warning;
    }
  }

  Widget _buildAboutCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '关于',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('局域网同步'),
              subtitle: const Text('版本 1.0.0'),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('使用 Flutter 构建'),
              subtitle: const Text('跨平台文件同步'),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}