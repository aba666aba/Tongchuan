import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 配对码输入对话框
/// 用于在发送端输入接收到的配对码进行验证
class PairingVerifyDialog extends StatefulWidget {
  final String targetDeviceName;
  final String expectedCode;
  final Function(String code) onVerify;

  const PairingVerifyDialog({
    super.key,
    required this.targetDeviceName,
    required this.expectedCode,
    required this.onVerify,
  });

  /// 显示验证对话框
  static Future<bool> show({
    required BuildContext context,
    required String targetDeviceName,
    required String expectedCode,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PairingVerifyDialog(
        targetDeviceName: targetDeviceName,
        expectedCode: expectedCode,
        onVerify: (code) {
          Navigator.of(context).pop(code == expectedCode);
        },
      ),
    );
    return result ?? false;
  }

  @override
  State<PairingVerifyDialog> createState() => _PairingVerifyDialogState();
}

class _PairingVerifyDialogState extends State<PairingVerifyDialog> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  String _errorText = '';

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onCodeChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }

    // 检查是否所有字段都已填写
    final code = _controllers.map((c) => c.text).join();
    if (code.length == 6) {
      setState(() {
        _errorText = '';
      });
    }
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].text = '';
    }
  }

  void _verify() {
    final code = _controllers.map((c) => c.text).join();
    if (code.length != 6) {
      setState(() {
        _errorText = '请输入完整的6位数字';
      });
      return;
    }

    if (code != widget.expectedCode) {
      setState(() {
        _errorText = '配对码不匹配，请检查后重试。';
      });
      // 清空输入
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
      return;
    }

    widget.onVerify(code);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(
        Icons.verified_user,
        size: 48,
        color: colorScheme.primary,
      ),
      title: const Text('验证配对码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '请输入以下设备上显示的6位配对码',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          Text(
            widget.targetDeviceName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),

          // 配对码输入
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (index) {
              if (index == 3) {
                return Row(
                  children: [
                    const SizedBox(width: 8),
                    _buildCodeField(index),
                    const SizedBox(width: 8),
                  ],
                );
              }
              return _buildCodeField(index);
            }),
          ),

          if (_errorText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _errorText,
              style: TextStyle(
                color: colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: 16),
          Text(
            '两台设备上的配对码必须完全一致',
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
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _verify,
          icon: const Icon(Icons.check),
          label: const Text('验证'),
        ),
      ],
    );
  }

  Widget _buildCodeField(int index) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 40,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) => _onKeyEvent(index, event),
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: colorScheme.primary,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: colorScheme.error,
              ),
            ),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          onChanged: (value) => _onCodeChanged(index, value),
        ),
      ),
    );
  }
}
