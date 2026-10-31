import 'package:flutter/material.dart';

import '../jobs/job.dart';
import 'app_controller.dart';
import 'job_detail_screen.dart';
import 'languages.dart';
import 'settings_screen.dart';

String describe(Job? job) => switch (job?.state) {
  null => 'Waiting for transcript',
  JobState.queued => 'Queued',
  JobState.processing =>
    job!.placement == Placement.mac
        ? 'Running on the Mac'
        : 'Running on this phone',
  JobState.completed =>
    job!.placement == Placement.mac ? 'Done on the Mac' : 'Done on this phone',
  JobState.retryable => 'Will retry: ${job!.lastError ?? ''}',
  JobState.failed => 'Failed: ${job!.lastError ?? ''}',
  JobState.cancelled => 'Cancelled',
};

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final recordings = controller.recordings;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Fieldnote'),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(controller: controller),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (!controller.speechReady || !controller.summaryReady)
              MaterialBanner(
                content: const Text(
                  'Download the on-device models in Settings before recording.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsScreen(controller: controller),
                      ),
                    ),
                    child: const Text('Settings'),
                  ),
                ],
              ),
            if (controller.message != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(controller.message!),
              ),
            Expanded(
              child: recordings.isEmpty
                  ? const Center(
                      child: Text('No recordings yet. Tap Record to start.'),
                    )
                  : ListView(
                      children: [
                        for (final recording in recordings)
                          ListTile(
                            title: Text(
                              '${recording.id}  (${recordingLanguages[recording.language] ?? recording.language})',
                            ),
                            subtitle: Text(
                              'Transcript: ${describe(recording)}\nSummary: ${describe(controller.summaryFor(recording))}',
                            ),
                            isThreeLine: true,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => JobDetailScreen(
                                  controller: controller,
                                  recording: recording,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
        floatingActionButton: controller.isRecording
            ? FloatingActionButton.extended(
                onPressed: controller.stopRecording,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              )
            : FloatingActionButton.extended(
                onPressed: () => _pickLanguageAndRecord(context),
                icon: const Icon(Icons.mic),
                label: const Text('Record'),
              ),
      );
    },
  );

  Future<void> _pickLanguageAndRecord(BuildContext context) async {
    final language = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Language of the meeting')),
          for (final MapEntry(:key, :value) in recordingLanguages.entries)
            ListTile(
              title: Text(value),
              onTap: () => Navigator.of(context).pop(key),
            ),
        ],
      ),
    );
    if (language != null) await controller.startRecording(language);
  }
}
