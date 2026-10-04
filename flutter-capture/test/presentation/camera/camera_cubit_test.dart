import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/domain/entities/camera_capabilities.dart';
import 'package:tether_capture/domain/entities/camera_failure.dart';
import 'package:tether_capture/domain/entities/captured_photo.dart';
import 'package:tether_capture/domain/repositories/camera_repository.dart';
import 'package:tether_capture/presentation/camera/cubit/camera_cubit.dart';
import 'package:tether_capture/presentation/camera/cubit/camera_state.dart';

import '../../helpers/fake_camera_repository.dart';

void main() {
  late FakeCameraRepository camera;

  setUp(() => camera = FakeCameraRepository());

  const ready = CameraReady(capabilities: backCamera, zoom: 1);

  group('starting', () {
    blocTest<CameraCubit, CameraState>(
      'opens the back camera straight away when permission is already granted',
      build: () => CameraCubit(camera),
      act: (cubit) => cubit.start(),
      expect: () => [const CameraStarting(), ready],
      verify: (_) => expect(camera.requestCount, 0),
    );

    blocTest<CameraCubit, CameraState>(
      'asks for permission first, then opens once it is granted',
      setUp: () => camera
        ..status = CameraPermission.denied
        ..requestResult = CameraPermission.granted,
      build: () => CameraCubit(camera),
      act: (cubit) => cubit.start(),
      expect: () => [const CameraStarting(), ready],
      verify: (_) => expect(camera.requestCount, 1),
    );

    blocTest<CameraCubit, CameraState>(
      'explains when permission is denied',
      setUp: () => camera
        ..status = CameraPermission.denied
        ..requestResult = CameraPermission.denied,
      build: () => CameraCubit(camera),
      act: (cubit) => cubit.start(),
      expect: () => [const CameraPermissionRequired(permanentlyDenied: false)],
      verify: (_) => expect(camera.openCount, 0),
    );

    blocTest<CameraCubit, CameraState>(
      'points to Settings when Android will no longer ask',
      // Android reports "denied" until a request reveals it won't ask again.
      setUp: () => camera
        ..status = CameraPermission.denied
        ..requestResult = CameraPermission.permanentlyDenied,
      build: () => CameraCubit(camera),
      act: (cubit) => cubit.start(),
      expect: () => [const CameraPermissionRequired(permanentlyDenied: true)],
    );

    blocTest<CameraCubit, CameraState>(
      'reports a device without a back camera',
      setUp: () => camera.openFailure = CameraFailure.noBackCamera,
      build: () => CameraCubit(camera),
      act: (cubit) => cubit.start(),
      expect: () => [
        const CameraStarting(),
        const CameraUnavailable(CameraFailure.noBackCamera),
      ],
    );

    blocTest<CameraCubit, CameraState>(
      'can retry after the camera failed to start',
      setUp: () => camera.openFailure = CameraFailure.initializationFailed,
      build: () => CameraCubit(camera),
      act: (cubit) async {
        await cubit.start();
        camera.openFailure = null;
        await cubit.retry();
      },
      expect: () => [
        const CameraStarting(),
        const CameraUnavailable(CameraFailure.initializationFailed),
        const CameraStarting(),
        ready,
      ],
    );
  });

  group('permission', () {
    blocTest<CameraCubit, CameraState>(
      '"Allow camera" asks again and opens on success',
      setUp: () => camera
        ..status = CameraPermission.denied
        ..requestResult = CameraPermission.granted,
      build: () => CameraCubit(camera),
      seed: () => const CameraPermissionRequired(permanentlyDenied: false),
      act: (cubit) => cubit.requestPermission(),
      expect: () => [const CameraStarting(), ready],
    );

    blocTest<CameraCubit, CameraState>(
      'returning from Settings with permission granted opens the camera',
      build: () => CameraCubit(camera),
      seed: () => const CameraPermissionRequired(permanentlyDenied: true),
      act: (cubit) => cubit.onAppResumed(),
      expect: () => [const CameraStarting(), ready],
    );

    blocTest<CameraCubit, CameraState>(
      'returning from Settings still without permission changes nothing',
      setUp: () => camera.status = CameraPermission.permanentlyDenied,
      build: () => CameraCubit(camera),
      seed: () => const CameraPermissionRequired(permanentlyDenied: true),
      act: (cubit) => cubit.onAppResumed(),
      expect: () => <CameraState>[],
    );

    blocTest<CameraCubit, CameraState>(
      'Open settings is forwarded to the system',
      build: () => CameraCubit(camera),
      act: (cubit) => cubit.openAppSettings(),
      verify: (_) => expect(camera.settingsOpened, isTrue),
    );

    test(
      'the pause and resume caused by the permission dialog itself are ignored',
      () async {
        camera
          ..status = CameraPermission.denied
          ..requestResult = CameraPermission.granted
          ..requestGate = Completer<void>();
        final cubit = CameraCubit(camera);

        final started = cubit.start();
        await Future<void>.delayed(Duration.zero);
        // The dialog takes focus, then the user answers it.
        await cubit.onAppInactive();
        await cubit.onAppResumed();
        camera.requestGate!.complete();
        await started;

        expect(cubit.state, ready);
        expect(camera.openCount, 1);
        expect(camera.closeCount, 0);
        await cubit.close();
      },
    );
  });

  group('lifecycle', () {
    blocTest<CameraCubit, CameraState>(
      'going to the background releases the camera; coming back reopens it',
      build: () => CameraCubit(camera),
      act: (cubit) async {
        await cubit.start();
        await cubit.onAppInactive();
        expect(camera.isOpen, isFalse);
        await cubit.onAppResumed();
      },
      expect: () => [
        const CameraStarting(),
        ready,
        const CameraPaused(),
        const CameraStarting(),
        ready,
      ],
      verify: (_) => expect(camera.openCount, 2),
    );

    blocTest<CameraCubit, CameraState>(
      'zoom is restored after coming back',
      build: () => CameraCubit(camera),
      act: (cubit) async {
        await cubit.start();
        cubit.setZoom(3);
        await cubit.onAppInactive();
        await cubit.onAppResumed();
      },
      skip: 4,
      expect: () => [
        const CameraStarting(),
        const CameraReady(capabilities: backCamera, zoom: 3),
      ],
      verify: (_) => expect(camera.zoomCalls, [3, 3]),
    );

    test('closing the cubit releases the camera', () async {
      final cubit = CameraCubit(camera);
      await cubit.start();

      await cubit.close();

      expect(camera.isOpen, isFalse);
    });
  });

  group('zoom and focus', () {
    blocTest<CameraCubit, CameraState>(
      'zoom is clamped to the camera range and sent to the camera',
      build: () => CameraCubit(camera),
      seed: () => ready,
      act: (cubit) => cubit
        ..setZoom(20)
        ..setZoom(8)
        ..setZoom(0.2),
      expect: () => [
        const CameraReady(capabilities: backCamera, zoom: 8),
        ready,
      ],
      verify: (_) => expect(camera.zoomCalls, [8, 1]),
    );

    blocTest<CameraCubit, CameraState>(
      'zoom is ignored while the camera is not ready',
      build: () => CameraCubit(camera),
      act: (cubit) => cubit.setZoom(2),
      expect: () => <CameraState>[],
      verify: (_) => expect(camera.zoomCalls, isEmpty),
    );

    blocTest<CameraCubit, CameraState>(
      'focus is sent to the camera, clamped to the preview',
      build: () => CameraCubit(camera),
      seed: () => ready,
      act: (cubit) => cubit.focusAt(0.25, 1.4),
      verify: (_) => expect(camera.focusCalls, [(0.25, 1.0)]),
    );

    blocTest<CameraCubit, CameraState>(
      'focus is skipped on a fixed-focus camera',
      build: () => CameraCubit(camera),
      seed: () => const CameraReady(
        capabilities: CameraCapabilities(
          minZoom: 1,
          maxZoom: 4,
          supportsFocusPoint: false,
          previewAspectRatio: 4 / 3,
        ),
        zoom: 1,
      ),
      act: (cubit) => cubit.focusAt(0.5, 0.5),
      verify: (_) => expect(camera.focusCalls, isEmpty),
    );
  });

  group('capture', () {
    final photo = CapturedPhoto(
      path: '/photos/1.jpg',
      capturedAt: DateTime(2026, 10, 4, 12, 1),
    );

    blocTest<CameraCubit, CameraState>(
      'a capture shows progress, then the new photo and count',
      build: () => CameraCubit(camera),
      seed: () => ready,
      act: (cubit) => cubit.capture(),
      expect: () => [
        const CameraReady(capabilities: backCamera, zoom: 1, isCapturing: true),
        CameraReady(
          capabilities: backCamera,
          zoom: 1,
          lastCapture: photo,
          captureCount: 1,
        ),
      ],
    );

    test('a second tap while capturing takes no second photo', () async {
      camera.captureGate = Completer<void>();
      final cubit = CameraCubit(camera);
      await cubit.start();

      final first = cubit.capture();
      final second = cubit.capture();
      camera.captureGate!.complete();
      await Future.wait([first, second]);

      expect(camera.captureCount, 1);
      expect((cubit.state as CameraReady).captureCount, 1);
      await cubit.close();
    });

    blocTest<CameraCubit, CameraState>(
      'a failed capture is reported once, then cleared',
      setUp: () => camera.captureFails = true,
      build: () => CameraCubit(camera),
      seed: () => ready,
      act: (cubit) async {
        await cubit.capture();
        cubit.captureFailureShown();
      },
      expect: () => [
        const CameraReady(capabilities: backCamera, zoom: 1, isCapturing: true),
        const CameraReady(
          capabilities: backCamera,
          zoom: 1,
          captureFailed: true,
        ),
        ready,
      ],
    );

    test('photos and count survive going to the background', () async {
      final cubit = CameraCubit(camera);
      await cubit.start();
      await cubit.capture();

      await cubit.onAppInactive();
      await cubit.onAppResumed();

      final state = cubit.state as CameraReady;
      expect(state.captureCount, 1);
      expect(state.lastCapture, photo);
      await cubit.close();
    });
  });
}
