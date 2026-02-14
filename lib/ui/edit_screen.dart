import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/material.dart';
import '../../app_config.dart';
import '../../domain/dot_model.dart';
import '../../infra/dot_storage.dart';
import 'canvas/dot_editor.dart';

class EditScreen extends StatefulWidget {
  final DotModel? dot;

  const EditScreen({super.key, this.dot});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  final DotStorage _storage = DotStorage();
  final DotEditorController _editorController = DotEditorController();
  late DotModel _dot;
  bool _canPop = false; // Add flag to control pop

  @override
  void initState() {
    super.initState();
    _dot = widget.dot ?? DotModel.create();
  }

  Future<void> _saveDot(DotModel dot) async {
    await _storage.saveDot(dot);
    if (mounted) {
      setState(() {
        _dot = dot;
      });
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved!'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // User tried to go back (gesture or back button while _canPop=false)
        // Here we just ignore it to block gestures.
        // If we want a confirmation dialog, we can show it here.
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () {
              // Allow popping via the button
              setState(() {
                _canPop = true;
              });
              final navigator = Navigator.of(context);
              // Wait for rebuild to apply _canPop=true then pop
              Future.microtask(() {
                navigator.pop();
              });
            },
          ),
          title: const Text(
            'Edit',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Symbols.save),
              tooltip: 'Save',
              onPressed: _editorController.save,
            ),
            IconButton(
              icon: const Icon(Symbols.photo_camera),
              tooltip: 'Import from Photo',
              onPressed: _editorController.importPhoto,
            ),
            IconButton(
              icon: const Icon(Symbols.open_in_full),
              tooltip: 'Resize Canvas',
              onPressed: () {
                _showDotMultiplierSheet(context);
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: DotEditor(
                  key: ValueKey(_dot.id),
                  initialDot: _dot,
                  onSave: _saveDot,
                  controller: _editorController,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDotMultiplierSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: AppConfig.dotMultipliers.map((multiplier) {
              final newDots = AppConfig.dots * multiplier;
              return ListTile(
                title: Text('x$multiplier (${newDots}x$newDots)'),
                onTap: () {
                  Navigator.pop(context);
                  _multiplyDots(multiplier);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _multiplyDots(int multiplier) {
    // 1. Calculate new dot count
    final int currentDots = AppConfig.dots;
    final int newDots = currentDots * multiplier;
    final int newCount = newDots * newDots;

    // 2. Create new pixels array with multiplied dots (Nearest Neighbor)
    final List<int> newPixels = List<int>.filled(newCount, 0);
    final List<int> originalPixels = _dot.pixels;

    for (int y = 0; y < newDots; y++) {
      for (int x = 0; x < newDots; x++) {
        int origX = x ~/ multiplier;
        int origY = y ~/ multiplier;
        int origIndex = origY * currentDots + origX;

        if (origIndex < originalPixels.length) {
          int color = originalPixels[origIndex];
          int newIndex = y * newDots + x;
          newPixels[newIndex] = color;
        }
      }
    }

    // 3. Create new DotModel
    final newDot = DotModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // New ID
      title: '${_dot.title} (x$multiplier)',
      pixels: newPixels,
    );

    // 4. Update state to open new dot in editor
    // We might want to push a new EditScreen or replace current one.
    // For now, replacing current one is simpler to implement in this flow.
    // But pushing new one preserves the original in the stack.
    // Let's replace current structure for now as requested "open in editor".

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => EditScreen(dot: newDot)));
  }
}
