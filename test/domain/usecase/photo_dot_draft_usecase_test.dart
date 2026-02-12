import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:dot_pixel_art_maker/domain/usecase/photo_dot_draft_usecase.dart';

void main() {
  late PhotoDotDraftUsecase usecase;

  setUp(() {
    usecase = PhotoDotDraftUsecase();
  });

  // Helper to create a simple PNG image bytes (single red pixel)
  Uint8List createRedPixelPng() {
    final image = img.Image(width: 1, height: 1);
    image.setPixelRgb(0, 0, 255, 0, 0); // Red
    return img.encodePng(image);
  }

  group('PhotoDotDraftUsecase', () {
    test('execute returns 256 length pixels', () async {
      final bytes = createRedPixelPng();
      final result = await usecase.execute(
        sourceBytes: bytes,
        params: const DraftGenerationParams(),
      );

      expect(result.length, 256);
      // Since it's resized to 16x16, all pixels should be red (opaque)
      // ARGB: 0xFFFF0000 -> 4294901760 (unsigned) or -65536 (signed)
      // Dart int is 64bit, so 0xFFFF0000 is 4294901760.
      expect(result.first, 0xFFFF0000);
    });

    test('execute applies brightness', () async {
      final bytes = createRedPixelPng();
      // Increase brightness
      final result = await usecase.execute(
        sourceBytes: bytes,
        params: const DraftGenerationParams(brightness: 20),
      );

      // Brightness +20 means +51 (20% of 255) to each channel
      // R: 255 + 51 -> 255 (clamped)
      // G: 0 + 51 -> 51
      // B: 0 + 51 -> 51
      // Expect: 0xFFFF3333 (approx)

      final pixel = result.first;
      final r = (pixel >> 16) & 0xFF;
      final g = (pixel >> 8) & 0xFF;
      final b = pixel & 0xFF;

      expect(r, 255);
      expect(g, greaterThan(0));
      expect(b, greaterThan(0));
    });
  });
}
