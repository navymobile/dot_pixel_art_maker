import 'package:flutter/material.dart';
import '../../domain/dot_model.dart';

class ExportScreen extends StatelessWidget {
  final DotModel dot;

  const ExportScreen({super.key, required this.dot});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Export Screen'),
            const SizedBox(height: 16),
            Text('Dot ID: ${dot.id}'),
          ],
        ),
      ),
    );
  }
}
