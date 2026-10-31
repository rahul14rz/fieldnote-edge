import 'package:flutter/material.dart';

void main() {
  runApp(const FieldnoteApp());
}

class FieldnoteApp extends StatelessWidget {
  const FieldnoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fieldnote',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fieldnote')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Recording, transcription and summaries are not built yet. '
          'This screen is a placeholder for Milestone 0.',
        ),
      ),
    );
  }
}
