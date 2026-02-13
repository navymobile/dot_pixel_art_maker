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

      // v3 lineage count guard (max 20)
      if (count > 20) {
        throw FormatException('v3 lineage count exceeds limit: $count');
      }

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

  // --- v5 Implementation ---

  /// Encodes pixels and lineage to v5 payload (Base64URL).
  ///
  /// [Header(4): v=5, e=type, w, h]
  /// Type 1 (RGBA5551): [Pixel(2*w*h)] + [Count(1)] + [Lineage(16*N)] + [CRC(4)]
  /// Type 2 (Indexed8): [Pixel(w*h)] + [Count(1)] + [Lineage(16*N)] + [CRC(4)]
  /// Type 3 (RGB444): [PackedPixels(ceil(w*h*12/8))] + [Count(1)] + [Lineage(16*N)] + [CRC(4)]
  static String encodeV5(
    List<int> argbPixels,
    List<Uint8List> lineage, {
    required int encodingType, // 1=RGBA5551, 2=Indexed8, 3=RGB444
  }) {
    final int dots = AppConfig.dots;
    final int pixelCount = dots * dots;

    if (argbPixels.length != pixelCount) {
      throw ArgumentError(
        'Pixel count mismatch: expected $pixelCount, got ${argbPixels.length}',
      );
    }

    // 1. Prepare Body Builder
    final bodyBuilder = BytesBuilder(copy: false);

    // 2. Add Header (v=5, e=type, w, h)
    bodyBuilder.addByte(5);
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
    } else if (encodingType == 3) {
      // RGB444 (12bit packed)
      final rgb12values = argbPixels.map(_argbToRgb444).toList();
      bodyBuilder.add(_packRgb444(rgb12values));
    } else {
      throw ArgumentError('Unsupported encoding type: $encodingType');
    }

    // 4. Add Lineage Count & Entries
    int count = lineage.length;
    if (count > 255) count = 255;
    bodyBuilder.addByte(count);

    for (int i = 0; i < count; i++) {
      final entry = lineage[i];
      if (entry.length == 16) {
        bodyBuilder.add(entry);
      } else {
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

  /// Decodes payload with v5/v4/v3 support.
  ///
  /// Strategy:
  /// - v==5 → _decodeV5 (CRC mismatch on valid structure = FormatException, NO fallback)
  /// - v==4 → _decodeV4 (CRC mismatch on valid structure = FormatException, NO fallback)
  /// - else → decodeV3 (legacy, count>20 = FormatException)
  static ({List<int> pixels, List<Uint8List> lineage}) decode(String b64url) {
    // Base64 decode once
    String padded = b64url;
    while (padded.length % 4 != 0) {
      padded += '=';
    }

    Uint8List fullPayload;
    try {
      fullPayload = base64Url.decode(padded);
    } catch (e) {
      throw FormatException('Invalid Base64URL: $e');
    }

    final totalLen = fullPayload.lengthInBytes;
    if (totalLen < 5) {
      throw FormatException('Payload too short: $totalLen');
    }

    final version = fullPayload[0];

    if (version == 5) {
      return _decodeV5(fullPayload);
    } else if (version == 4) {
      return _decodeV4FromBytes(fullPayload);
    } else {
      // Fallback to v3 (headerless)
      return decodeV3(b64url);
    }
  }

  static ({List<int> pixels, List<Uint8List> lineage}) _decodeV5(
    Uint8List fullPayload,
  ) {
    final totalLen = fullPayload.lengthInBytes;

    // Min: Header(4) + Count(1) + CRC(4) = 9
    if (totalLen < 9) {
      throw FormatException('v5 payload too short');
    }

    final version = fullPayload[0];
    final encoding = fullPayload[1];
    final width = fullPayload[2];
    final height = fullPayload[3];

    if (version != 5) {
      throw FormatException('Not v5 payload (version=$version)');
    }

    final int pixelCount = width * height;

    // Calculate pixel data length based on encoding
    int pixelDataLen;
    if (encoding == 1) {
      pixelDataLen = pixelCount * 2;
    } else if (encoding == 2) {
      pixelDataLen = pixelCount;
    } else if (encoding == 3) {
      pixelDataLen = (pixelCount * 12 + 7) ~/ 8;
    } else {
      throw FormatException('Unknown v5 encoding: $encoding');
    }

    final minLen = 4 + pixelDataLen + 1 + 4;
    if (totalLen < minLen) {
      throw FormatException(
        'v5 payload too short for encoding $encoding ($width x $height)',
      );
    }

    // Verify CRC32 — mismatch = data corruption, NO fallback
    final bodyLen = totalLen - 4;
    final body = fullPayload.sublist(0, bodyLen);
    final storedCrc = ByteData.sublistView(
      fullPayload,
    ).getUint32(bodyLen, Endian.big);
    final computedCrc = _computeCrc32(body);

    if (storedCrc != computedCrc) {
      throw FormatException('CRC mismatch in v5 (data corruption)');
    }

    // Parse Pixels
    int offset = 4;
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
        pixels[i] = _index8Rgb332ToArgb(pixelBytes[i]);
      }
    } else if (encoding == 3) {
      // RGB444
      final packedBytes = Uint8List.fromList(
        body.sublist(offset, offset + pixelDataLen),
      );
      offset += pixelDataLen;
      final rgb12values = _unpackRgb444(packedBytes, pixelCount);
      for (int i = 0; i < pixelCount; i++) {
        pixels[i] = _rgb444ToArgb(rgb12values[i]);
      }
    }

    // Parse Lineage
    final count = body[offset];
    offset += 1;

    final lineage = <Uint8List>[];
    for (int i = 0; i < count; i++) {
      if (offset + 16 > bodyLen) {
        throw FormatException('v5 lineage truncated');
      }
      lineage.add(body.sublist(offset, offset + 16));
      offset += 16;
    }

    return (pixels: pixels, lineage: lineage);
  }

  /// v4 decoder that accepts pre-decoded bytes (used by the unified decode method).
  static ({List<int> pixels, List<Uint8List> lineage}) _decodeV4FromBytes(
    Uint8List fullPayload,
  ) {
    final totalLen = fullPayload.lengthInBytes;

    if (totalLen < 9) {
      throw FormatException('v4 payload too short');
    }

    final version = fullPayload[0];
    final encoding = fullPayload[1];
    final width = fullPayload[2];
    final height = fullPayload[3];

    if (version != 4) {
      throw FormatException('Not v4 payload (version=$version)');
    }

    final int pixelCount = width * height;

    int pixelDataLen;
    if (encoding == 1) {
      pixelDataLen = pixelCount * 2;
    } else if (encoding == 2) {
      pixelDataLen = pixelCount;
    } else {
      throw FormatException('Unknown v4 encoding: $encoding');
    }

    final minLen = 4 + pixelDataLen + 1 + 4;
    if (totalLen < minLen) {
      throw FormatException(
        'v4 payload too short for encoding $encoding ($width x $height)',
      );
    }

    // CRC mismatch = data corruption, NO fallback
    final bodyLen = totalLen - 4;
    final body = fullPayload.sublist(0, bodyLen);
    final storedCrc = ByteData.sublistView(
      fullPayload,
    ).getUint32(bodyLen, Endian.big);
    final computedCrc = _computeCrc32(body);

    if (storedCrc != computedCrc) {
      throw FormatException('CRC mismatch in v4 (data corruption)');
    }

    int offset = 4;
    final pixels = List<int>.filled(pixelCount, 0);

    if (encoding == 1) {
      final pixelBytes = body.sublist(offset, offset + pixelDataLen);
      offset += pixelDataLen;
      final byteData = ByteData.sublistView(pixelBytes);
      for (int i = 0; i < pixelCount; i++) {
        final v16 = byteData.getUint16(i * 2, Endian.big);
        pixels[i] = _rgba5551ToArgb(v16);
      }
    } else if (encoding == 2) {
      final pixelBytes = body.sublist(offset, offset + pixelDataLen);
      offset += pixelDataLen;
      for (int i = 0; i < pixelCount; i++) {
        pixels[i] = _index8Rgb332ToArgb(pixelBytes[i]);
      }
    }

    final count = body[offset];
    offset += 1;

    final lineage = <Uint8List>[];
    for (int i = 0; i < count; i++) {
      if (offset + 16 > bodyLen) {
        throw FormatException('v4 lineage truncated');
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

  // --- RGB444 Helpers ---

  /// ARGB32 → RGB444 (12bit). 0x000 = transparent.
  static int _argbToRgb444(int argb) {
    final a = (argb >>> 24) & 0xFF;
    if (a == 0) return 0x000;

    final r = (argb >>> 16) & 0xFF;
    final g = (argb >>> 8) & 0xFF;
    final b = argb & 0xFF;

    final r4 = (r * 15 + 127) ~/ 255;
    final g4 = (g * 15 + 127) ~/ 255;
    final b4 = (b * 15 + 127) ~/ 255;

    int rgb12 = (r4 << 8) | (g4 << 4) | b4;
    // 0x000 is reserved for transparent → substitute with 0x001
    if (rgb12 == 0x000) rgb12 = 0x001;
    return rgb12;
  }

  /// RGB444 (12bit) → ARGB32. 0x000 = transparent.
  static int _rgb444ToArgb(int rgb12) {
    if (rgb12 == 0x000) return 0x00000000;

    final r4 = (rgb12 >> 8) & 0x0F;
    final g4 = (rgb12 >> 4) & 0x0F;
    final b4 = rgb12 & 0x0F;

    final r8 = (r4 * 255 + 7) ~/ 15;
    final g8 = (g4 * 255 + 7) ~/ 15;
    final b8 = (b4 * 255 + 7) ~/ 15;

    return (0xFF << 24) | (r8 << 16) | (g8 << 8) | b8;
  }

  /// Pack a list of 12-bit values into MSB-first byte stream.
  /// 2 pixels = 3 bytes. If odd pixel count, last nibble is zero-padded.
  static Uint8List _packRgb444(List<int> rgb12values) {
    final pixelCount = rgb12values.length;
    final byteLen = (pixelCount * 12 + 7) ~/ 8; // ceil(pixelCount * 12 / 8)
    final result = Uint8List(byteLen);

    int bitOffset = 0;
    for (final v12 in rgb12values) {
      // Write 12 bits MSB-first
      final byteIdx = bitOffset ~/ 8;
      final bitPos = bitOffset % 8;

      if (bitPos == 0) {
        // Aligned: v12 starts at bit 0 of byteIdx
        // byte[n] = top 8 bits, byte[n+1] top nibble = bottom 4 bits
        result[byteIdx] = (v12 >> 4) & 0xFF;
        if (byteIdx + 1 < byteLen) {
          result[byteIdx + 1] = ((v12 & 0x0F) << 4);
        }
      } else {
        // bitPos == 4: v12 starts at bit 4 of byteIdx
        // byte[n] bottom nibble = top 4 bits, byte[n+1] = bottom 8 bits
        result[byteIdx] = (result[byteIdx] & 0xF0) | ((v12 >> 8) & 0x0F);
        if (byteIdx + 1 < byteLen) {
          result[byteIdx + 1] = v12 & 0xFF;
        }
      }
      bitOffset += 12;
    }
    return result;
  }

  /// Unpack MSB-first packed 12-bit values.
  static List<int> _unpackRgb444(Uint8List packed, int pixelCount) {
    final result = List<int>.filled(pixelCount, 0);

    int bitOffset = 0;
    for (int i = 0; i < pixelCount; i++) {
      final byteIdx = bitOffset ~/ 8;
      final bitPos = bitOffset % 8;

      int v12;
      if (bitPos == 0) {
        // Aligned: read top 8 bits from byte[n], top 4 bits from byte[n+1]
        v12 =
            (packed[byteIdx] << 4) |
            ((byteIdx + 1 < packed.length ? packed[byteIdx + 1] : 0) >> 4);
      } else {
        // bitPos == 4: read bottom 4 bits from byte[n], all 8 bits from byte[n+1]
        v12 =
            ((packed[byteIdx] & 0x0F) << 8) |
            (byteIdx + 1 < packed.length ? packed[byteIdx + 1] : 0);
      }
      result[i] = v12 & 0xFFF;
      bitOffset += 12;
    }
    return result;
  }

  /// Helper to quantize ARGB pixels to RGB444 colors (and back to ARGB).
  /// Used for previewing how the image will look when saved as RGB444.
  static List<int> quantizeToRgb444(List<int> pixels) {
    return pixels.map((argb) {
      final rgb12 = _argbToRgb444(argb);
      return _rgb444ToArgb(rgb12);
    }).toList();
  }
}
