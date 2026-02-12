import 'package:dot_pixel_art_maker/infra/dot_codec.dart';
import '../domain/dot_model.dart';

class QrService {
  // Format: v2|id|gen|base64_pixelData
  // Format: v3|uuid|gen|payload_b64 (Base64URL no padding)
  // Payload: Pixels(512) + Count(1) + Lineage(16*N) + CRC32(4)

  static String encode(DotModel dot) {
    // Encode using v3
    final encodedPayload = DotCodec.encodeV3(dot.pixels, dot.lineage);
    return 'v3|${dot.id}|${dot.gen}|$encodedPayload';
  }

  static DotModel? decode(String qrData) {
    try {
      final parts = qrData.split('|');
      if (parts.length != 4) return null;

      final version = parts[0];
      final id = parts[1];

      // UUID strict validation
      final uuidReg = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      );
      if (!uuidReg.hasMatch(id)) return null;

      final genStr = parts[2];
      final gen = int.tryParse(genStr);
      if (gen == null || gen < 0) return null;

      final payloadStr = parts[3];

      if (version == 'v3') {
        final result = DotCodec.decodeV3(payloadStr);
        return DotModel(
          id: id,
          pixels: result.pixels,
          gen: gen,
          originalId: null,
          lineage: result.lineage,
        );
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
