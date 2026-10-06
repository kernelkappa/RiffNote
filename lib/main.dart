import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const RiffNoteApp());
}

class RiffNoteApp extends StatelessWidget {
  const RiffNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RiffNote',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
