import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../domain/dot_model.dart';
import '../../infra/dot_storage.dart';
import 'edit_screen.dart';
import 'export/export_screen.dart';
import 'exchange/qr_display_screen.dart';
import '../app_config.dart';

class DetailScreen extends StatefulWidget {
  final DotModel dot;

  const DetailScreen({super.key, required this.dot});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late DotModel _dot;
  final DotStorage _storage = DotStorage();

  @override
  void initState() {
    super.initState();
    _dot = widget.dot;
  }

  Future<void> _navigateToEdit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EditScreen(dot: _dot)),
    );
    // Reload dot from storage to update view if changed
    final updatedDots = _storage.listDots().where((d) => d.id == _dot.id);
    if (updatedDots.isNotEmpty) {
      if (mounted) {
        setState(() {
          _dot = updatedDots.first;
        });
      }
    }
  }

  Future<void> _deleteDot() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Dot?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storage.deleteDot(_dot.id);
      if (mounted) {
        Navigator.pop(context); // Return to Home
      }
    }
  }

  Future<void> _onShowQrPressed() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => QrDisplayScreen(dot: _dot)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_dot.title ?? 'Dot Details'),
        actions: [
          IconButton(
            icon: const Icon(Symbols.ios_share),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ExportScreen(dot: _dot),
                ),
              );
            },
            tooltip: 'Export',
          ),
          IconButton(
            icon: const Icon(Symbols.delete),
            color: Colors.red,
            onPressed: _deleteDot,
            tooltip: 'Delete',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Preview
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.all(32),
              // color: Colors.grey.shade100, // Remove background color
              child: Hero(
                tag: _dot.id,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: const BoxDecoration(
                    // color: Colors.white, // Transparent by default
                    // boxShadow: [], // No shadow
                  ),
                  child: CustomPaint(painter: _DetailDotPainter(_dot.pixels)),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _dot.title ?? 'Untitled',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ID: ${_dot.id}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Gen: ${_dot.gen}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _navigateToEdit,
                          icon: const Icon(Symbols.edit),
                          label: const Text('Edit'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _onShowQrPressed,
                          icon: const Icon(Symbols.qr_code),
                          label: const Text('QR Code'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailDotPainter extends CustomPainter {
  final List<int> pixels;

  _DetailDotPainter(this.pixels);

  @override
  void paint(Canvas canvas, Size size) {
    final double cellSize = size.width / AppConfig.dots;

    // Draw dots
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
  }

  @override
  bool shouldRepaint(covariant _DetailDotPainter oldDelegate) => true;
}
