import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/download_status.dart';

class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  Directory? _cacheDir;

  Future<Directory> _getCacheDir() async {
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

  Future<Map<String, String>?> _readMeta(Directory dir, String fileName) async {
    final metaFile = _metaFileFor(dir, fileName);
    if (!await metaFile.exists()) return null;
    try {
      final raw = await metaFile.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeMeta(
    Directory dir,
    String fileName, {
    String? etag,
    String? lastModified,
  }) async {
    final metaFile = _metaFileFor(dir, fileName);
    await metaFile.writeAsString(
      jsonEncode({'etag': etag, 'lastModified': lastModified}),
    );
  }

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

    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
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
    input.close();
    return output.events.single.toString();
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
    final dir = await _getCacheDir();
    final file = _fileFor(dir, ProvingArtifacts.artifact.fileName);
    return (await file.exists()) && (await file.length() > 0);
  }

  Future<void> checkAndDownload(
    void Function(FileDownloadProgress progress) onProgress,
  ) async {
    const spec = ProvingArtifacts.artifact;
    final dir = await _getCacheDir();
    final file = _fileFor(dir, spec.fileName);
    final meta = await _readMeta(dir, spec.fileName);
    final hasLocalCopy = (await file.exists()) && (await file.length() > 0);

    onProgress(FileDownloadProgress(state: DownloadState.downloading));

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(spec.url));

      if (hasLocalCopy && meta != null) {
        final etag = meta['etag'];
        final lastModified = meta['lastModified'];
        if (etag != null) request.headers['If-None-Match'] = etag;
        if (lastModified != null) {
          request.headers['If-Modified-Since'] = lastModified;
        }
      }

      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode == 304) {
        await streamedResponse.stream.drain();
        client.close();

        final actualHash = await _computeSha256Hex(file, onProgress);
        if (!_hashMatches(actualHash, spec.checksum)) {
          await _purgeCachedFile(dir, spec.fileName);
          onProgress(
            FileDownloadProgress(
              state: DownloadState.error,
              errorMessage:
                  'Checksum verification failed for cached ${spec.fileName}',
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
        return;
      }

      if (streamedResponse.statusCode != 200) {
        await streamedResponse.stream.drain();
        client.close();
        onProgress(
          FileDownloadProgress(
            state: DownloadState.error,
            errorMessage: 'HTTP ${streamedResponse.statusCode}',
          ),
        );
        return;
      }

      final total = streamedResponse.contentLength;
      final sink = file.openWrite();
      int received = 0;

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(
          FileDownloadProgress(
            state: DownloadState.downloading,
            fractionComplete: total != null && total > 0
                ? received / total
                : null,
          ),
        );
        await Future.delayed(Duration.zero);
      }
      await sink.flush();
      await sink.close();
      client.close();

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

      final newEtag = streamedResponse.headers['etag'];
      final newLastModified = streamedResponse.headers['last-modified'];
      await _writeMeta(
        dir,
        spec.fileName,
        etag: newEtag,
        lastModified: newLastModified,
      );

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

  Future<String> pathFor() async {
    final dir = await _getCacheDir();
    return _fileFor(dir, ProvingArtifacts.artifact.fileName).path;
  }
}
