/// Represents the lifecycle state of a single downloadable artifact.
enum DownloadState {
  notDownloaded,
  downloading,
  downloaded,
  checksum,
  error,
}

/// Describes a remote file that needs to be cached locally before the
/// Groth16 proof can be generated.
class RemoteFileSpec {
  final String displayName;
  final String fileName;
  final String url;
  final String checksum;

  const RemoteFileSpec({
    required this.displayName,
    required this.fileName,
    required this.url,
    required this.checksum,
  });
}

/// Hardcoded GCS public bucket locations for the proving artifacts.
/// 
/// TODO: Replace with pinned values.
/// Use a semver naming convention for the file e.g. ledger_26.8.7.zkey
class ProvingArtifacts {
  static const String _bucketBase = 'https://storage.googleapis.com/bkt-p-zkproof-files-001';

  static const RemoteFileSpec artifact = RemoteFileSpec(
    displayName: 'Circuit Key File',
    fileName: 'ledger_final.zkey',
    url: '$_bucketBase/groth16/circuit_final.zkey',
    checksum: 'dc48de69b283cebdf2ca258c29a70e0480f398481f70c24437a4cabda82ce4d8',
  );
}

/// Mutable progress/status record tracked per file while downloading.
class FileDownloadProgress {
  DownloadState state;
  double? fractionComplete;
  String? errorMessage;

  FileDownloadProgress({
    this.state = DownloadState.notDownloaded,
    this.fractionComplete,
    this.errorMessage,
  });
}
