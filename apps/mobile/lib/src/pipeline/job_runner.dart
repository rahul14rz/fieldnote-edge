import 'dart:convert';
import 'dart:io';

import '../jobs/job.dart';
import '../jobs/job_store.dart';
import '../routing/routing_policy.dart';
import 'engines.dart';
import 'mac_gateway.dart';
import 'summary_validation.dart';

/// What the runner did with one job, for logs and tests.
class RunReport {
  const RunReport(this.jobId, this.route, this.state);
  final String jobId;
  final Route route;
  final JobState state;
}

/// Runs jobs from the store one at a time: asks the routing policy where each
/// one goes, runs it there, and records the outcome before moving on.
///
/// The Mac can't transcribe (the gateway takes summary jobs only, ADR 0008),
/// so transcription is routed as if no Mac were paired.
class JobRunner {
  JobRunner({
    required this.store,
    required this.speech,
    required this.summaryModel,
    required this.models,
    required this.validator,
    required this.promptTemplate,
    required this.schemaJson,
    required this.allowMac,
    required this.now,
    this.mac,
    this.thresholds = const RoutingThresholds(),
    this.waitForMacDelay = const Duration(minutes: 1),
  });

  final JobStore store;
  final SpeechToText speech;
  final SummaryModel summaryModel;
  final ModelAvailability models;
  final SummaryValidator validator;
  final String promptTemplate;
  final String schemaJson;
  final bool Function() allowMac;
  final DateTime Function() now;
  final MacGateway? mac;
  final RoutingThresholds thresholds;
  final Duration waitForMacDelay;

  /// Runs the next runnable job. Returns null when nothing is runnable.
  Future<RunReport?> runNext() async {
    final job = await store.nextRunnable(now());
    if (job == null) return null;
    final macStatus = job.kind == JobKind.transcribe
        ? MacStatus.unpaired
        : (allowMac() ? await mac?.status() : null) ?? MacStatus.unpaired;
    final decision = route(
      RoutingInput(
        kind: job.kind,
        inputSize: await _inputSize(job),
        phoneModelReady: job.kind == JobKind.transcribe
            ? models.speechReady
            : models.summaryReady,
        mac: macStatus,
        lastPhoneOutcome: job.phoneOutcome,
        allowMac: allowMac(),
        thresholds: thresholds,
      ),
    );
    final Job after;
    switch (decision) {
      case RunOnPhone():
        after = await _runOnPhone(job);
      case RunOnMac():
        after = await _runOnMac(job);
      case WaitForMac(:final reason):
        after = await store.update(
          job.id,
          (j) => j.waitForMac(reason, now(), waitForMacDelay),
        );
      case CannotRun(:final reason):
        after = await store.update(
          job.id,
          (j) => j.failPermanent(reason, now()),
        );
    }
    return RunReport(job.id, decision, after.state);
  }

  /// Runs jobs until none is runnable now. Returns what was done.
  Future<List<RunReport>> runUntilIdle() async {
    final reports = <RunReport>[];
    for (
      var report = await runNext();
      report != null;
      report = await runNext()
    ) {
      reports.add(report);
    }
    return reports;
  }

  Future<int> _inputSize(Job job) async {
    final file = File(job.inputPath);
    if (!file.existsSync()) return 0;
    return switch (job.kind) {
      // 16 kHz mono 16-bit PCM is 32000 bytes per second.
      JobKind.transcribe => (await file.length()) ~/ 32000,
      JobKind.summarize =>
        (await file.readAsString())
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .length,
    };
  }

  Future<Job> _runOnPhone(Job queued) async {
    final job = await store.update(
      queued.id,
      (j) => j.start(Placement.phone, now()),
    );
    switch (job.kind) {
      case JobKind.transcribe:
        final String text;
        try {
          text = await speech.transcribe(job.inputPath, language: job.language);
        } on FormatException catch (e) {
          return store.update(
            job.id,
            (j) => j.failPermanent('unreadable audio: ${e.message}', now()),
          );
        } on Object catch (e) {
          return store.update(
            job.id,
            (j) => j.failTransient(
              'transcription failed: $e',
              now(),
              store.policy,
            ),
          );
        }
        final transcriptPath = _sibling(job.inputPath, '.transcript.txt');
        await _writeAtomically(transcriptPath, text);
        final done = await store.update(
          job.id,
          (j) => j.complete(transcriptPath, now()),
        );
        await store.add(
          Job.queued(
            id: summaryJobId(job.id),
            kind: JobKind.summarize,
            inputPath: transcriptPath,
            language: job.language,
            now: now(),
          ),
        );
        return done;
      case JobKind.summarize:
        final String answer;
        try {
          final transcript = await File(job.inputPath).readAsString();
          answer = await summaryModel.generate(
            summarizePrompt(
              template: promptTemplate,
              schemaJson: schemaJson,
              transcript: transcript,
            ),
          );
        } on Object catch (e) {
          return store.update(
            job.id,
            (j) =>
                j.escalate(PhoneOutcome.error, 'phone model failed: $e', now()),
          );
        }
        switch (validator.validate(answer)) {
          case ValidSummary(:final json):
            final path = _sibling(job.inputPath, '.summary.json');
            await _writeAtomically(path, json);
            return store.update(job.id, (j) => j.complete(path, now()));
          case InvalidSummary(:final reason):
            return store.update(
              job.id,
              (j) => j.escalate(PhoneOutcome.invalidOutput, reason, now()),
            );
        }
    }
  }

  Future<Job> _runOnMac(Job queued) async {
    final job = await store.update(
      queued.id,
      (j) => j.start(Placement.mac, now()),
    );
    final transcript = await File(job.inputPath).readAsString();
    final result = await mac!.summarize(
      jobId: job.id,
      transcript: transcript,
      language: job.language,
    );
    switch (result) {
      case MacCompleted(:final summary):
        switch (validator.validate(jsonEncode(summary.toJson()))) {
          case ValidSummary(:final json):
            final path = _sibling(job.inputPath, '.summary.json');
            await _writeAtomically(path, json);
            return store.update(job.id, (j) => j.complete(path, now()));
          case InvalidSummary(:final reason):
            return store.update(
              job.id,
              (j) => j.failPermanent(
                'the Mac summary failed validation: $reason',
                now(),
              ),
            );
        }
      case MacInvalidOutput(:final reason):
        return store.update(
          job.id,
          (j) => j.failPermanent(
            'the Mac output failed validation too: $reason',
            now(),
          ),
        );
      case MacUnavailable(:final reason):
        return store.update(
          job.id,
          (j) => j.failTransient(reason, now(), store.policy),
        );
    }
  }
}

String summaryJobId(String transcribeJobId) => '$transcribeJobId.summary';

String _sibling(String path, String suffix) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf(Platform.pathSeparator);
  return '${dot > slash ? path.substring(0, dot) : path}$suffix';
}

Future<void> _writeAtomically(String path, String contents) async {
  final temp = File('$path.tmp');
  await temp.writeAsString(contents, flush: true);
  await temp.rename(path);
}
