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
  late DotModel _dot;

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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Editor',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(child: Text('Gen: ${_dot.gen}')),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: DotEditor(initialDot: _dot, onSave: _saveDot),
            ),
          ),
        ],
      ),
    );
  }
}
