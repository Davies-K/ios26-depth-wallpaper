import 'package:depth_wallpaper/depth_wallpaper.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Depth Wallpaper Example',
      theme: ThemeData(textTheme: GoogleFonts.interTextTheme()),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key,});


  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DepthWallpaper(
        imagePath: 'assets/images/example_2.jpeg',
        useLocalProcessing: false,
        // TODO: Replace with your own API key from https://www.remove.bg/api
        removeBackgroundApiKey: 'RTzvFVmPrEz2rmH1n3Vpvq9x',
        clockWidget: Padding(
          padding: const EdgeInsets.only(top: 120.0),
          child: IOSLockScreenClock(timeSize: 180),
        ),
      ),
    );
  }
}
