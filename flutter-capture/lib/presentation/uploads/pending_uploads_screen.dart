import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'cubit/upload_queue_cubit.dart';
import 'cubit/upload_queue_state.dart';
import 'widgets/batch_card.dart';

/// Lists submitted batches with their upload status. Batches stay here,
/// files and all, until the server confirms them.
class PendingUploadsScreen extends StatelessWidget {
  const PendingUploadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pending Uploads')),
      body: BlocBuilder<UploadQueueCubit, UploadQueueState>(
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
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: batches.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => index == 0
                ? _Summary(state: state)
                : BatchCard(batch: batches[index - 1]),
          );
        },
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

class _Summary extends StatelessWidget {
  const _Summary({required this.state});

  final UploadQueueState state;

  @override
  Widget build(BuildContext context) {
    final unfinished = state.queue.unfinished;
    final photos = unfinished.fold(0, (sum, batch) => sum + batch.photoCount);
    final text = unfinished.isEmpty
        ? 'All batches uploaded'
        : '${unfinished.length == 1 ? '1 batch' : '${unfinished.length} batches'}'
              ' · ${photos == 1 ? '1 photo' : '$photos photos'} waiting';
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
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
