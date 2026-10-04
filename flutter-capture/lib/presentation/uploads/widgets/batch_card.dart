import 'dart:io';

import 'package:flutter/material.dart';

import '../../../domain/entities/upload_batch.dart';
import '../../../domain/entities/upload_item.dart';
import '../../../domain/entities/upload_status.dart';
import '../upload_formatting.dart';

/// One queued batch: size, time, upload status and its first photos.
class BatchCard extends StatelessWidget {
  const BatchCard({super.key, required this.batch});

  final UploadBatch batch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _StatusStyle.of(batch, theme.colorScheme);
    final lastError = batch.lastError;
    final detailStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.photoCount == 1
                            ? '1 photo'
                            : '${batch.photoCount} photos',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatDateTime(context, batch.submittedAt ?? batch.createdAt)}'
                        ' · ${formatBytes(batch.totalBytes)}',
                        style: detailStyle,
                      ),
                    ],
                  ),
                ),
                _StatusChip(style: style),
              ],
            ),
            const SizedBox(height: 12),
            if (batch.status == UploadStatus.completed)
              const _UploadedNote()
            else
              _ThumbnailStrip(items: batch.items),
            if (batch.status == UploadStatus.uploading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (batch.status == UploadStatus.failed) ...[
              const SizedBox(height: 8),
              if (lastError != null)
                Text(
                  lastError,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              Text(
                _retryText(context, batch.nextAttemptAt),
                style: detailStyle,
              ),
            ] else if (batch.status == UploadStatus.pending &&
                lastError != null) ...[
              // e.g. an upload interrupted by the app being closed.
              const SizedBox(height: 8),
              Text(lastError, style: detailStyle),
            ],
          ],
        ),
      ),
    );
  }
}

String _retryText(BuildContext context, DateTime? nextAttemptAt) {
  if (nextAttemptAt == null || !nextAttemptAt.isAfter(DateTime.now())) {
    return 'Retrying as soon as possible.';
  }
  final time = MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(nextAttemptAt));
  return 'Next automatic retry at $time, or sooner when the connection returns.';
}

/// Replaces the thumbnails once uploaded: the files have been deleted.
class _UploadedNote extends StatelessWidget {
  const _UploadedNote();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.cloud_done_outlined, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Stored on the server; removed from this device.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _StatusStyle {
  const _StatusStyle(this.label, this.icon, this.color);

  factory _StatusStyle.of(UploadBatch batch, ColorScheme colors) =>
      switch (batch.status) {
        UploadStatus.draft => _StatusStyle(
          'Capturing',
          Icons.photo_camera_outlined,
          colors.outline,
        ),
        UploadStatus.pending => _StatusStyle(
          'Waiting to upload',
          Icons.schedule,
          colors.onSurfaceVariant,
        ),
        UploadStatus.uploading => _StatusStyle(
          'Uploading',
          Icons.cloud_upload_outlined,
          colors.primary,
        ),
        UploadStatus.failed => _StatusStyle(
          batch.retryCount == 1 ? 'Failed once' : 'Failed ${batch.retryCount}×',
          Icons.error_outline,
          colors.error,
        ),
        UploadStatus.completed => const _StatusStyle(
          'Uploaded',
          Icons.check_circle_outline,
          Color(0xFF4ADE80),
        ),
      };

  final String label;
  final IconData icon;
  final Color color;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.style});

  final _StatusStyle style;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: style.color.withValues(alpha: 0.14),
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 14, color: style.color),
            const SizedBox(width: 4),
            Text(
              style.label,
              style: TextStyle(
                color: style.color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// As many thumbnails as fit the card's width, then "+N" for the rest.
class _ThumbnailStrip extends StatelessWidget {
  const _ThumbnailStrip({required this.items});

  static const _size = 52.0;
  static const _gap = 6.0;

  final List<UploadItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fits = ((constraints.maxWidth + _gap) / (_size + _gap)).floor();
        // When not all fit, the last slot becomes the "+N" tile.
        final shown = items.length <= fits ? items.length : fits - 1;
        final hidden = items.length - shown;
        return Row(
          children: [
            for (final item in items.take(shown))
              Padding(
                padding: const EdgeInsets.only(right: _gap),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(item.filePath),
                    width: _size,
                    height: _size,
                    fit: BoxFit.cover,
                    cacheWidth: 160,
                    errorBuilder: (_, _, _) => const SizedBox.square(
                      dimension: _size,
                      child: ColoredBox(
                        color: Colors.white10,
                        child: Icon(Icons.broken_image_outlined, size: 20),
                      ),
                    ),
                  ),
                ),
              ),
            if (hidden > 0)
              SizedBox.square(
                dimension: _size,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: Text('+$hidden')),
                ),
              ),
          ],
        );
      },
    );
  }
}
