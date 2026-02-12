import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../domain/usecase/photo_dot_draft_usecase.dart';

class ImportPhotoSheet extends StatefulWidget {
  final Uint8List sourceBytes;
  final Function(List<int>) onApply;

  const ImportPhotoSheet({
    super.key,
    required this.sourceBytes,
    required this.onApply,
  });

  @override
  State<ImportPhotoSheet> createState() => _ImportPhotoSheetState();
}

class _ImportPhotoSheetState extends State<ImportPhotoSheet> {
  final _usecase = PhotoDotDraftUsecase();

  DraftFilter _filter = DraftFilter.smooth;
  double _brightness = 0; // -20 to 20
  double _contrast = 0; // -20 to 20

  List<int>? _previewPixels;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _generatePreview();
  }

  Future<void> _generatePreview() async {
    if (_isGenerating) return;
    setState(() {
      _isGenerating = true;
    });

    final params = DraftGenerationParams(
      filter: _filter,
      brightness: _brightness.round(),
      contrast: _contrast.round(),
    );

    try {
      final pixels = await _usecase.execute(
        sourceBytes: widget.sourceBytes,
        params: params,
      );
      if (mounted) {
        setState(() {
          _previewPixels = pixels;
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error generating preview: $e')));
      }
    }
  }

  void _onApply() {
    if (_previewPixels != null) {
      widget.onApply(_previewPixels!);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: 600, // Fixed height for sheet
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Import Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Preview Area
          Expanded(
            flex: 2,
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                  ),
                  child: _isGenerating && _previewPixels == null
                      ? const Center(child: CircularProgressIndicator())
                      : _PreviewGrid(pixels: _previewPixels),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Controls
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Filter Toggle
                  SegmentedButton<DraftFilter>(
                    segments: const [
                      ButtonSegment(
                        value: DraftFilter.smooth,
                        label: Text('Smooth'),
                      ),
                      ButtonSegment(
                        value: DraftFilter.crisp,
                        label: Text('Crisp'),
                      ),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (Set<DraftFilter> newSelection) {
                      setState(() {
                        _filter = newSelection.first;
                      });
                      _generatePreview();
                    },
                  ),
                  const SizedBox(height: 16),

                  // Brightness
                  Text('Brightness: ${_brightness.round()}'),
                  Slider(
                    value: _brightness,
                    min: -20,
                    max: 20,
                    divisions: 40,
                    label: _brightness.round().toString(),
                    onChanged: (value) {
                      setState(() => _brightness = value);
                    },
                    onChangeEnd: (_) => _generatePreview(),
                  ),

                  // Contrast
                  Text('Contrast: ${_contrast.round()}'),
                  Slider(
                    value: _contrast,
                    min: -20,
                    max: 20,
                    divisions: 40,
                    label: _contrast.round().toString(),
                    onChanged: (value) {
                      setState(() => _contrast = value);
                    },
                    onChangeEnd: (_) => _generatePreview(),
                  ),
                ],
              ),
            ),
          ),

          // Apply Button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _onApply,
              icon: const Icon(Icons.check),
              label: const Text('APPLY to Canvas'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewGrid extends StatelessWidget {
  final List<int>? pixels;

  const _PreviewGrid({this.pixels});

  @override
  Widget build(BuildContext context) {
    if (pixels == null) return const SizedBox();

    return LayoutBuilder(
      builder: (context, constraints) {
        final pixelSize = constraints.maxWidth / 16;
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxWidth),
          painter: _PixelPainter(pixels!, pixelSize),
        );
      },
    );
  }
}

class _PixelPainter extends CustomPainter {
  final List<int> pixels;
  final double pixelSize;
  final Paint _paint = Paint();

  _PixelPainter(this.pixels, this.pixelSize);

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < pixels.length; i++) {
      final x = (i % 16) * pixelSize;
      final y = (i ~/ 16) * pixelSize;

      _paint.color = Color(pixels[i]); // ARGB32
      canvas.drawRect(Rect.fromLTWH(x, y, pixelSize, pixelSize), _paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PixelPainter oldDelegate) {
    return oldDelegate.pixels != pixels;
  }
}
