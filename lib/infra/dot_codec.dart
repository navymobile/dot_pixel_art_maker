import '../../app_config.dart';
import 'dart:convert';
import 'dart:typed_data';

class DotCodec {
  static const int _pixelCount = AppConfig.dots * AppConfig.dots;
  static const int _byteSize = _pixelCount * 2;

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

      // Min length: _byteSize (pix) + 1 (cnt) + 4 (crc)
      if (totalLen < _byteSize + 5) {
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

      // 1. Pixels (_byteSize bytes)
      final pixelBytes = body.sublist(offset, offset + _byteSize);
      offset += _byteSize;

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

  // --- v4 Implementation ---

  /// Encodes pixels and lineage to v4 payload (Base64URL).
  ///
  /// [Header(4): v=4, e=type, w, h]
  /// Type 1 (RGBA5551): [Pixel(2*w*h)] + [Count(1)] + [Lineage(16*N)] + [CRC(4)]
  /// Type 2 (Indexed8): [Pixel(w*h)] + [Count(1)] + [Lineage(16*N)] + [CRC(4)]
  static String encodeV4(
    List<int> argbPixels,
    List<Uint8List> lineage, {
    required int encodingType, // 1=RGBA5551, 2=Indexed8
  }) {
    // Current dimension from AppConfig
    final int dots = AppConfig.dots;
    final int pixelCount = dots * dots;

    if (argbPixels.length != pixelCount) {
      throw ArgumentError(
        'Pixel count mismatch: expected $pixelCount, got ${argbPixels.length}',
      );
    }

    // 1. Prepare Body Builder
    final bodyBuilder = BytesBuilder(copy: false);

    // 2. Add Header (v=4, e=type, w, h)
    bodyBuilder.addByte(4);
    bodyBuilder.addByte(encodingType);
    bodyBuilder.addByte(dots); // w
    bodyBuilder.addByte(dots); // h

    // 3. Add Pixels
    if (encodingType == 1) {
      // RGBA5551 (2 bytes per pixel)
      for (final argb in argbPixels) {
        bodyBuilder.add(_argbToRgba5551(argb));
      }
    } else if (encodingType == 2) {
      // Indexed8 (1 byte per pixel)
      for (final argb in argbPixels) {
        bodyBuilder.addByte(_argbToIndex8Rgb332(argb));
      }
    } else {
      throw ArgumentError('Unsupported encoding type: $encodingType');
    }

    // 4. Add Lineage Count & Entries
    int count = lineage.length;
    if (count > 255) count = 255; // Max 255
    bodyBuilder.addByte(count);

    for (int i = 0; i < count; i++) {
      final entry = lineage[i];
      if (entry.length == 16) {
        bodyBuilder.add(entry);
      } else {
        // Fallback: truncate or pad
        final safeEntry = Uint8List(16);
        final len = entry.length > 16 ? 16 : entry.length;
        safeEntry.setRange(0, len, entry);
        bodyBuilder.add(safeEntry);
      }
    }

    // 5. Compute CRC32 (Header + Body)
    final body = bodyBuilder.toBytes();
    final crc = _computeCrc32(body);

    // 6. Append CRC32
    final fullBuilder = BytesBuilder(copy: false);
    fullBuilder.add(body);
    final crcBytes = ByteData(4)..setUint32(0, crc, Endian.big);
    fullBuilder.add(crcBytes.buffer.asUint8List());

    // 7. Base64URL Encode (no padding)
    return base64Url.encode(fullBuilder.toBytes()).replaceAll('=', '');
  }

  /// Decodes payload with v4 support (fallback to v3).
  static ({List<int> pixels, List<Uint8List> lineage}) decode(String b64url) {
    try {
      return _decodeV4(b64url);
    } catch (_) {
      // Fallback to legacy v3
      return decodeV3(b64url);
    }
  }

  static ({List<int> pixels, List<Uint8List> lineage}) _decodeV4(
    String b64url,
  ) {
    // 1. Base64 Decode (restore padding)
    String padded = b64url;
    while (padded.length % 4 != 0) {
      padded += '=';
    }
    final fullPayload = base64Url.decode(padded);
    final totalLen = fullPayload.lengthInBytes;

    // Check minimum length for v4
    // Header(4) + Count(1) + CRC(4) = 9 (minimum overhead)
    if (totalLen < 9) {
      throw FormatException('Payload too short for v4');
    }

    // 2. Check Header
    final version = fullPayload[0];
    final encoding = fullPayload[1];
    final width = fullPayload[2];
    final height = fullPayload[3];

    if (version != 4) {
      throw FormatException('Not v4 payload (version=$version)');
    }

    // Calculate expected pixel size
    final int pixelCount = width * height;

    // Check if dimensions match current AppConfig (Optional stricter check, or just allow read)
    // For specific requirement "preview on canvs", we need to make sure we don't crash
    // if we try to load a 16x16 into 21x21 canvas.
    // The DotStorage._toModel logic uses this return. DotModel holds `pixels`.
    // DotEditor checks `initialDot.pixels.length` vs `AppConfig.dots`.
    // So reading it as is (whatever w*h is) is correct for the Codec.

    int pixelDataLen = 0;
    if (encoding == 1) {
      pixelDataLen = pixelCount * 2;
    } else if (encoding == 2) {
      pixelDataLen = pixelCount * 1;
    } else {
      throw FormatException('Unknown encoding: $encoding');
    }

    final minLen = 4 + pixelDataLen + 1 + 4; // Header+Pixels+Count+CRC

    if (totalLen < minLen) {
      throw FormatException(
        'Payload too short for encoding $encoding ($width x $height)',
      );
    }

    // 4. Verify CRC32
    final bodyLen = totalLen - 4;
    final body = fullPayload.sublist(0, bodyLen);
    final storedCrc = ByteData.sublistView(
      fullPayload,
    ).getUint32(bodyLen, Endian.big);
    final computedCrc = _computeCrc32(body);

    if (storedCrc != computedCrc) {
      throw FormatException('CRC mismatch in v4');
    }

    // 5. Parse Pixels
    int offset = 4; // Skip header (v, e, w, h)
    final pixels = List<int>.filled(pixelCount, 0);

    if (encoding == 1) {
      // RGBA5551
      final pixelBytes = body.sublist(offset, offset + pixelDataLen);
      offset += pixelDataLen;
      final byteData = ByteData.sublistView(pixelBytes);

      for (int i = 0; i < pixelCount; i++) {
        final v16 = byteData.getUint16(i * 2, Endian.big);
        pixels[i] = _rgba5551ToArgb(v16);
      }
    } else if (encoding == 2) {
      // Indexed8
      final pixelBytes = body.sublist(offset, offset + pixelDataLen);
      offset += pixelDataLen;

      for (int i = 0; i < pixelCount; i++) {
        final index = pixelBytes[i];
        pixels[i] = _index8Rgb332ToArgb(index);
      }
    }

    // 6. Parse Lineage
    final count = body[offset];
    offset += 1;

    final lineage = <Uint8List>[];
    for (int i = 0; i < count; i++) {
      if (offset + 16 > bodyLen) {
        throw FormatException('Lineage truncated');
      }
      lineage.add(body.sublist(offset, offset + 16));
      offset += 16;
    }

    return (pixels: pixels, lineage: lineage);
  }

  // --- Helpers ---

  static Uint8List _argbToRgba5551(int argb) {
    int a = (argb >>> 24) & 0xFF;
    int v16;
    if (a == 0) {
      v16 = 0x0000;
    } else {
      int r = (argb >>> 16) & 0xFF;
      int g = (argb >>> 8) & 0xFF;
      int b = argb & 0xFF;
      int r5 = (r >>> 3) & 0x1F;
      int g5 = (g >>> 3) & 0x1F;
      int b5 = (b >>> 3) & 0x1F;
      v16 = (r5 << 11) | (g5 << 6) | (b5 << 1) | 1;
    }
    return Uint8List(2)..buffer.asByteData().setUint16(0, v16, Endian.big);
  }

  static int _rgba5551ToArgb(int v16) {
    int a = v16 & 1;
    if (a == 0) return 0x00000000;

    int r5 = (v16 >>> 11) & 0x1F;
    int g5 = (v16 >>> 6) & 0x1F;
    int b5 = (v16 >>> 1) & 0x1F;

    // Bit replication for 5->8 bit
    int r8 = (r5 << 3) | (r5 >>> 2);
    int g8 = (g5 << 3) | (g5 >>> 2);
    int b8 = (b5 << 3) | (b5 >>> 2);

    return (0xFF << 24) | (r8 << 16) | (g8 << 8) | b8;
  }

  static int _argbToIndex8Rgb332(int argb) {
    final a = (argb >>> 24) & 0xFF;
    if (a == 0) return 0;

    final r = (argb >>> 16) & 0xFF;
    final g = (argb >>> 8) & 0xFF;
    final b = argb & 0xFF;

    final r3 = (r * 7 + 127) ~/ 255;
    final g3 = (g * 7 + 127) ~/ 255;
    final b2 = (b * 3 + 127) ~/ 255;

    final v = (r3 << 5) | (g3 << 2) | b2;
    // index 1..255 (clamp max)
    int idx = v + 1;
    if (idx > 255) idx = 255;
    return idx;
  }

  static int _index8Rgb332ToArgb(int index) {
    if (index == 0) return 0x00000000;

    final colorValue = index - 1;
    final r3 = (colorValue >> 5) & 0x07;
    final g3 = (colorValue >> 2) & 0x07;
    final b2 = colorValue & 0x03;

    // Fixed Scaling Logic
    final r8 = (r3 * 255) ~/ 7;
    final g8 = (g3 * 255) ~/ 7;
    final b8 = (b2 * 255) ~/ 3;

    return (0xFF << 24) | (r8 << 16) | (g8 << 8) | b8;
  }

  /// Helper to quantize a list of ARGB pixels to Indexed8 colors (and back to ARGB).
  /// Used for previewing how the image will look when saved as Indexed8.
  static List<int> quantizeToIndexed8(List<int> pixels) {
    return pixels.map((argb) {
      final idx = _argbToIndex8Rgb332(argb);
      return _index8Rgb332ToArgb(idx);
    }).toList();
  }
}
