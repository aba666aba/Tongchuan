import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/transfer_manager.dart';

class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('传输记录'),
          actions: [
            if (appState.transfers.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep),
                onPressed: () {
                  appState.transferManager?.cleanupCompletedTransfers();
                },
                tooltip: '清除已完成',
              ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: appState.transfers.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.swap_horiz,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '暂无传输',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '文件传输记录将在此显示',
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
                      final transfer = appState.transfers[index];
                      return _TransferCard(transfer: transfer);
                    },
                    childCount: appState.transfers.length,
                  ),
                ),
        ),
      ],
    );
  }
}

class _TransferCard extends StatelessWidget {
  final TransferProgress transfer;

  const _TransferCard({required this.transfer});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  transfer.isSending ? Icons.upload : Icons.download,
                  color: transfer.isError
                      ? Colors.red
                      : transfer.isCompleted
                          ? Colors.green
                          : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transfer.fileName,
                        style: Theme.of(context).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        transfer.isSending ? '发送中' : '接收中',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                if (transfer.isCompleted)
                  Icon(
                    Icons.check_circle,
                    color: Colors.green,
                  )
                else if (transfer.isError)
                  Icon(
                    Icons.error,
                    color: Colors.red,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!transfer.isCompleted && !transfer.isError) ...[
              LinearProgressIndicator(
                value: transfer.progress,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    transfer.progressPercent,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    transfer.speedText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            if (transfer.isError) ...[
              const SizedBox(height: 8),
              Text(
                transfer.errorMessage ?? '传输失败',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.red,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}