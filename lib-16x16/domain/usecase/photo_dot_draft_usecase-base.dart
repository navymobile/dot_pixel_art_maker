import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum DraftFilter {
  smooth, // Linear/average interpolation
  crisp, // Nearest neighbor (only for final 16x16 if you want)
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

/// Photo-leaning 16x16 draft generator (NO quantize / NO dither).
/// Main goals:
/// - Keep it as "photo-like as possible" in 16x16
/// - Reduce "pepper noise" / black specks without crushing non-bg areas
///
/// Approach:
/// 1) Decode -> RGBA
/// 2) Gentle color adjust (saturation + user brightness/contrast)
/// 3) Downscale with averaging via intermediate + tiny blur
/// 4) Optional white background matting (only if background is white-ish)
/// 5) Pepper reduction ONLY on background-like bright regions (not on subject)
/// 6) Pack to ARGB32
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
  decoded = decoded.convert(numChannels: 4);

  // --------------------
  // 2) Color tuning (keep photo-like)
  // --------------------
  // Saturation 1.2 tends to push shadows and can amplify specks.
  // Keep it modest for photo-like output.
  decoded = img.adjustColor(decoded, saturation: 1.06);

  final double contrast = 1.0 + (params.contrast / 100.0);
  final double brightness = 1.0 + (params.brightness / 100.0);

  decoded = img.adjustColor(
    decoded,
    contrast: contrast,
    brightness: brightness,
  );

  // --------------------
  // 3) Resize (anti-speckle downscale)
  // --------------------
  // Key: do NOT jump directly to 16x16 with nearest.
  // Use averaging in an intermediate stage to reduce sensor noise,
  // then a tiny blur, then final resize.
  final mid = img.copyResize(
    decoded,
    width: 64,
    height: 64,
    interpolation: img.Interpolation.average,
  );

  // Tiny blur before 16x16 prevents single-pixel pepper from surviving.
  // (Too strong blur ruins faces; keep radius=1)
  final midSoft = img.gaussianBlur(mid, radius: 1);

  final resized = img
      .copyResize(
        midSoft,
        width: 16,
        height: 16,
        interpolation: (params.filter == DraftFilter.crisp)
            ? img.Interpolation.nearest
            : img.Interpolation.average,
      )
      .convert(numChannels: 4);

  // --------------------
  // 4) Background detection + (optional) matting
  // --------------------
  // Only apply matting if the corners are clearly bright (white-ish).
  // Otherwise, do nothing (prevents accidental "white wiping").
  final bg = _estimateBackgroundColor(decoded);
  final bool bgIsWhiteish = _isWhiteish(bg, lumMin: 220);

  img.Image work = resized;
  if (bgIsWhiteish) {
    // Snap near-bg bright pixels to white -> reduces dirty gray pixels that look like specks.
    work = _snapBackgroundToWhite(work, bg, distThreshold: 28, yThreshold: 212);

    // Very high-luminance pixels to pure white.
    work = _forceNearWhiteToWhite(work, lumThreshold: 246);
  }

  // --------------------
  // 5) Pepper reduction (background-like only)
  // --------------------
  // Remove isolated dark pixels ONLY if:
  // - background is white-ish
  // - the pixel sits in a bright neighborhood AND is close to bg color (but dark)
  // - AND it's isolated (far from neighbor average)
  if (bgIsWhiteish) {
    work = _reducePepperNoise(
      work,
      bg: bg,
      darkLumMax: 55,
      brightLumMin: 205,
      brightNeighborMin: 6,
      colorDeltaMin: 26,
      bgDist2Max: 38 * 38,
      replaceWithWhite: true,
    );
  }

  // Ensure RGBA output for getPixel channel access.
  work = work.convert(numChannels: 4);

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
  // Use corners of original (not 16x16) for stable bg estimate.
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

bool _isWhiteish(img.Color c, {required int lumMin}) {
  final r = c.r.toInt();
  final g = c.g.toInt();
  final b = c.b.toInt();
  return _lum8(r, g, b) >= lumMin;
}

img.Image _snapBackgroundToWhite(
  img.Image src,
  img.Color bg, {
  required int distThreshold,
  required int yThreshold,
}) {
  final out = img.Image.from(src);

  final br = bg.r.toInt();
  final bgG = bg.g.toInt();
  final bb = bg.b.toInt();
  final int thr2 = distThreshold * distThreshold;

  for (int y = 0; y < out.height; y++) {
    for (int x = 0; x < out.width; x++) {
      final p = out.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();

      // Bright-only
      final lum = _lum8(r, g, b);
      if (lum < yThreshold) continue;

      // Close-to-background-only
      final dist2 = _dist2Rgb(r, g, b, br, bgG, bb);
      if (dist2 <= thr2) {
        out.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      }
    }
  }
  return out;
}

img.Image _forceNearWhiteToWhite(img.Image src, {required int lumThreshold}) {
  final out = img.Image.from(src);
  for (int y = 0; y < out.height; y++) {
    for (int x = 0; x < out.width; x++) {
      final p = out.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      if (_lum8(r, g, b) >= lumThreshold) {
        out.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      }
    }
  }
  return out;
}

/// Pepper reduction focused on bright/background regions.
/// This is intentionally conservative to avoid touching subject dark details.
img.Image _reducePepperNoise(
  img.Image src, {
  required img.Color bg,
  required int darkLumMax,
  required int brightLumMin,
  required int brightNeighborMin,
  required int colorDeltaMin,
  required int bgDist2Max,
  required bool replaceWithWhite,
}) {
  final out = img.Image.from(src);

  final br = bg.r.toInt();
  final bgG = bg.g.toInt();
  final bb = bg.b.toInt();

  // 8-neighborhood
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

      // Candidate must be dark-ish
      final lum = _lum8(r, g, b);
      if (lum > darkLumMax) continue;

      // Neighbor stats
      int brightCount = 0;
      int sumR = 0, sumG = 0, sumB = 0, n = 0;

      for (final o in offsets) {
        final nx = x + o[0];
        final ny = y + o[1];
        if (nx < 0 || ny < 0 || nx >= out.width || ny >= out.height) continue;

        final np = src.getPixel(nx, ny);
        final nr = np.r.toInt();
        final ng = np.g.toInt();
        final nb = np.b.toInt();
        final nl = _lum8(nr, ng, nb);

        if (nl >= brightLumMin) brightCount++;
        sumR += nr;
        sumG += ng;
        sumB += nb;
        n++;
      }
      if (n == 0) continue;

      // Must be in a bright neighborhood (background-like)
      final bool neighborhoodIsBright = brightCount >= brightNeighborMin;
      if (!neighborhoodIsBright) continue;

      // Must also be close to bg color (prevents touching subject shadows)
      final int d2Bg = _dist2Rgb(r, g, b, br, bgG, bb);
      if (d2Bg > bgDist2Max) continue;

      // Isolation check: far from neighbor average => pepper
      final ar = sumR ~/ n;
      final ag = sumG ~/ n;
      final ab = sumB ~/ n;

      final int d2Avg = _dist2Rgb(r, g, b, ar, ag, ab);
      if (d2Avg < colorDeltaMin * colorDeltaMin) continue;

      // Replace
      if (replaceWithWhite) {
        out.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      } else {
        out.setPixel(x, y, img.ColorRgb8(ar, ag, ab));
      }
    }
  }

  return out;
}
