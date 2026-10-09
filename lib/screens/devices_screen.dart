import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('设备'),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: appState.devices.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.devices_other,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '未发现设备',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '开始同步以发现局域网中的设备',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final device = appState.devices[index];
                      return _DeviceCard(device: device);
                    },
                    childCount: appState.devices.length,
                  ),
                ),
        ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final dynamic device;

  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appState = context.read<AppState>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getDeviceIcon(device.platform),
                  size: 32,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.deviceName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        device.platform.toUpperCase(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                // 信任状态标签
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: device.isTrusted
                        ? Colors.green.withValues(alpha: 0.1)
                        : colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        device.isTrusted ? Icons.verified : Icons.shield,
                        size: 14,
                        color: device.isTrusted ? Colors.green : colorScheme.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        device.isTrusted ? '已信任' : '未信任',
                        style: TextStyle(
                          fontSize: 12,
                          color: device.isTrusted ? Colors.green : colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 连接状态
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: Colors.green,
                ),
                const SizedBox(width: 4),
                Text(
                  '通过局域网连接',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  device.address.address,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            // 未信任设备显示信任按钮
            if (!device.isTrusted) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showTrustDialog(context, appState),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('信任此设备'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showTrustDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('信任设备'),
        content: Text('确定信任 ${device.deviceName}？\n信任后将自动同步文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              appState.trustDevice(device);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${device.deviceName} 已被信任')),
              );
            },
            child: const Text('信任'),
          ),
        ],
      ),
    );
  }

  IconData _getDeviceIcon(String platform) {
    switch (platform.toLowerCase()) {
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
}