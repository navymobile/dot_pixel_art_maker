import 'dart:convert';
import 'dart:typed_data';

class DotCodec {
  static const int _pixelCount = 256;
  static const int _byteSize = 512; // 256 pixels * 2 bytes

  // --- v3 Implementation ---

  // IEEE 802.3 CRC32 (0xEDB88320)
  static int _computeCrc32(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >>> 1) ^ 0xEDB88320;
        } else {
          crc = crc >>> 1;
        }
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  /// Encodes pixels and lineage to v3 payload (Base64URL).
  /// Layout: [Pixel(512)] + [Count(1)] + [Lineage(16*N)] + [CRC(4)]
  static String encodeV3(List<int> argbPixels, List<Uint8List> lineage) {
    // 1. Encode Pixels to RGBA5551 (512 bytes)
    final pixelBytes = Uint8List(_byteSize);
    final byteData = ByteData.sublistView(pixelBytes);

    for (int i = 0; i < _pixelCount; i++) {
      int argb = argbPixels[i];
      int a = (argb >>> 24) & 0xFF;
      int rgba5551;

      if (a == 0) {
        rgba5551 = 0x0000;
      } else {
        int r = (argb >>> 16) & 0xFF;
        int g = (argb >>> 8) & 0xFF;
        int b = argb & 0xFF;
        int r5 = (r >>> 3) & 0x1F;
        int g5 = (g >>> 3) & 0x1F;
        int b5 = (b >>> 3) & 0x1F;
        rgba5551 = (r5 << 11) | (g5 << 6) | (b5 << 1) | 1;
      }
      byteData.setUint16(i * 2, rgba5551, Endian.big);
    }

    // 2. Build Payload Body (Pixels + Lineage Count + Lineage Logs)
    // Cap lineage at 20 (Nmax)
    int count = lineage.length;
    if (count > 20) count = 20;

    final bodyLength = _byteSize + 1 + (count * 16);
    final body = Uint8List(bodyLength);
    int offset = 0;

    // Copy Pixels
    body.setRange(offset, offset + _byteSize, pixelBytes);
    offset += _byteSize;

    // Lineage Count
    body[offset] = count;
    offset += 1;

    // Copy Lineage Entries (16 bytes fixed each)
    for (int i = 0; i < count; i++) {
      final entry = lineage[i];
      if (entry.length == 16) {
        body.setRange(offset, offset + 16, entry);
      } else {
        // Fallback: zero-fill or truncate
        final safeEntry = Uint8List(16);
        final len = entry.length > 16 ? 16 : entry.length;
        safeEntry.setRange(0, len, entry);
        body.setRange(offset, offset + 16, safeEntry);
      }
      offset += 16;
    }

    // 3. Compute CRC32
    final crc = _computeCrc32(body);

    // 4. Append CRC32 (4 bytes Big Endian)
    final totalLength = bodyLength + 4;
    final fullPayload = Uint8List(totalLength);
    fullPayload.setRange(0, bodyLength, body);

    final fullByteData = ByteData.sublistView(fullPayload);
    fullByteData.setUint32(bodyLength, crc, Endian.big);

    // 5. Base64URL Encode (no padding)
    return base64Url.encode(fullPayload).replaceAll('=', '');
  }

  /// Decodes v3 payload to (pixels, lineage).
  static ({List<int> pixels, List<Uint8List> lineage}) decodeV3(String b64url) {
    try {
      // Restore padding
      String padded = b64url;
      while (padded.length % 4 != 0) {
        padded += '=';
      }

      final fullPayload = base64Url.decode(padded);
      final totalLen = fullPayload.lengthInBytes;

      // Min length: 512 (pix) + 1 (cnt) + 4 (crc) = 517
      if (totalLen < 517) {
        throw FormatException('Payload too short: $totalLen');
      }

      // Verify CRC32
      final bodyLen = totalLen - 4;
      final body = fullPayload.sublist(0, bodyLen);
      final storedCrc = ByteData.sublistView(
        fullPayload,
      ).getUint32(bodyLen, Endian.big);
      final computedCrc = _computeCrc32(body);

      if (storedCrc != computedCrc) {
        throw FormatException(
          'CRC mismatch: stored=$storedCrc, computed=$computedCrc',
        );
      }

      // Parse Body
      int offset = 0;

      // 1. Pixels (512 bytes)
      final pixelBytes = body.sublist(offset, offset + 512);
      offset += 512;

      final pixelByteData = ByteData.sublistView(pixelBytes);
      final pixels = List<int>.filled(_pixelCount, 0);

      for (int i = 0; i < _pixelCount; i++) {
        final v16 = pixelByteData.getUint16(i * 2, Endian.big);
        final a1 = v16 & 1;
        if (a1 == 0) {
          pixels[i] = 0x00000000;
        } else {
          final r5 = (v16 >>> 11) & 0x1F;
          final g5 = (v16 >>> 6) & 0x1F;
          final b5 = (v16 >>> 1) & 0x1F;
          final r8 = (r5 << 3) | (r5 >>> 2);
          final g8 = (g5 << 3) | (g5 >>> 2);
          final b8 = (b5 << 3) | (b5 >>> 2);
          pixels[i] = (0xFF << 24) | (r8 << 16) | (g8 << 8) | b8;
        }
      }

      // 2. Lineage Count
      final count = body[offset];
      offset += 1;

      // 3. Lineage Entries
      final lineage = <Uint8List>[];
      for (int i = 0; i < count; i++) {
        // Safety check for loop bounds
        if (offset + 16 > bodyLen) {
          throw FormatException('Lineage data truncated');
        }
        final entry = body.sublist(offset, offset + 16);
        lineage.add(entry);
        offset += 16;
      }

      return (pixels: pixels, lineage: lineage);
    } catch (e) {
      if (e is FormatException) rethrow;
      throw FormatException('Invalid v3 payload: $e');
    }
  }
}
