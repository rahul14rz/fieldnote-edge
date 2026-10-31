import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/spike_runner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SpikeApp());
}

/// Android: the app-specific external directory, which `adb push` can write
/// to without extra permissions. macOS: the sandbox container's Documents.
Future<Directory> workDirectory() async {
  if (Platform.isAndroid) {
    final dir = await getExternalStorageDirectory();
    if (dir != null) return dir;
  }
  return getApplicationDocumentsDirectory();
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({
    super.key,
    this.workDir = workDirectory,
    this.run = runFromWorkDir,
  });

  final Future<Directory> Function() workDir;
  final Future<File> Function(Directory, {required void Function(String) log})
  run;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Fieldnote spike',
    home: SpikeScreen(workDir: workDir, run: run),
  );
}

class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key, required this.workDir, required this.run});

  final Future<Directory> Function() workDir;
  final Future<File> Function(Directory, {required void Function(String) log})
  run;

  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<SpikeScreen> {
  final _lines = <String>[];
  String? _workDir;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    widget.workDir().then((dir) => setState(() => _workDir = dir.path));
  }

  void _log(String line) => setState(() => _lines.add(line));

  Future<void> _start() async {
    setState(() {
      _running = true;
      _lines.clear();
    });
    try {
      final result = await widget.run(Directory(_workDir!), log: _log);
      _log('DONE wrote ${result.path}');
    } catch (error) {
      _log('FAILED $error');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fieldnote spike')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText('Work directory: ${_workDir ?? '…'}'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _running || _workDir == null ? null : _start,
            child: Text(_running ? 'Running…' : 'Run $configFileName'),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [for (final line in _lines) SelectableText(line)],
            ),
          ),
        ],
      ),
    ),
  );
}
