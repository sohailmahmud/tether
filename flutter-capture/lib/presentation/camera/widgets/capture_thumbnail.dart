import 'dart:io';

import 'package:flutter/material.dart';

/// The newest photo of the batch being captured, with a badge counting them.
class CaptureThumbnail extends StatelessWidget {
  const CaptureThumbnail({
    super.key,
    required this.imagePath,
    required this.count,
  });

  static const size = 52.0;

  final String? imagePath;
  final int count;

  @override
  Widget build(BuildContext context) {
    final imagePath = this.imagePath;
    return Semantics(
      label: count == 1
          ? '1 photo in this batch'
          : '$count photos in this batch',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imagePath == null
                    ? const DecoratedBox(
                        decoration: BoxDecoration(color: Colors.white10),
                      )
                    : Image.file(
                        File(imagePath),
                        fit: BoxFit.cover,
                        // Decode at thumbnail size, not the photo's full resolution.
                        cacheWidth: 160,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: Colors.white10),
                      ),
              ),
            ),
            if (count > 0)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: const ShapeDecoration(
                    color: Color(0xFF2563EB),
                    shape: StadiumBorder(),
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
