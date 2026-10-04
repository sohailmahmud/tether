import 'dart:math';

final _random = Random.secure();

/// A unique id that sorts by creation time: base-36 microseconds since the
/// epoch, then 32 random bits.
String newId([DateTime Function() clock = DateTime.now]) =>
    '${clock().microsecondsSinceEpoch.toRadixString(36)}-'
    '${_random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0')}';
