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
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(style: style),
              ],
            ),
            const SizedBox(height: 12),
            _ThumbnailStrip(items: batch.items),
            if (batch.status == UploadStatus.failed && lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                lastError,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
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
          batch.retryCount == 1
              ? 'Failed once · will retry'
              : 'Failed ${batch.retryCount}× · will retry',
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

/// Up to five thumbnails, then "+N" for the rest.
class _ThumbnailStrip extends StatelessWidget {
  const _ThumbnailStrip({required this.items});

  static const _shown = 5;
  static const _size = 52.0;

  final List<UploadItem> items;

  @override
  Widget build(BuildContext context) {
    final hidden = items.length - _shown;
    return Row(
      children: [
        for (final item in items.take(_shown))
          Padding(
            padding: const EdgeInsets.only(right: 6),
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
  }
}
