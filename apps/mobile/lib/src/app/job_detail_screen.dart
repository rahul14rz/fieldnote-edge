import 'dart:convert';
import 'dart:io';

import 'package:fieldnote_contracts/fieldnote_contracts.dart'
    show MeetingSummary;
import 'package:flutter/material.dart';

import '../jobs/job.dart';
import 'app_controller.dart';
import 'home_screen.dart' show describe;

class JobDetailScreen extends StatelessWidget {
  const JobDetailScreen({
    super.key,
    required this.controller,
    required this.recording,
  });
  final AppController controller;
  final Job recording;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final transcribe = controller.store.byId(recording.id) ?? recording;
      final summarize = controller.summaryFor(transcribe);
      final transcript = _read(
        transcribe.state == JobState.completed ? transcribe.resultPath : null,
      );
      final summaryJson = _read(
        summarize?.state == JobState.completed ? summarize?.resultPath : null,
      );
      final summary = summaryJson == null
          ? null
          : MeetingSummary.fromJson(
              jsonDecode(summaryJson) as Map<String, dynamic>,
            );
      return Scaffold(
        appBar: AppBar(title: Text(transcribe.id)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Summary', style: Theme.of(context).textTheme.titleLarge),
            if (summary == null)
              Text(describe(summarize))
            else
              ..._summary(context, summary),
            const SizedBox(height: 24),
            Text('Transcript', style: Theme.of(context).textTheme.titleLarge),
            SelectableText(transcript ?? describe(transcribe)),
          ],
        ),
      );
    },
  );

  static String? _read(String? path) => path == null || !File(path).existsSync()
      ? null
      : File(path).readAsStringSync();

  List<Widget> _summary(BuildContext context, MeetingSummary s) {
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
    return [
      heading('Participants'),
      for (final p in s.participants)
        Text(p.role == null ? p.name : '${p.name} (${p.role})'),
      heading('Topics'),
      for (final t in s.topics) Text('• $t'),
      heading('Decisions'),
      for (final d in s.decisions) Text('• $d'),
      heading('Action items'),
      for (final a in s.actionItems)
        Text(
          '• ${a.description}. Owner: ${a.owner ?? 'not stated'}. Due: ${a.dueDate ?? 'not stated'}.',
        ),
    ];
  }
}
