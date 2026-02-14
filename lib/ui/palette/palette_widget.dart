import 'package:flutter/material.dart';
import '../../infra/storage_service.dart';

// 設計思想:
// - Recentは「履歴」ではなく「自然に構築される自分色」
// - 描画体験を最優先し、余計な管理UIは排除
// - setState最小化とRepaintBoundary対応

class PaletteWidget extends StatefulWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorSelected;
  final PaletteController controller;

  const PaletteWidget({
    super.key,
    required this.currentColor,
    required this.onColorSelected,
    required this.controller,
  });

  @override
  State<PaletteWidget> createState() => _PaletteWidgetState();
}

class _PaletteWidgetState extends State<PaletteWidget> {
  // Fixed Grayscale Palette (8 colors)
  static const List<Color> _grayscalePalette = [
    Color(0xFF000000), // Black
    Color(0xFF2A2A2A),
    Color(0xFF555555),
    Color(0xFF808080),
    Color(0xFFAAAAAA),
    Color(0xFFCCCCCC),
    Color(0xFFE5E5E5),
    Color(0xFFFFFFFF), // White
  ];

  // Recent Palette (Max 32)
  List<Color> _recentColors = [];
  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
    _loadPalette();
  }

  @override
  void dispose() {
    widget.controller._detach();
    super.dispose();
  }

  Future<void> _loadPalette() async {
    final intList = await _storage.loadRecentPalette();
    if (mounted) {
      setState(() {
        _recentColors = intList.map((c) => Color(c)).toList();
      });
    }
  }

  void _addRecent(Color color) {
    setState(() {
      // LRU Logic
      // 1. Remove if exists
      _recentColors.remove(color);
      // 2. Insert at 0
      _recentColors.insert(0, color);
      // 3. Trim to 32
      if (_recentColors.length > 32) {
        _recentColors.removeLast();
      }
    });
    // Fire and forget save
    _savePalette();
  }

  Future<void> _savePalette() async {
    final intList = _recentColors.map((c) => c.toARGB32()).toList();
    await _storage.saveRecentPalette(intList);
  }

  @override
  Widget build(BuildContext context) {
    // 8 columns fixed
    // Width is constrained by parent (likely screen width)
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Grayscale (Fixed)
        SizedBox(
          height: 48, // Fixed height for consistency
          child: Row(
            children: _grayscalePalette
                .map((c) => Expanded(child: _buildColorCell(c)))
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Recent (Dynamic Grid)
        // 4 rows max (= 32 cells / 8 columns)
        // Using RepaintBoundary to isolate updates
        RepaintBoundary(
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 32, // Fixed slots
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              crossAxisSpacing: 0,
              mainAxisSpacing: 0,
            ),
            itemBuilder: (context, index) {
              if (index < _recentColors.length) {
                return _buildColorCell(_recentColors[index]);
              } else {
                return const SizedBox(); // Empty slot
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildColorCell(Color color) {
    final isSelected = color == widget.currentColor;

    return GestureDetector(
      onTap: () => widget.onColorSelected(color),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: color,
          border: isSelected
              ? Border.all(color: Colors.blueAccent, width: 3) // Highlight
              : Border.all(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

// Controller to allow parent to trigger "Color Used" event
class PaletteController {
  _PaletteWidgetState? _state;

  void _attach(_PaletteWidgetState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  // Call this when the user *actually draws* with a color
  void notifyColorUsed(Color color) {
    _state?._addRecent(color);
  }
}
