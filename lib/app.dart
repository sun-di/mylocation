import 'package:flutter/material.dart';
import 'pages/home_page.dart';

class ShowLocationApp extends StatelessWidget {
  const ShowLocationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShowLocation',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
