import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum DraftFilter {
  smooth, // Photo-like (average + tiny blur)
  crisp, // Pixel-like (nearest at final)
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

/// No-quantize (NO color reduction), minimal-diff stable pipeline:
/// - Photo-like base via average downscale (+ tiny blur for smooth)
/// - Dot-like feel via final interpolation toggle (Smooth=average / Crisp=nearest)
/// - Black speckle reduction ONLY on bright background-like pixels (very strict)
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
  // 2) Gentle tuning (keep as photo-like as possible)
  // --------------------
  // Saturation bump is optional; keep small to avoid shadow crush.
  decoded = img.adjustColor(decoded, saturation: 1.06);

  final double contrast = 1.0 + (params.contrast / 100.0);
  final double brightness = 1.0 + (params.brightness / 100.0);

  decoded = img.adjustColor(
    decoded,
    contrast: contrast,
    brightness: brightness,
  );

  // Background estimate from original (for later bg-only noise reduction).
  final bg = _estimateBackgroundColor(decoded);
  final bool bgIsWhiteish = _isWhiteish(bg, lumMin: 220);

  // --------------------
  // 3) Downscale
  // --------------------
  // Step 1: average downscale (reduces sensor noise, preserves tones)
  final mid = img.copyResize(
    decoded,
    width: 64,
    height: 64,
    interpolation: img.Interpolation.average,
  );

  // Step 2: tiny blur ONLY for Smooth (prevents pepper + alias)
  // (Too strong blur kills facial features; keep radius=1)
  final midSoft = (params.filter == DraftFilter.smooth)
      ? img.gaussianBlur(mid, radius: 1)
      : mid;

  // Step 3: final 16x16
  img.Image work = img.copyResize(
    midSoft,
    width: 16,
    height: 16,
    interpolation: (params.filter == DraftFilter.crisp)
        ? img.Interpolation.nearest
        : img.Interpolation.average,
  );

  work = work.convert(numChannels: 4);

  // --------------------
  // 4) (Optional) near-white cleanup
  // --------------------
  // Only apply if background is white-ish to avoid accidentally whitening subject.
  if (bgIsWhiteish) {
    work = _forceNearWhiteToWhite(work, lumThreshold: 246);
  }

  // --------------------
  // 5) Black-speckle reduction (bg-only, very strict)
  // --------------------
  // IMPORTANT:
  // - Only when bg is white-ish
  // - Only when the pixel is BOTH:
  //   a) in a very bright neighborhood
  //   b) close to bg color (so we don't touch hair/eyes/shadows)
  if (bgIsWhiteish) {
    work = _reducePepperNoiseBgOnly(
      work,
      bg: bg,
      darkLumMax: 50,
      brightLumMin: 220,
      brightNeighborMin: 7,
      bgDist2Max: 32 * 32,
      replaceWithWhite: true,
    ).convert(numChannels: 4);
  }

  // --------------------
  // 6) Pack to ARGB32 List<int>(256)
  // --------------------
  final pixels = List<int>.filled(256, 0);
  for (int y = 0; y < 16; y++) {
    for (int x = 0; x < 16; x++) {
      final p = work.getPixel(x, y);
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
  // Use corners of original for stable bg estimate.
  final corners = [
    src.getPixel(0, 0),
    src.getPixel(src.width - 1, 0),
    src.getPixel(0, src.height - 1),
    src.getPixel(src.width - 1, src.height - 1),
  ];

  int r = 0, g = 0, b = 0;
  for (final p in corners) {
    r += _to8(p.r);
    g += _to8(p.g);
    b += _to8(p.b);
  }
  return img.ColorRgb8((r ~/ 4), (g ~/ 4), (b ~/ 4));
}

bool _isWhiteish(img.Color c, {required int lumMin}) {
  final r = _to8(c.r);
  final g = _to8(c.g);
  final b = _to8(c.b);
  return _lum8(r, g, b) >= lumMin;
}

img.Image _forceNearWhiteToWhite(img.Image src, {required int lumThreshold}) {
  final out = img.Image.from(src);
  for (int y = 0; y < out.height; y++) {
    for (int x = 0; x < out.width; x++) {
      final p = out.getPixel(x, y);
      final r = _to8(p.r);
      final g = _to8(p.g);
      final b = _to8(p.b);
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

  final br = _to8(bg.r);
  final bgG = _to8(bg.g);
  final bb = _to8(bg.b);

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
      final r = _to8(p.r);
      final g = _to8(p.g);
      final b = _to8(p.b);

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
        final nr = _to8(np.r);
        final ng = _to8(np.g);
        final nb = _to8(np.b);
        final nl = _lum8(nr, ng, nb);
        if (nl >= brightLumMin) brightCount++;
      }
      if (brightCount < brightNeighborMin) continue;

      // replace
      if (replaceWithWhite) {
        out.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      } else {
        // neighbor average (kept for flexibility)
        int sumR = 0, sumG = 0, sumB = 0, n = 0;
        for (final o in offsets) {
          final nx = x + o[0];
          final ny = y + o[1];
          if (nx < 0 || ny < 0 || nx >= out.width || ny >= out.height) continue;
          final np = src.getPixel(nx, ny);
          sumR += _to8(np.r);
          sumG += _to8(np.g);
          sumB += _to8(np.b);
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
