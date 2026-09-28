import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hashlib/hashlib.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zkp_recovery_app/models/download_status.dart';

class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  Directory? _cacheDir;

  Future<Directory> getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/proving_artifacts');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  File _fileFor(Directory dir, String fileName) =>
      File('${dir.path}/$fileName');

  File _metaFileFor(Directory dir, String fileName) =>
      File('${dir.path}/$fileName.meta.json');

  Future<String> _computeSha256Hex(
    File file,
    void Function(FileDownloadProgress progress) onProgress,
  ) async {
    onProgress(
      FileDownloadProgress(
        state: DownloadState.checksum,
        fractionComplete: 1.0,
      ),
    );

    final input = sha256.createSink();
    final fileSize = await file.length();

    var progress = 0;
    await for (final chunk in file.openRead()) {
      input.add(chunk);
      progress += chunk.length;
      onProgress(
        FileDownloadProgress(
          state: DownloadState.checksum,
          fractionComplete: progress / fileSize,
        ),
      );
      await Future.delayed(Duration.zero);
    }
    return input.digest().toString();
  }

  bool _hashMatches(String actualHex, String expectedHex) {
    return expectedHex.trim().toLowerCase() == actualHex.trim().toLowerCase();
  }

  Future<void> _purgeCachedFile(Directory dir, String fileName) async {
    final file = _fileFor(dir, fileName);
    final metaFile = _metaFileFor(dir, fileName);
    if (await file.exists()) await file.delete();
    if (await metaFile.exists()) await metaFile.delete();
  }

  Future<bool> existsLocally() async {
    final dir = await getCacheDir();
    final file = _fileFor(dir, ProvingArtifacts.artifact.fileName);
    return (await file.exists()) && (await file.length() > 0);
  }

  Future<void> checkAndDownload(
    void Function(FileDownloadProgress progress) onProgress,
  ) async {
    const spec = ProvingArtifacts.artifact;
    final dir = await getCacheDir();
    final file = _fileFor(dir, spec.fileName);
    final hasLocalCopy = (await file.exists()) && (await file.length() > 0);

    onProgress(FileDownloadProgress(state: DownloadState.downloading));

    try {
      if (hasLocalCopy) {
        final actualHash = await _computeSha256Hex(file, onProgress);
        if (_hashMatches(actualHash, spec.checksum)) {
          onProgress(
            FileDownloadProgress(
              state: DownloadState.downloaded,
              fractionComplete: 1.0,
            ),
          );
          return;
        }

        await _purgeCachedFile(dir, spec.fileName);
      }

      final assetData = await rootBundle.load('assets/${spec.fileName}');
      final bytes = assetData.buffer.asUint8List(
        assetData.offsetInBytes,
        assetData.lengthInBytes,
      );

      final sink = file.openWrite();
      sink.add(bytes);
      await sink.flush();
      await sink.close();

      final actualHash = await _computeSha256Hex(file, onProgress);
      if (!_hashMatches(actualHash, spec.checksum)) {
        await _purgeCachedFile(dir, spec.fileName);
        onProgress(
          FileDownloadProgress(
            state: DownloadState.error,
            errorMessage: 'Checksum verification failed for ${spec.fileName}',
          ),
        );
        return;
      }

      onProgress(
        FileDownloadProgress(
          state: DownloadState.downloaded,
          fractionComplete: 1.0,
        ),
      );
    } catch (e) {
      onProgress(
        FileDownloadProgress(
          state: DownloadState.error,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<bool> verifyArtifact() async {
    final dir = await getCacheDir();
    final File file = _fileFor(dir, ProvingArtifacts.artifact.fileName);

    final input = sha256.createSink();
    await for (final chunk in file.openRead()) {
      input.add(chunk);
      await Future.delayed(Duration.zero);
    }

    final checksum = input.digest().toString();
    return _hashMatches(checksum, ProvingArtifacts.artifact.checksum);
  }

  Future<String> pathFor() async {
    final dir = await getCacheDir();
    return _fileFor(dir, ProvingArtifacts.artifact.fileName).path;
  }
}
