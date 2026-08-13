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
    fileName: 'ledger_final.zkey',
    url:
        'http://192.168.68.131:8080/circuit_final.zkey',
        // 'https://storage.googleapis.com/bkt-p-zkproof-files-001/plonk/circuit_final.zkey',
    checksum:
        'e18ad3024cda26e5ae7c153702e299a202e3d4b955fce26a45bf4ad76020464a',
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
