import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum DraftFilter {
  smooth, // Photo-like (average + tiny blur)
  crisp, // Pixel-like (nearest)
}

class DraftGenerationParams {
  final DraftFilter filter;
  final int brightness; // -20 to +20
  final int contrast; // -20 to +20

  const DraftGenerationParams({
    this.filter = DraftFilter.smooth,
    this.brightness = 0,
    this.contrast = 0,
  });
}

class PhotoDotDraftUsecase {
  /// Executes the generation pipeline in a background isolate.
  Future<List<int>> execute({
    required Uint8List sourceBytes,
    required DraftGenerationParams params,
  }) async {
    return await compute(_generate, _GenerationArgs(sourceBytes, params));
  }
}

class _GenerationArgs {
  final Uint8List bytes;
  final DraftGenerationParams params;
  _GenerationArgs(this.bytes, this.params);
}

/// Minimal-diff, stable pipeline:
/// - Keep photo-like by default (Smooth)
/// - Still "dot-like" via palette quantization (no dither, higher colors for Smooth)
/// - Reduce black speckles safely:
///   1) tiny pre-blur only for Smooth
///   2) near-white -> white before quantize
///   3) very restricted pepper removal (only on bright background & bg-like pixels)
List<int> _generate(_GenerationArgs args) {
  final bytes = args.bytes;
  final params = args.params;

  // --------------------
  // 1) Decode
  // --------------------
  img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('Failed to decode image');
  }

  // Normalize to RGBA to avoid indexed/paletted surprises.
  decoded = decoded.convert(numChannels: 4);

  // --------------------
  // 1.2) Gentle tuning
  // --------------------
  // Keep small; large saturation/contrast tends to create pepper/noise in 16x16.
  decoded = img.adjustColor(decoded, saturation: 1.03);

  final double contrast = 1.0 + (params.contrast / 100.0);
  final double brightness = 1.0 + (params.brightness / 100.0);

  decoded = img.adjustColor(
    decoded,
    contrast: contrast,
    brightness: brightness,
  );

  // Background estimate from original (for later pepper logic).
  final bg = _estimateBackgroundColor(decoded);

  // --------------------
  // 2) Downscale (photo-like)
  // --------------------
  // Step 1: average downscale (reduces sensor noise, preserves tones)
  final mid = img.copyResize(
    decoded,
    width: 64,
    height: 64,
    interpolation: img.Interpolation.average,
  );

  // Step 2: tiny blur ONLY for Smooth (prevents pepper + alias)
  final midSoft = (params.filter == DraftFilter.smooth)
      ? img.gaussianBlur(mid, radius: 1)
      : mid;

  // Step 3: final 16x16
  final resized = img.copyResize(
    midSoft,
    width: 16,
    height: 16,
    interpolation: (params.filter == DraftFilter.crisp)
        ? img.Interpolation.nearest
        : img.Interpolation.average,
  );

  // --------------------
  // 2.5) Near-white cleanup (pre-quantize)
  // --------------------
  // This is the single safest anti-speckle step for white studio backgrounds.
  final cleaned = _forceNearWhiteToWhite(resized, lumThreshold: 246);

  // --------------------
  // 3) Quantize (dot-like, but photo-leaning)
  // --------------------
  // - Smooth: higher colors (photo-ish, less crush)
  // - Crisp: fewer colors (more dot-ish)
  final int colors = (params.filter == DraftFilter.smooth) ? 48 : 32;

  final quantized = img.quantize(
    cleaned,
    numberOfColors: colors,
    method: img.QuantizeMethod.octree,
    dither: img.DitherKernel.none, // IMPORTANT: avoid sandstorm in 16x16
  );

  final qRgba = quantized.convert(numChannels: 4);

  // --------------------
  // 3.5) Pepper reduction (very restricted)
  // --------------------
  // Only remove "dark single pixels" that sit in bright background AND are bg-like.
  final pepperReduced = _reducePepperNoiseBgOnly(
    qRgba,
    bg: bg,
    // “dark dot” threshold
    darkLumMax: 48,
    // neighborhood must be very bright
    brightLumMin: 220,
    // require many bright neighbors (8-neighborhood)
    brightNeighborMin: 7,
    // pixel must be close to estimated background color
    bgDist2Max: 32 * 32,
    // replace with pure white (stable for bg)
    replaceWithWhite: true,
  );

  // --------------------
  // 4) Pack to ARGB32 List<int>(256)
  // --------------------
  final pixels = List<int>.filled(256, 0);
  for (int y = 0; y < 16; y++) {
    for (int x = 0; x < 16; x++) {
      final p = pepperReduced.getPixel(x, y);
      final r = _to8(p.r);
      final g = _to8(p.g);
      final b = _to8(p.b);
      pixels[y * 16 + x] = (0xFF << 24) | (r << 16) | (g << 8) | b;
    }
  }

  return pixels;
}

