import 'package:flutter/material.dart';
import '../../domain/dot_model.dart';
import 'dot_grid_item.dart';

class DotGridBody extends StatefulWidget {
  final List<DotModel> dots;
  final Function(DotModel) onDotTap;
  final String emptyMessage;

  const DotGridBody({
    super.key,
    required this.dots,
    required this.onDotTap,
    this.emptyMessage = 'No dots found.',
  });

  @override
  State<DotGridBody> createState() => _DotGridBodyState();
}

class _DotGridBodyState extends State<DotGridBody> {
  double _crossAxisCount = 4;

  @override
  Widget build(BuildContext context) {
    if (widget.dots.isEmpty) {
      return Center(
        child: Text(
          widget.emptyMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // Slider Section (Scrollable)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                const Icon(Icons.grid_view, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _crossAxisCount,
                    min: 2,
                    max: 8,
                    divisions: 3,
                    label: _crossAxisCount.round().toString(),
                    onChanged: (value) {
                      setState(() {
                        _crossAxisCount = value;
                      });
                    },
                  ),
                ),
                Text(
                  '${_crossAxisCount.round()}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 80, // Space for FAB
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _crossAxisCount.round(),
              crossAxisSpacing: 24 - (_crossAxisCount * 2),
              mainAxisSpacing: 24 - (_crossAxisCount * 2),
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final dot = widget.dots[index];
              return DotGridItem(dot: dot, onTap: () => widget.onDotTap(dot));
            }, childCount: widget.dots.length),
          ),
        ),
      ],
    );
  }
}
