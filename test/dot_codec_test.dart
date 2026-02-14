import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_pixel_art_maker/infra/dot_codec.dart';

void main() {
  group('DotCodec v3', () {
    test('Should encode and decode v3 payload correctly', () {
      final pixels = List<int>.filled(256, 0xFF000000); // All Black
      // 2 lineage entries (16 bytes each)
      final lineage1 = Uint8List(16);
      lineage1[0] = 0xAA;
      final lineage2 = Uint8List(16);
      lineage2[15] = 0xBB;

      final lineage = [lineage1, lineage2];

      final encoded = DotCodec.encodeV3(pixels, lineage);
      final decoded = DotCodec.decodeV3(encoded);

      // Check Pixels: RGBA5551 conversion might slightly alter color if not 5-bit aligned,
      // but 0xFF000000 (Black) is safe.
      // Wait, 0xFF000000 (Black) is A=1, R=0, G=0, B=0.
      // RGBA5551: 0x0001
      // Decode: A=1, R=0, G=0, B=0 -> 0xFF000000. Correct.
      expect(decoded.pixels[0], 0xFF000000);

      // Check Lineage
      expect(decoded.lineage.length, 2);
      expect(decoded.lineage[0][0], 0xAA);
      expect(decoded.lineage[1][15], 0xBB);
    });

    test('Should detect CRC mismatch', () {
      final pixels = List<int>.filled(256, 0); // Transparent (0x0000)
      final encoded = DotCodec.encodeV3(pixels, []);

      // Tamper with the payload
      String padded = encoded;
      while (padded.length % 4 != 0) {
        padded += '=';
      }
      final bytes = base64Url.decode(padded);

      // Flip a bit in the pixel data area (byte 0)
      bytes[0] ^= 0xFF; // Toggle bits

      final tampered = base64Url.encode(bytes).replaceAll('=', '');

      expect(() => DotCodec.decodeV3(tampered), throwsFormatException);
    });

    test('Should handle max lineage validation', () {
      final pixels = List<int>.filled(256, 0);
      // Create 25 entries
      final lineage = List.generate(25, (_) => Uint8List(16));

      final encoded = DotCodec.encodeV3(pixels, lineage);
      final decoded = DotCodec.decodeV3(encoded);

      // Should be capped at 20
      expect(decoded.lineage.length, 20);
    });

    test('Should throw exception for too short payload', () {
      const shortPayload = 'ABCD';
      expect(() => DotCodec.decodeV3(shortPayload), throwsFormatException);
    });
  });
}
