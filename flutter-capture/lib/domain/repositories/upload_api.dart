import '../entities/upload_batch.dart';
import '../entities/upload_result.dart';

/// The remote upload endpoint.
///
/// Implementations must treat `batch.id` as an idempotency key: if the app is
/// killed after the server stored a batch but before the batch was marked
/// completed, the same batch is sent again and must not be stored twice.
abstract interface class UploadApi {
  /// Uploads all photos of [batch]. Returns [UploadFailed] for expected
  /// failures instead of throwing.
  Future<UploadResult> uploadBatch(UploadBatch batch);
}