// --------------------
// Helpers
// --------------------

int _to8(num v) {
  // image package may return 0..1 or 0..255 depending on internal color type
  if (v <= 1.0) return (v * 255).round().clamp(0, 255);
  return v.round().clamp(0, 255);
}

int _lum8(int r, int g, int b) {
  return (0.2126 * r + 0.7152 * g + 0.0722 * b).round().clamp(0, 255);
}

int _dist2Rgb(int r1, int g1, int b1, int r2, int g2, int b2) {
  final dr = r1 - r2;
  final dg = g1 - g2;
  final db = b1 - b2;
  return dr * dr + dg * dg + db * db;
}

img.Color _estimateBackgroundColor(img.Image src) {
  final corners = [
    src.getPixel(0, 0),
    src.getPixel(src.width - 1, 0),
    src.getPixel(0, src.height - 1),
    src.getPixel(src.width - 1, src.height - 1),
  ];
  int r = 0, g = 0, b = 0;
  for (final p in corners) {
    r += p.r.toInt();
    g += p.g.toInt();
    b += p.b.toInt();
  }
  return img.ColorRgb8((r ~/ 4), (g ~/ 4), (b ~/ 4));
}

img.Image _forceNearWhiteToWhite(img.Image src, {required int lumThreshold}) {
  final out = img.Image.from(src);
  for (int y = 0; y < out.height; y++) {
    for (int x = 0; x < out.width; x++) {
      final p = out.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final lum = _lum8(r, g, b);
      if (lum >= lumThreshold) {
        out.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      }
    }
  }
  return out;
}

/// Pepper reduction that is *only* allowed on bright background-like regions.
/// This avoids “non-background black crush” on hair/eyes/shadows.
img.Image _reducePepperNoiseBgOnly(
  img.Image src, {
  required img.Color bg,
  required int darkLumMax,
  required int brightLumMin,
  required int brightNeighborMin,
  required int bgDist2Max,
  required bool replaceWithWhite,
}) {
  final out = img.Image.from(src);

  final br = bg.r.toInt();
  final bgG = bg.g.toInt();
  final bb = bg.b.toInt();

  const offsets = [
    [-1, -1],
    [0, -1],
    [1, -1],
    [-1, 0],
    [1, 0],
    [-1, 1],
    [0, 1],
    [1, 1],
  ];

  for (int y = 0; y < out.height; y++) {
    for (int x = 0; x < out.width; x++) {
      final p = src.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();

      // candidate must be dark
      final lum = _lum8(r, g, b);
      if (lum > darkLumMax) continue;

      // must be close to background color (prevents killing real dark details)
      final d2Bg = _dist2Rgb(r, g, b, br, bgG, bb);
      if (d2Bg > bgDist2Max) continue;

      // neighborhood must be very bright
      int brightCount = 0;
      for (final o in offsets) {
        final nx = x + o[0];
        final ny = y + o[1];
        if (nx < 0 || ny < 0 || nx >= out.width || ny >= out.height) continue;
        final np = src.getPixel(nx, ny);
        final nl = _lum8(np.r.toInt(), np.g.toInt(), np.b.toInt());
        if (nl >= brightLumMin) brightCount++;
      }
      if (brightCount < brightNeighborMin) continue;

      // replace
      if (replaceWithWhite) {
        out.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      } else {
        // neighbor average (not used by default, but kept for flexibility)
        int sumR = 0, sumG = 0, sumB = 0, n = 0;
        for (final o in offsets) {
          final nx = x + o[0];
          final ny = y + o[1];
          if (nx < 0 || ny < 0 || nx >= out.width || ny >= out.height) continue;
          final np = src.getPixel(nx, ny);
          sumR += np.r.toInt();
          sumG += np.g.toInt();
          sumB += np.b.toInt();
          n++;
        }
        if (n > 0) {
          out.setPixel(x, y, img.ColorRgb8(sumR ~/ n, sumG ~/ n, sumB ~/ n));
        }
      }
    }
  }

  return out;
}
