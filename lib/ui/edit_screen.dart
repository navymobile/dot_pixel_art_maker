import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
              // Wait for rebuild to apply _canPop=true then pop
              Future.microtask(() {
                if (mounted) Navigator.of(context).pop();
              });
            },
          ),
          title: const Text(
            'Edit',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(CupertinoIcons.square_arrow_down),
              tooltip: 'Save',
              onPressed: _editorController.save,
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.camera),
              tooltip: 'Import from Photo',
              onPressed: _editorController.importPhoto,
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.arrow_up_left_arrow_down_right),
              tooltip: 'Switch to x2 (coming soon)',
              onPressed: null,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: DotEditor(
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
}
