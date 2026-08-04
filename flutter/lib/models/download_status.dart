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
class ProvingArtifacts {
  static const String _bucketBase = 'http://192.168.68.130:8080';

  static const RemoteFileSpec artifact = RemoteFileSpec(
    displayName: 'Circuit Key File',
    fileName: 'ledger_final.zkey',
    url: '$_bucketBase/ledger_final.zkey',
    checksum: 'ec96c7bc927eb6babe1e6d52b62702a1bd3203ae3d71d6eceb6f972577c050ee',
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
