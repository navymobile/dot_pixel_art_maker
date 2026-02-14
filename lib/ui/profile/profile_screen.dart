import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../infra/user_storage.dart';
import '../../domain/dot_model.dart';
import 'dot_selection_screen.dart';
import '../../app_config.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _version = '';
  final UserStorage _userStorage = UserStorage();
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _initFuture = _userStorage.init(); // Start init
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _version = info.version;
    });
  }

  Future<void> _pickIcon() async {
    final DotModel? selectedDot = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DotSelectionScreen()),
    );

    if (selectedDot != null) {
      await _userStorage.saveUserIcon(selectedDot.pixels);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _pickIcon,
                child: ValueListenableBuilder(
                  valueListenable: _userStorage.listen(),
                  builder: (context, box, _) {
                    final pixels = _userStorage.getUserIcon();

                    if (pixels != null) {
                      return Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.indigo, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: CustomPaint(
                            painter: _ProfileIconPainter(pixels),
                          ),
                        ),
                      );
                    }

                    return const CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.indigo,
                      child: Icon(Icons.person, size: 50, color: Colors.white),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Guest User',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              TextButton(
                onPressed: _pickIcon,
                child: const Text('Change Icon'),
              ),
              const SizedBox(height: 32),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  // TODO: Implement settings
                },
              ),
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('Version'),
                trailing: Text(_version),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileIconPainter extends CustomPainter {
  final List<int> pixels;

  _ProfileIconPainter(this.pixels);

  @override
  void paint(Canvas canvas, Size size) {
    final double cellSize = size.width / AppConfig.dots;

    // Fill white background first for transparency
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

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
  bool shouldRepaint(covariant _ProfileIconPainter oldDelegate) {
    return oldDelegate.pixels != pixels; // Simple check, ideally check content
  }
}
