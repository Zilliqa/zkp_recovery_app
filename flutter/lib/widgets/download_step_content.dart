import 'package:flutter/material.dart';

import 'package:zkp_recovery_app/models/download_status.dart';

class DownloadStepContent extends StatelessWidget {
  final FileDownloadProgress progress;
  final VoidCallback onRetry;

  const DownloadStepContent({
    super.key,
    required this.progress,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDownloaded = progress.state == DownloadState.downloaded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'This file is required to generate your proof. It is downloaded once and cached on this device.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        _DownloadListTile(
          spec: ProvingArtifacts.artifact,
          progress: progress,
          onRetry: onRetry,
        ),
        if (!allDownloaded) ...[
          const SizedBox(height: 12),
          Text(
            'Please wait for the download to finish.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _DownloadListTile extends StatelessWidget {
  final RemoteFileSpec spec;
  final FileDownloadProgress progress;
  final VoidCallback onRetry;

  const _DownloadListTile({
    required this.spec,
    required this.progress,
    required this.onRetry,
  });

  Widget _statusIcon() {
    switch (progress.state) {
      case DownloadState.notDownloaded:
        return const Icon(Icons.cancel, color: Colors.red);
      case DownloadState.downloading:
        return const Icon(Icons.downloading, color: Colors.blue);
      case DownloadState.downloaded:
        return const Icon(Icons.download_done, color: Colors.green);
      case DownloadState.checksum:
        return const Icon(Icons.security, color:Colors.amber);
      case DownloadState.error:
        return IconButton(
          icon: const Icon(Icons.error, color: Colors.red),
          tooltip: 'Retry',
          onPressed: onRetry,
        );
    }
  }

  String _subtitle() {
    switch (progress.state) {
      case DownloadState.notDownloaded:
        return 'Not downloaded';
      case DownloadState.downloading:
        final pct = progress.fractionComplete;
        return pct != null
            ? 'Downloading… ${(pct * 100).toStringAsFixed(0)}%'
            : 'Downloading…';
      case DownloadState.checksum:
        final pct = progress.fractionComplete;
        return pct != null
            ? 'Checksumming… ${(pct * 100).toStringAsFixed(0)}%'
            : 'Checksumming…';
      case DownloadState.downloaded:
        return 'Ready';
      case DownloadState.error:
        return 'Error: ${progress.errorMessage ?? 'unknown'} - tap to retry';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: _statusIcon(),
        title: Text(spec.displayName),
        subtitle: Text(_subtitle()),
      ),
    );
  }
}
