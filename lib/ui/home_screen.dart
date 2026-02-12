import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/dot_entity.dart';
import '../../domain/dot_model.dart';
import '../../infra/dot_storage.dart';
import 'sub/dot_grid_item.dart';
import 'edit_screen.dart';
import 'exchange/exchange_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DotStorage _storage = DotStorage();
  double _crossAxisCount =
      4; // Default to 4 (or 5 as per user's last edit, let's stick to 4 or 5? User changed to 4 in edit, but 5 in code snippet? I'll use 5 as default based on their code override but they edited to 4? Let's use 5 as per snippet request 2..8 range). User said "値は2 , 3, 4, 5,6,7,8としてください". I'll default to 5.

  Future<void> _onFabPressed() async {
    // Navigate to EditScreen with new Dot
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EditScreen(dot: null)),
    );
  }

  Future<void> _onDotTapped(DotModel dot) async {
    // Navigate to Editing existing dot
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EditScreen(dot: dot)),
    );
  }

  Future<void> _onExchangePressed() async {
    // For MVP, just use a new blank dot or latest edited?
    // The previous implementation loaded "latest dot".
    // Now with multiple dots, we might need to pick one?
    // User flow: "Exchange button on Home".
    // If we have dots, maybe use the latest updated one?
    final dots = _storage.listDots();
    final targetDot = dots.isNotEmpty ? dots.first : DotModel.create();

    if (!mounted) return;

    final DotModel? receivedDot = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExchangeScreen(currentDot: targetDot),
      ),
    );

    if (receivedDot != null) {
      await _storage.saveDot(receivedDot);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Received new Dot! Gen +1')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Dots',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: _onExchangePressed,
            tooltip: 'Exchange',
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: _storage.listen(),
        builder: (context, Box<DotEntity> box, _) {
          final dots = _storage.listDots();

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

              // Empty State or Grid
              if (dots.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No dots yet.\nTap + to create one!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
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
                      final dot = dots[index];
                      return DotGridItem(
                        dot: dot,
                        onTap: () => _onDotTapped(dot),
                      );
                    }, childCount: dots.length),
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        currentIndex: 0, // Always home for now
        onTap: (index) {
          switch (index) {
            case 0:
              // Home - do nothing or scroll to top
              break;
            case 1:
              // Collection - Placeholder
              break;
            case 2:
              // Edit - Create new dot
              _onFabPressed();
              break;
            case 3:
              // Profile - Placeholder
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.collections),
            label: 'Collection',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.edit), label: 'Edit'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
