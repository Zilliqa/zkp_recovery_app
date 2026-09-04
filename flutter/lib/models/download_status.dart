/// Represents the lifecycle state of a single downloadable artifact.
enum DownloadState { notDownloaded, downloading, downloaded, checksum, error }

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
  static const RemoteFileSpec artifact = RemoteFileSpec(
    displayName: 'Circuit Key File',
    fileName: 'groth_final.zkey',
    url:
        'https://storage.googleapis.com/bkt-p-zkproof-files-001/groth16/final.zkey',
    checksum:
        '87191dc220d5cb0111442273a3232267d9029755674da0ee76f4a332b456d97d',
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

enum Wallets { ledger, others, }
