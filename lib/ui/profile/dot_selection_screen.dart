import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/dot_entity.dart';
import '../../infra/dot_storage.dart';
import '../sub/dot_grid_body.dart';

class DotSelectionScreen extends StatelessWidget {
  const DotSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = DotStorage();

    return Scaffold(
      appBar: AppBar(title: const Text('Select Icon')),
      body: ValueListenableBuilder(
        valueListenable: storage.listen(),
        builder: (context, Box<DotEntity> box, _) {
          final allDots = storage.listDots();
          // Filter to show only "My Dots" (created by user)
          final myDots = allDots.where((d) => d.isScanned == false).toList();

          return DotGridBody(
            dots: myDots,
            onDotTap: (dot) {
              Navigator.pop(context, dot);
            },
            emptyMessage: 'No dots available to select.\nCreate one first!',
          );
        },
      ),
    );
  }
}
