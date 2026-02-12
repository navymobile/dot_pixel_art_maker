import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'domain/dot_entity.dart';
import 'infra/dot_storage.dart';
import 'package:dot_pixel_art_maker/ui/home_screen.dart';

void main() async {
  await Hive.initFlutter();
  Hive.registerAdapter(DotEntityAdapter());
  await DotStorage().init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dot Pixel Art Maker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
