import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/dot_entity.dart';
import '../../domain/dot_model.dart';
import '../../infra/dot_storage.dart';
import 'detail_screen.dart';
import 'exchange/qr_scan_screen.dart';
import 'edit_screen.dart';
import 'sub/dot_grid_body.dart';
import 'profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DotStorage _storage = DotStorage();
  int _currentIndex = 0;

  Future<void> _onFabPressed() async {
    // Navigate to EditScreen with new Dot (Directly, for creation)
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EditScreen(dot: null)),
    );
  }

  Future<void> _onDotTapped(DotModel dot) async {
    // Navigate to DetailScreen
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DetailScreen(dot: dot)),
    );
  }

  Future<void> _onScanPressed() async {
    final DotModel? receivedDot = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QrScanScreen()),
    );

    if (receivedDot != null) {
      await _storage.saveDot(receivedDot);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Received new Dot via QR!')),
        );
      }
    }
  }

  void _onTabTapped(int index) {
    if (index == 2) {
      // Edit/Create Tab
      _onFabPressed();
    } else {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentIndex == 1 ? 'Collection' : 'My Dots',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _onScanPressed,
            tooltip: 'Scan QR',
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: _storage.listen(),
        builder: (context, Box<DotEntity> box, _) {
          final allDots = _storage.listDots();

          // Filter dots
          // My Dots: isScanned == false
          // Collection: isScanned == true
          // If isScanned is null (legacy), assume false (My Dot)

          List<DotModel> dotsToShow;
          String emptyMessage;

          if (_currentIndex == 1) {
            // Collection
            dotsToShow = allDots.where((d) => d.isScanned == true).toList();
            emptyMessage =
                'No scanned dots yet.\nScan a QR code to add to collection!';
          } else {
            // Home / My Dots (default)
            dotsToShow = allDots.where((d) => d.isScanned == false).toList();
            emptyMessage = 'No dots yet.\nTap + to create one!';
          }

          // Sort by updated/created descending
          dotsToShow.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

          if (_currentIndex == 3) {
            return const ProfileScreen();
          }

          return DotGridBody(
            dots: dotsToShow,
            onDotTap: _onDotTapped,
            emptyMessage: emptyMessage,
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.collections),
            label: 'Collection',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Create',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
