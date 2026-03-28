import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Callback reporting download progress: [received] bytes of [total] bytes.
typedef DownloadProgressCallback = void Function(int received, int total);

/// Thrown when the user cancels a download.
class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => 'Download cancelled by user';
}

/// HTTP file downloader with progress, cancellation, and resume support.
///
/// Each instance manages one concurrent download. Call [cancel] to abort.
class ModelDownloader {
  bool _cancelled = false;
  HttpClient? _client;

  // ─── Static helpers ──────────────────────────────────────────────────

  /// Directory where all model GGUF files are stored.
  static Future<Directory> getModelsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Full path where [filename] would be stored.
  static Future<String> getModelPath(String filename) async {
    final dir = await getModelsDir();
    return '${dir.path}/$filename';
  }

  /// Whether a fully-downloaded model file exists on disk.
  static Future<bool> isDownloaded(String filename) async {
    final path = await getModelPath(filename);
    final file = File(path);
    if (!file.existsSync()) return false;
    // If a .part file also exists, the download was incomplete
    if (File('$path.part').existsSync()) return false;
    return true;
  }

  /// Delete a model file (and any partial download) from disk.
  static Future<void> deleteModel(String filename) async {
    final path = await getModelPath(filename);
    final file = File(path);
    if (file.existsSync()) await file.delete();
    final part = File('$path.part');
    if (part.existsSync()) await part.delete();
  }

  // ─── Download ────────────────────────────────────────────────────────

  /// Download [url] to the models directory as [filename].
  ///
  /// Resumes partial downloads via HTTP Range headers.
  /// When [authToken] is provided, it is sent as a Bearer token in the
  /// Authorization header — required for gated HuggingFace repos.
  /// Returns the final file path on success.
  Future<String> download(
    String url,
    String filename, {
    DownloadProgressCallback? onProgress,
    String? authToken,
  }) async {
    _cancelled = false;

    final dir = await getModelsDir();
    final filePath = '${dir.path}/$filename';
    final tempPath = '$filePath.part';
    final tempFile = File(tempPath);

    _client = HttpClient();

    IOSink? sink;

    try {
      var startByte = 0;
      if (tempFile.existsSync()) {
        startByte = tempFile.lengthSync();
      }

      final request = await _client!.getUrl(Uri.parse(url));
      if (authToken != null && authToken.isNotEmpty) {
        request.headers.add(
          HttpHeaders.authorizationHeader,
          'Bearer $authToken',
        );
      }
      if (startByte > 0) {
        request.headers.add(HttpHeaders.rangeHeader, 'bytes=$startByte-');
      }

      final response = await request.close();

      final statusCode = response.statusCode;
      final isSuccessful =
          statusCode == HttpStatus.partialContent ||
          (statusCode >= HttpStatus.ok &&
              statusCode < HttpStatus.multipleChoices);
      if (!isSuccessful) {
        final errorBody = await response.transform(utf8.decoder).join();
        final reasonPhrase = response.reasonPhrase.trim();
        final message = StringBuffer()
          ..write(
            'Failed to download model: HTTP $statusCode '
                    '$reasonPhrase'
                .trim(),
          );
        if (errorBody.trim().isNotEmpty) {
          message.write(' - ${errorBody.trim()}');
        }
        throw HttpException(message.toString(), uri: Uri.parse(url));
      }

      // Determine total size
      int total;
      if (response.statusCode == HttpStatus.partialContent) {
        // Server accepted the Range request
        total = response.contentLength > 0
            ? startByte + response.contentLength
            : -1;
      } else if (response.contentLength > 0) {
        // Full response — restart from scratch
        startByte = 0;
        total = response.contentLength;
      } else {
        total = -1; // Unknown size
      }

      sink = tempFile.openWrite(
        mode: startByte > 0 && response.statusCode == HttpStatus.partialContent
            ? FileMode.append
            : FileMode.write,
      );

      int received = startByte;

      await for (final chunk in response) {
        if (_cancelled) {
          throw const DownloadCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total > 0 ? total : received);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      // Move temp file to final path
      if (File(filePath).existsSync()) {
        await File(filePath).delete();
      }
      await tempFile.rename(filePath);

      return filePath;
    } on Object {
      if (_cancelled) {
        throw const DownloadCancelledException();
      }
      rethrow;
    } finally {
      if (sink != null) {
        await sink.flush();
        await sink.close();
      }
      _client?.close();
      _client = null;
    }
  }

  /// Cancel the current download.
  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }
}
