import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/security_service.dart';

/// 配对确认对话框
/// 当新设备尝试连接时显示，要求用户确认配对码
class PairingDialog extends StatefulWidget {
  final PairingRequest request;
  final Function(bool accepted) onConfirm;

  const PairingDialog({
    super.key,
    required this.request,
    required this.onConfirm,
  });

  /// 显示配对对话框
  static Future<bool> show({
    required BuildContext context,
    required PairingRequest request,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PairingDialog(
        request: request,
        onConfirm: (accepted) {
          Navigator.of(context).pop(accepted);
        },
      ),
    );
    return result ?? false;
  }

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _timerController;
  int _remainingSeconds = 60;
  bool _codeVisible = false;

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..addListener(() {
        setState(() {
          _remainingSeconds = 60 - _timerController.value.toInt();
        });
      });
    _timerController.forward();
  }

  @override
  void dispose() {
    _timerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(
        Icons.security,
        size: 48,
        color: colorScheme.primary,
      ),
      title: const Text('新设备连接'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 设备信息
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  _getDeviceIcon(widget.request.platform),
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.request.deviceName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '平台: ${widget.request.platform}',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 配对码显示
          Text(
            '配对码',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                _codeVisible = !_codeVisible;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _codeVisible
                        ? _formatPairingCode(widget.request.pairingCode)
                        : '• • • • • •',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: colorScheme.onPrimaryContainer,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _codeVisible ? Icons.visibility_off : Icons.visibility,
                    color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: widget.request.pairingCode),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('配对码已复制')),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制配对码'),
          ),
          const SizedBox(height: 16),

          // 倒计时
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.timer,
                size: 16,
                color: _remainingSeconds < 10
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '${_remainingSeconds}秒后过期',
                style: TextStyle(
                  color: _remainingSeconds < 10
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 提示
          Text(
            '请确认两台设备上的配对码一致',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => widget.onConfirm(false),
          child: const Text('拒绝'),
        ),
        FilledButton.icon(
          onPressed: () => widget.onConfirm(true),
          icon: const Icon(Icons.check),
          label: const Text('接受'),
        ),
      ],
    );
  }

  String _formatPairingCode(String code) {
    if (code.length == 6) {
      return '${code.substring(0, 3)} ${code.substring(3)}';
    }
    return code;
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
