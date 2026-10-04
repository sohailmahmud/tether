/// Where a batch or photo is in the upload process.
enum UploadStatus {
  /// A batch the user is still adding photos to. Never uploaded; batches only.
  draft,

  /// Submitted and waiting for an upload attempt.
  pending,

  /// An upload attempt is in progress.
  uploading,

  /// The last attempt failed; it will be retried. Files are kept.
  failed,

  /// The server has confirmed the upload.
  completed,
}
