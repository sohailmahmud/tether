import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/upload_queue_snapshot.dart';
import '../../../domain/repositories/upload_queue_repository.dart';
import 'upload_queue_state.dart';

/// Follows the persistent upload queue and submits the batch being captured.
///
/// Photos are added by the camera; this cubit only reads the queue and
/// decides when a batch is ready to go.
class UploadQueueCubit extends Cubit<UploadQueueState> {
  UploadQueueCubit(this._repository) : super(const UploadQueueState()) {
    _subscription = _repository.watchQueue().listen(
      (queue) => _emit(
        state.copyWith(queue: queue, isLoaded: true, loadFailed: false),
      ),
      onError: (Object _) =>
          _emit(state.copyWith(isLoaded: true, loadFailed: true)),
    );
  }

  final UploadQueueRepository _repository;
  late final StreamSubscription<UploadQueueSnapshot> _subscription;

  /// "Upload batch": sends the draft for upload. Returns true if a batch was
  /// submitted; the queue update arrives through the watched stream.
  Future<bool> submitDraft() async {
    try {
      return await _repository.submitDraft() != null;
    } on UploadQueueException {
      _emit(state.copyWith(submitFailed: true));
      return false;
    }
  }

  /// The submit failure has been shown to the user.
  void submitFailureShown() => _emit(state.copyWith(submitFailed: false));

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }

  void _emit(UploadQueueState next) {
    if (!isClosed) emit(next);
  }
}
