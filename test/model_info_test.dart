import 'package:flutter_test/flutter_test.dart';
import 'package:koshika/models/model_info.dart';

void main() {
  group('ModelInfo.formattedSize', () {
    test('shows MB for values under 1000', () {
      const info = ModelInfo(
        name: 'Test',
        downloadUrl: 'https://example.com/model.task',
        estimatedSizeMB: 500,
      );
      expect(info.formattedSize, '500 MB');
    });

    test('shows GB for values >= 1000', () {
      const info = ModelInfo(
        name: 'Test',
        downloadUrl: 'https://example.com/model.task',
        estimatedSizeMB: 1200,
      );
      expect(info.formattedSize, '1.2 GB');
    });

    test('shows exact GB for round values', () {
      const info = ModelInfo(
        name: 'Test',
        downloadUrl: 'https://example.com/model.task',
        estimatedSizeMB: 3000,
      );
      expect(info.formattedSize, '3.0 GB');
    });
  });

  group('ModelInfo.isUsable', () {
    test('true only when loaded', () {
      for (final status in ModelStatus.values) {
        final info = ModelInfo(
          name: 'Test',
          downloadUrl: 'https://example.com/model.task',
          estimatedSizeMB: 500,
          status: status,
        );
        expect(info.isUsable, status == ModelStatus.loaded);
      }
    });
  });

  group('ModelInfo.canDownload', () {
    test('true for notDownloaded and error', () {
      for (final status in ModelStatus.values) {
        final info = ModelInfo(
          name: 'Test',
          downloadUrl: 'https://example.com/model.task',
          estimatedSizeMB: 500,
          status: status,
        );
        expect(
          info.canDownload,
          status == ModelStatus.notDownloaded || status == ModelStatus.error,
        );
      }
    });
  });

  group('ModelInfo.canLoad', () {
    test('true only when ready', () {
      for (final status in ModelStatus.values) {
        final info = ModelInfo(
          name: 'Test',
          downloadUrl: 'https://example.com/model.task',
          estimatedSizeMB: 500,
          status: status,
        );
        expect(info.canLoad, status == ModelStatus.ready);
      }
    });
  });

  group('ModelInfo.copyWith', () {
    test('preserves unchanged fields', () {
      const original = ModelInfo(
        name: 'Original',
        downloadUrl: 'https://example.com/model.task',
        estimatedSizeMB: 1200,
        status: ModelStatus.notDownloaded,
        downloadProgress: 0,
      );

      final copied = original.copyWith(status: ModelStatus.downloading);

      expect(copied.name, 'Original');
      expect(copied.downloadUrl, 'https://example.com/model.task');
      expect(copied.estimatedSizeMB, 1200);
      expect(copied.status, ModelStatus.downloading);
      expect(copied.downloadProgress, 0);
      expect(copied.errorMessage, isNull);
    });

    test('copyWith(errorMessage: null) clears error', () {
      const original = ModelInfo(
        name: 'Test',
        downloadUrl: 'https://example.com/model.task',
        estimatedSizeMB: 500,
        status: ModelStatus.error,
        errorMessage: 'Something failed',
      );

      final copied = original.copyWith(status: ModelStatus.notDownloaded);

      // errorMessage param defaults to null in copyWith, which clears it
      expect(copied.errorMessage, isNull);
    });

    test('updates multiple fields', () {
      const original = ModelInfo(
        name: 'Test',
        downloadUrl: 'https://example.com/model.task',
        estimatedSizeMB: 500,
      );

      final copied = original.copyWith(
        status: ModelStatus.downloading,
        downloadProgress: 42,
      );

      expect(copied.status, ModelStatus.downloading);
      expect(copied.downloadProgress, 42);
    });
  });
}
