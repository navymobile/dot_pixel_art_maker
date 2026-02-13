import '../../app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math' as math;
import '../../domain/dot_model.dart';
import '../../infra/dot_codec.dart';
import '../palette/palette_widget.dart';
import '../sub/import_photo_sheet.dart';

class DotEditor extends StatefulWidget {
  final DotModel initialDot;
  final Function(DotModel) onSave;

  const DotEditor({super.key, required this.initialDot, required this.onSave});

  @override
  State<DotEditor> createState() => _DotEditorState();
}

enum ToolType { pen, eraser, fill, circle, eyedropper }

class _DotEditorState extends State<DotEditor> {
  late List<int> _pixels;
  Color _currentColor = Colors.black;

  // Undo state (1 generation for import)
  List<int>? _undoPixels;
  ToolType _tool = ToolType.pen;
  final PaletteController _paletteController = PaletteController();

  // Circle Tool State
  Offset? _dragStart;
  Offset? _dragEnd;

  @override
  void initState() {
    super.initState();
    final int count = AppConfig.dots * AppConfig.dots;
    // Resize if dimension mismatch (ignore old data content if size changed)
    if (widget.initialDot.pixels.length != count) {
      _pixels = List<int>.filled(count, 0);
    } else {
      _pixels = List.from(widget.initialDot.pixels);
    }
  }

