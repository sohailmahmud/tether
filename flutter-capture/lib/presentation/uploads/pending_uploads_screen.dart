import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/upload_status.dart';
import 'cubit/mock_server_cubit.dart';
import 'cubit/sync_cubit.dart';
import 'cubit/upload_queue_cubit.dart';
import 'cubit/upload_queue_state.dart';
import 'widgets/batch_card.dart';
import 'widgets/mock_server_sheet.dart';

/// Lists submitted batches with their upload status. Batches stay here,
/// files and all, until the server confirms them.
class PendingUploadsScreen extends StatelessWidget {
  const PendingUploadsScreen({super.key});

  Future<void> _chooseMockServer(BuildContext context) async {
    final cubit = context.read<MockServerCubit>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Sized to its content, scrolling on short screens.
      isScrollControlled: true,
      builder: (sheetContext) => MockServerSheet(
        mode: cubit.state,
        onSelected: (mode) {
          unawaited(cubit.select(mode));
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSyncing = context.select(
      (SyncCubit cubit) => cubit.state.isSyncing,
    );
    final isOnline = context.select((SyncCubit cubit) => cubit.state.isOnline);
    final mockMode = context.select((MockServerCubit cubit) => cubit.state);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Uploads'),
        actions: [
          Tooltip(
            message: 'Mock server: ${MockServerSheet.label(mockMode)}',
            child: TextButton.icon(
              onPressed: () => unawaited(_chooseMockServer(context)),
              icon: const Icon(Icons.dns_outlined),
              label: Text(MockServerSheet.shortLabel(mockMode)),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: isSyncing
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox(height: 2),
        ),
      ),
      body: Column(
        children: [
          if (!isOnline) const _OfflineBanner(),
          Expanded(
            child: BlocBuilder<UploadQueueCubit, UploadQueueState>(
              builder: (context, state) {
                if (!state.isLoaded) {
                  return const Center(child: CircularProgressIndicator());
                }
                final batches = state.queue.batches;
                if (batches.isEmpty) {
                  return _Message(
                    icon: state.loadFailed
                        ? Icons.error_outline
                        : Icons.cloud_done_outlined,
                    text: state.loadFailed
                        ? "The upload queue couldn't be read."
                        : 'No pending uploads.\nBatches you upload appear here until the server '
                              'confirms them.',
                  );
                }
                final anyFailed = batches.any(
                  (b) => b.status == UploadStatus.failed,
                );
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: batches.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => index == 0
                      ? _Summary(
                          state: state,
                          showRetry: anyFailed && !isSyncing,
                        )
                      : BatchCard(batch: batches[index - 1]),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Start new upload batch'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tells the user why nothing is uploading, and that it will resume by itself.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: colors.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.wifi_off, color: colors.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "You're offline. Uploads resume automatically when the "
                  'connection returns.',
                  style: TextStyle(color: colors.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.state, required this.showRetry});

  final UploadQueueState state;
  final bool showRetry;

  @override
  Widget build(BuildContext context) {
    final unfinished = state.queue.unfinished;
    final photos = unfinished.fold(0, (sum, batch) => sum + batch.photoCount);
    final text = unfinished.isEmpty
        ? 'All batches uploaded'
        : '${unfinished.length == 1 ? '1 batch' : '${unfinished.length} batches'}'
              ' · ${photos == 1 ? '1 photo' : '$photos photos'} waiting';
    return Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              letterSpacing: 0.8,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // A convenience only: failed batches are also retried automatically.
        if (showRetry)
          FilledButton.tonalIcon(
            onPressed: () =>
                unawaited(context.read<SyncCubit>().sync(retryFailedNow: true)),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry now'),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.white54),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
