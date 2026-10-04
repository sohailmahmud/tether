import 'package:equatable/equatable.dart';

/// A photo taken by the camera, stored as a file on the device.
class CapturedPhoto extends Equatable {
  const CapturedPhoto({required this.path, required this.capturedAt});

  final String path;
  final DateTime capturedAt;

  @override
  List<Object> get props => [path, capturedAt];
}