  void _onPanStart(DragStartDetails details, Size size) {
    if (_tool == ToolType.circle) {
      final pos = _getLocalGridPosition(details.localPosition, size);
      if (pos != null) {
        setState(() {
          _dragStart = details.localPosition;
          _dragEnd = details.localPosition;
        });
      }
    } else {
      _updatePixel(details.localPosition, size);
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    if (_tool == ToolType.circle) {
      setState(() {
        _dragEnd = details.localPosition;
      });
    } else {
      _updatePixel(details.localPosition, size);
    }
  }

  void _onPanEnd(DragEndDetails details, Size size) {
    if (_tool == ToolType.circle) {
      _commitCircle(size);
    }
    _recordColorUsage();
  }

  void _onTapDown(TapDownDetails details, Size size) {
    if (_tool != ToolType.circle) {
      _updatePixel(details.localPosition, size);
    }
  }

  void _onTapUp(TapUpDetails details, Size size) {
    if (_tool == ToolType.fill) {
      _floodFill(details.localPosition, size);
    }
    _recordColorUsage();
  }

  void _recordColorUsage() {
    if (_tool != ToolType.eraser) {
      _paletteController.notifyColorUsed(_currentColor);
    }
  }

  GridPoint? _getLocalGridPosition(Offset localPosition, Size size) {
    final double cellSize = size.width / AppConfig.dots;
    // 座標を計算
    int x = (localPosition.dx / cellSize).floor();
    int y = (localPosition.dy / cellSize).floor();

    // 範囲外でも、0〜最大値の間に収める (Clamp)
    // これにより、少し外側を触っても端のドットとして判定されます
    x = x.clamp(0, AppConfig.dots - 1);
    y = y.clamp(0, AppConfig.dots - 1);

    return GridPoint(x, y);
  }

  void _updatePixel(Offset localPosition, Size size) {
    if (_tool == ToolType.circle || _tool == ToolType.fill) return;

    final point = _getLocalGridPosition(localPosition, size);
    if (point == null) return;
    int index = point.y * AppConfig.dots + point.x;

    if (_tool == ToolType.eyedropper) {
      final pickedColorValue = _pixels[index];
      if (pickedColorValue != 0) {
        setState(() {
          _currentColor = Color(pickedColorValue);
          _tool = ToolType.pen;
        });
      }
      return;
    }

    int newColorValue = _tool == ToolType.eraser ? 0 : _currentColor.value;

    if (_pixels[index] != newColorValue) {
      setState(() {
        _pixels[index] = newColorValue;
      });
    }
  }

  void _floodFill(Offset localPosition, Size size) {
    final point = _getLocalGridPosition(localPosition, size);
    if (point == null) return;

    int targetIndex = point.y * AppConfig.dots + point.x;
    int targetColor = _pixels[targetIndex];
    int replacementColor = _currentColor.value;

    if (targetColor == replacementColor) return;

    // BFS
    List<int> queue = [targetIndex];
    Set<int> visited = {targetIndex};

    // Create a copy to modify
    List<int> newPixels = List.from(_pixels);

    while (queue.isNotEmpty) {
      int idx = queue.removeAt(0);
      newPixels[idx] = replacementColor;

      int x = idx % AppConfig.dots;
      int y = idx ~/ AppConfig.dots;

      // Neighbors (Up, Down, Left, Right)
      final neighbors = [
        if (y > 0) (y - 1) * AppConfig.dots + x,
        if (y < AppConfig.dots - 1) (y + 1) * AppConfig.dots + x,
        if (x > 0) y * AppConfig.dots + (x - 1),
        if (x < AppConfig.dots - 1) y * AppConfig.dots + (x + 1),
      ];

      for (var n in neighbors) {
        if (!visited.contains(n) && _pixels[n] == targetColor) {
          visited.add(n);
          queue.add(n);
        }
      }
    }

    setState(() {
      _pixels = newPixels;
    });
  }

  void _commitCircle(Size size) {
    if (_dragStart == null || _dragEnd == null) return;

    // We already have logic to get circle pixels in Painter?
    // No, we need it here to commit to _pixels.
    // Let's share the logic or duplicate it nicely.
    // Ideally put it in a helper.

    final points = _calculateCirclePoints(_dragStart!, _dragEnd!, size);
    int drawColor = _currentColor.value;

    setState(() {
      for (var p in points) {
        int idx = p.y * AppConfig.dots + p.x;
        _pixels[idx] = drawColor;
      }
      _dragStart = null;
      _dragEnd = null;
    });
  }

  List<GridPoint> _calculateCirclePoints(Offset start, Offset end, Size size) {
    final p1 = _getLocalGridPosition(start, size);
    final p2 = _getLocalGridPosition(end, size);

    if (p1 == null || p2 == null) return [];

    int left = math.min(p1.x, p2.x);
    int top = math.min(p1.y, p2.y);
    int right = math.max(p1.x, p2.x);
    int bottom = math.max(p1.y, p2.y); // inclusive corner

    // Center
    double centerX = (left + right) / 2.0;
    double centerY = (top + bottom) / 2.0;

    // Radii
    double radiusX = (right - left) / 2.0;
    double radiusY = (bottom - top) / 2.0;

    // If single point
    if (radiusX == 0 && radiusY == 0) return [GridPoint(left, top)];

    Set<GridPoint> pointsSet = {};

    // Circumference ~ 2 * pi * max(rx, ry)
    // Steps: circumference * 2 to be safe
    int steps = ((math.max(radiusX, radiusY) * 3 * 2 * math.pi)).ceil() + 10;
    if (steps == 0) steps = 10;

    for (int i = 0; i <= steps; i++) {
      double theta = (i / steps) * 2 * math.pi;

      // Simple trigonometric ellipse
      // x = cx + rx * cos(t)
      // y = cy + ry * sin(t)
      // We round to nearest int.

      int ix = (centerX + radiusX * getCos(theta)).round();
      int iy = (centerY + radiusY * getSin(theta)).round();

      if (ix >= 0 && ix < AppConfig.dots && iy >= 0 && iy < AppConfig.dots) {
        pointsSet.add(GridPoint(ix, iy));
      }
    }
    return pointsSet.toList();
  }

  double getCos(double t) =>
      (t == math.pi / 2 || t == 3 * math.pi / 2) ? 0 : math.cos(t);
  double getSin(double t) => (t == 0 || t == math.pi) ? 0 : math.sin(t);
  double widthFactor(double t) => 1.0;

  void _save() {
    final newDot = widget.initialDot.copyWith(pixels: _pixels);
    widget.onSave(newDot);
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pick a color'),
          content: SingleChildScrollView(
            child: HueRingPicker(
              pickerColor: _currentColor,
              onColorChanged: (color) {
                setState(() {
                  _currentColor = color;
                  _tool = ToolType.pen; // Switch to pen automatically
                });
              },
              enableAlpha: false,
              displayThumbColor: true,
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Done'),
              onPressed: () {
                Navigator.of(context).pop();
                // Color is updated in state, usage recorded on next draw or if we want here?
                // Specification said "actually used on canvas". So we rely on draw events.
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickAndImportPhoto() async {
    // 1. Select Source
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo Library'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      // 2. Pick Image
      final XFile? picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return;

      // 3. Crop (Square 1:1)
      final CroppedFile? cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop (1:1)',
            toolbarColor: Colors.deepOrange,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true, // User cannot change aspect ratio
          ),
          IOSUiSettings(
            title: 'Crop (1:1)',

            // 候補は square のみにしておく（任意）
            aspectRatioPresets: [CropAspectRatioPreset.square],

            // ★固定に寄せる設定
            aspectRatioPickerButtonHidden: true,
            resetAspectRatioEnabled: false,

            // 使えるなら（バージョンにより存在）
            aspectRatioLockEnabled: true,
            aspectRatioLockDimensionSwapEnabled: false,
          ),
        ],
      );
      if (cropped == null) return;

      final bytes = await cropped.readAsBytes();

      if (!mounted) return;

      // 4. Show Generation Sheet
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: ImportPhotoSheet(
            sourceBytes: bytes,
            onApply: (newPixels) {
              // 5. Apply with Undo
              setState(() {
                _undoPixels = List.from(_pixels);

                List<int> appliedPixels = newPixels;
                // インポート時に設定に合わせて減色プレビューを行う
                if (AppConfig.pixelEncoding == 'indexed8') {
                  // infra/dot_codec.dart のヘルパーを利用
                  // ※ DotCodec は既に import されている前提 (import '../../infra/dot_codec.dart'; が必要だが、
                  // もし無ければ追加する必要がある。ファイルの先頭を確認すると import '../../infra/dot_codec.dart' は無い。
                  // import '../../domain/dot_model.dart'; はある。
                  // infra層への依存を追加する。
                  appliedPixels = DotCodec.quantizeToIndexed8(newPixels);
                }

                // Apply new pixels
                final int count = AppConfig.dots * AppConfig.dots;
                // newPixels length should match, but be safe
                final len = appliedPixels.length < count
                    ? appliedPixels.length
                    : count;
                for (int i = 0; i < len; i++) {
                  _pixels[i] = appliedPixels[i];
                }
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Imported!'),
                  action: SnackBarAction(
                    label: 'UNDO',
                    onPressed: _restoreUndo,
                  ),
                  duration: const Duration(seconds: 4),
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error importing photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _restoreUndo() {
    if (_undoPixels != null) {
      setState(() {
        final int count = AppConfig.dots * AppConfig.dots;
        for (int i = 0; i < count; i++) {
          _pixels[i] = _undoPixels![i];
        }
        _undoPixels = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Structure: Canvas -> Toolbar -> Palette
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Column(
        children: [
          // 1. Canvas (Expanded)
          Expanded(
            child: InteractiveViewer(
              maxScale: 2.5,
              minScale: 1.0,
              panEnabled: false, // 1本指は描画用に通過させる (2本指で移動可能)
              boundaryMargin: const EdgeInsets.all(300),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );

                      List<GridPoint>? previewPoints;
                      if (_tool == ToolType.circle &&
                          _dragStart != null &&
                          _dragEnd != null) {
                        previewPoints = _calculateCirclePoints(
                          _dragStart!,
                          _dragEnd!,
                          size,
                        );
                      }

                      return GestureDetector(
                        onPanStart: (details) => _onPanStart(details, size),
                        onPanUpdate: (details) => _onPanUpdate(details, size),
                        onPanEnd: (details) => _onPanEnd(details, size),
                        onTapDown: (details) => _onTapDown(details, size),
                        onTapUp: (details) => _onTapUp(details, size),
                        child: CustomPaint(
                          size: size,
                          painter: _DotPainter(
                            pixels: _pixels,
                            previewPoints: previewPoints,
                            previewColor: _currentColor,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // 2. ToolBar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Save
              IconButton(
                icon: const Icon(Icons.save),
                color: Colors.blue,
                onPressed: _save,
                tooltip: 'Save',
              ),
              // Camera
              IconButton(
                icon: const Icon(Icons.camera_alt),
                color: Colors.green,
                onPressed: _pickAndImportPhoto,
                tooltip: 'Import from Photo',
              ),
              // Eyedropper
              IconButton(
                icon: const Icon(Icons.colorize),
                color: _tool == ToolType.eyedropper
                    ? _currentColor
                    : Colors.grey,
                onPressed: () => setState(() => _tool = ToolType.eyedropper),
                tooltip: 'Eyedropper',
                style: IconButton.styleFrom(
                  backgroundColor: _tool == ToolType.eyedropper
                      ? Colors.grey.shade200
                      : null,
                ),
              ),
              // Pen / Color Picker
              Tooltip(
                message: 'Pen (Tap again for Color)',
                child: InkWell(
                  onTap: () {
                    if (_tool == ToolType.pen) {
                      _showColorPicker();
                    } else {
                      setState(() => _tool = ToolType.pen);
                    }
                  },
                  customBorder: const CircleBorder(),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _tool == ToolType.pen
                          ? Colors.grey.shade200
                          : null,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _tool == ToolType.pen
                            ? Colors.blueAccent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Icon(Icons.circle, color: _currentColor),
                  ),
                ),
              ),
              // Fill
              IconButton(
                icon: const Icon(Icons.format_color_fill),
                color: _tool == ToolType.fill ? Colors.black : Colors.grey,
                onPressed: () => setState(() => _tool = ToolType.fill),
                tooltip: 'Flood Fill',
                style: IconButton.styleFrom(
                  backgroundColor: _tool == ToolType.fill
                      ? Colors.grey.shade200
                      : null,
                ),
              ),
              // Circle
              IconButton(
                icon: const Icon(Icons.circle_outlined),
                color: _tool == ToolType.circle ? Colors.black : Colors.grey,
                onPressed: () => setState(() => _tool = ToolType.circle),
                tooltip: 'Circle Tool',
                style: IconButton.styleFrom(
                  backgroundColor: _tool == ToolType.circle
                      ? Colors.grey.shade200
                      : null,
                ),
              ),
              // Eraser
              IconButton(
                icon: const Icon(Icons.cleaning_services),
                color: _tool == ToolType.eraser ? Colors.black : Colors.grey,
                onPressed: () => setState(() => _tool = ToolType.eraser),
                tooltip: 'Eraser',
                style: IconButton.styleFrom(
                  backgroundColor: _tool == ToolType.eraser
                      ? Colors.grey.shade200
                      : null,
                ),
              ),
              // Clear
              IconButton(
                icon: const Icon(Icons.delete),
                color: Colors.red,
                onPressed: () {
                  setState(
                    () => _pixels.fillRange(
                      0,
                      AppConfig.dots * AppConfig.dots,
                      0,
                    ),
                  );
                },
                tooltip: 'Clear All',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 3. Palette Widget (Grayscale + Recent)
          PaletteWidget(
            currentColor: _currentColor,
            controller: _paletteController,
            onColorSelected: (color) {
              setState(() {
                _currentColor = color;
                _tool = ToolType.pen;
              });
            },
          ),
        ],
      ),
    );
  }
}

class GridPoint {
  final int x;
  final int y;
  GridPoint(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      other is GridPoint && x == other.x && y == other.y;
  @override
  int get hashCode => Object.hash(x, y);
}

class _DotPainter extends CustomPainter {
  final List<int> pixels;
  final List<GridPoint>? previewPoints;
  final Color? previewColor;

  _DotPainter({required this.pixels, this.previewPoints, this.previewColor});

  @override
  void paint(Canvas canvas, Size size) {
    final double cellSize = size.width / AppConfig.dots;
    final Paint gridPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke;

    // 1. Draw Solid Background (for transparency)
    final Paint bgPaint = Paint()..color = Colors.grey.shade100;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 2. Draw Grid
    for (int i = 0; i <= AppConfig.dots; i++) {
      double pos = i * cellSize;
      canvas.drawLine(Offset(pos, 0), Offset(pos, size.height), gridPaint);
      canvas.drawLine(Offset(0, pos), Offset(size.width, pos), gridPaint);
    }

    // 3. Draw Dots
    for (int i = 0; i < pixels.length; i++) {
      int colorValue = pixels[i];
      if (colorValue != 0) {
        int x = i % AppConfig.dots;
        int y = i ~/ AppConfig.dots;

        final Paint dotPaint = Paint()
          ..color = Color(colorValue)
          ..style = PaintingStyle.fill;

        canvas.drawRect(
          Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize),
          dotPaint,
        );
      }
    }

    // 4. Draw Preview
    if (previewPoints != null &&
        previewColor != null &&
        previewPoints!.isNotEmpty) {
      final Paint previewPaint = Paint()
        ..color = previewColor!
        ..style = PaintingStyle.fill;

      for (var point in previewPoints!) {
        canvas.drawRect(
          Rect.fromLTWH(
            point.x * cellSize,
            point.y * cellSize,
            cellSize,
            cellSize,
          ),
          previewPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotPainter oldDelegate) {
    return true; // Always repaint for simplicity, or check props
  }
}
