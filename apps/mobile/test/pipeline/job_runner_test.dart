import 'dart:convert';
import 'dart:io';

import 'package:fieldnote_contracts/fieldnote_contracts.dart' show MeetingSummary;
import 'package:fieldnote_mobile/src/jobs/job.dart';
import 'package:fieldnote_mobile/src/jobs/job_store.dart';
import 'package:fieldnote_mobile/src/pipeline/engines.dart';
import 'package:fieldnote_mobile/src/pipeline/job_runner.dart';
import 'package:fieldnote_mobile/src/pipeline/mac_gateway.dart';
import 'package:fieldnote_mobile/src/pipeline/summary_validation.dart';
import 'package:fieldnote_mobile/src/routing/routing_policy.dart';
import 'package:flutter_test/flutter_test.dart';

final schema = File('assets/meeting-summary.schema.json').readAsStringSync();
final template = File('assets/summarize-prompt.txt').readAsStringSync();
final validJson = File(
  '../../packages/contracts/fixtures/meeting-summary.valid.json',
).readAsStringSync();

class FakeSpeech implements SpeechToText {
  FakeSpeech([this.text = 'Arun: I will send the quote by Friday.']);
  final String text;
  final calls = <(String, String)>[];
  Object? error;

  @override
  Future<String> transcribe(String wavPath, {required String language}) async {
    calls.add((wavPath, language));
    if (error != null) throw error!;
    return text;
  }
}

class FakeModel implements SummaryModel {
  FakeModel(this.answer);
  String answer;
  final prompts = <String>[];

  @override
  Future<String> generate(String prompt) async {
    prompts.add(prompt);
    return answer;
  }
}

class Models implements ModelAvailability {
  Models({this.speechReady = true, this.summaryReady = true});
  @override
  bool speechReady;
  @override
  bool summaryReady;
}

class FakeMac implements MacGateway {
  FakeMac(this.state, [this.result]);
  MacStatus state;
  MacResult? result;
  final transcripts = <String>[];
  int statusCalls = 0;

  @override
  Future<MacStatus> status() async {
    statusCalls++;
    return state;
  }

  @override
  Future<MacResult> summarize({
    required String jobId,
    required String transcript,
    required String language,
  }) async {
    transcripts.add(transcript);
    return result!;
  }
}

void main() {
  late Directory dir;
  late JobStore store;
  var clock = DateTime.utc(2026, 11, 1, 9);
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('runner');
    clock = DateTime.utc(2026, 11, 1, 9);
    store = await JobStore.open(File('${dir.path}/jobs.json'), now: clock);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  JobRunner runner({
    SpeechToText? speech,
    SummaryModel? model,
    Models? models,
    MacGateway? mac,
    bool allowMac = true,
    RoutingThresholds thresholds = const RoutingThresholds(),
  }) => JobRunner(
    store: store,
    speech: speech ?? FakeSpeech(),
    summaryModel: model ?? FakeModel(validJson),
    models: models ?? Models(),
    validator: SummaryValidator(schema),
    promptTemplate: template,
    schemaJson: schema,
    allowMac: () => allowMac,
    now: () => clock,
    mac: mac,
    thresholds: thresholds,
  );

  Future<Job> recording({
    String id = 'rec-1',
    String language = 'ta-en',
    int seconds = 5,
  }) async {
    final wav = File('${dir.path}/$id.wav')
      ..writeAsBytesSync(List.filled(seconds * 32000, 0));
    return store.add(
      Job.queued(
        id: id,
        kind: JobKind.transcribe,
        inputPath: wav.path,
        language: language,
        now: clock,
      ),
    );
  }

  Future<Job> transcript(String text, {String id = 'tx-1'}) async {
    final file = File('${dir.path}/$id.txt')..writeAsStringSync(text);
    return store.add(
      Job.queued(
        id: id,
        kind: JobKind.summarize,
        inputPath: file.path,
        language: 'en',
        now: clock,
      ),
    );
  }

  test(
    'phone only: transcribes, queues the summary, and summarizes on the phone',
    () async {
      final speech = FakeSpeech();
      final model = FakeModel(validJson);
      await recording();

      final reports = await runner(speech: speech, model: model).runUntilIdle();

      expect(reports.map((r) => (r.jobId, r.route.runtimeType, r.state)), [
        ('rec-1', RunOnPhone, JobState.completed),
        ('rec-1.summary', RunOnPhone, JobState.completed),
      ]);
      expect(speech.calls.single.$2, 'ta-en');
      final summaryJob = store.byId('rec-1.summary')!;
      expect(summaryJob.placement, Placement.phone);
      expect(
        jsonDecode(File(summaryJob.resultPath!).readAsStringSync()),
        jsonDecode(validJson),
      );
      expect(
        model.prompts.single,
        contains('Arun: I will send the quote by Friday.'),
      );
      expect(
        File(store.byId('rec-1')!.resultPath!).readAsStringSync(),
        'Arun: I will send the quote by Friday.',
      );
    },
  );

  test(
    'hybrid: an invalid phone summary escalates to the online Mac',
    () async {
      final mac = FakeMac(
        MacStatus.online,
        MacCompleted(
          MeetingSummary.fromJson(
            jsonDecode(validJson) as Map<String, dynamic>,
          ),
        ),
      );
      await transcript('Priya: budget approved.');

      final reports = await runner(
        model: FakeModel('Sure! Here is the summary.'),
        mac: mac,
      ).runUntilIdle();

      expect(reports.map((r) => r.route.runtimeType), [RunOnPhone, RunOnMac]);
      final job = store.byId('tx-1')!;
      expect(
        (job.state, job.placement, job.phoneOutcome),
        (JobState.completed, Placement.mac, PhoneOutcome.invalidOutput),
      );
      expect(mac.transcripts, ['Priya: budget approved.']);
      expect(
        jsonDecode(File(job.resultPath!).readAsStringSync()),
        jsonDecode(validJson),
      );
    },
  );

  test('an invalid phone summary waits for a paired Mac that is offline, then runs when it is back', () async {
    final mac = FakeMac(
      MacStatus.pairedOffline,
      MacCompleted(
        MeetingSummary.fromJson(jsonDecode(validJson) as Map<String, dynamic>),
      ),
    );
    await transcript('x');
    final r = runner(model: FakeModel('not json'), mac: mac);

    await r.runUntilIdle();
    expect(store.byId('tx-1')!.state, JobState.retryable);

    mac.state = MacStatus.online;
    clock = clock.add(const Duration(minutes: 1));
    await r.runUntilIdle();
    expect(store.byId('tx-1')!.state, JobState.completed);
  });

  test(
    'an invalid phone summary with no Mac paired fails and says why',
    () async {
      await transcript('x');

      await runner(model: FakeModel('not json')).runUntilIdle();

      final job = store.byId('tx-1')!;
      expect(job.state, JobState.failed);
      expect(job.lastError, contains('no Mac is paired'));
    },
  );

  test('a Mac that becomes unreachable mid-job leaves the job retryable with backoff', () async {
    final mac = FakeMac(
      MacStatus.online,
      const MacUnavailable('connection reset'),
    );
    await transcript('x');

    await runner(model: FakeModel('not json'), mac: mac).runUntilIdle();

    final job = store.byId('tx-1')!;
    expect(job.state, JobState.retryable);
    expect(job.notBefore!.isAfter(clock), isTrue);
  });

  test(
    'when the Mac output is invalid too, the job fails instead of looping',
    () async {
      final mac = FakeMac(MacStatus.online, const MacInvalidOutput('not JSON'));
      await transcript('x');

      await runner(model: FakeModel('not json'), mac: mac).runUntilIdle();

      expect(store.byId('tx-1')!.state, JobState.failed);
    },
  );

  test('without the speech model, transcription fails: the Mac does not transcribe', () async {
    await recording();

    await runner(
      models: Models(speechReady: false),
      mac: FakeMac(MacStatus.online),
    ).runUntilIdle();

    expect(store.byId('rec-1')!.state, JobState.failed);
    expect(store.byId('rec-1.summary'), isNull);
  });

  test(
    'unreadable audio fails permanently; a crash in the engine is retried',
    () async {
      final speech = FakeSpeech()
        ..error = const FormatException('expected PCM 16 kHz');
      await recording(id: 'bad');
      await runner(speech: speech).runUntilIdle();
      expect(store.byId('bad')!.state, JobState.failed);

      speech.error = StateError('native engine crashed');
      await recording(id: 'crash');
      await runner(speech: speech).runUntilIdle();
      expect(store.byId('crash')!.state, JobState.retryable);
    },
  );

  test('with Mac use turned off, the runner never contacts the Mac', () async {
    final mac = FakeMac(MacStatus.online);
    await transcript('x');

    await runner(
      model: FakeModel('not json'),
      mac: mac,
      allowMac: false,
    ).runUntilIdle();

    expect(mac.statusCalls, 0);
    expect(store.byId('tx-1')!.lastError, contains('turned off'));
  });

  test(
    'a transcript over the word limit goes straight to the online Mac',
    () async {
      final mac = FakeMac(
        MacStatus.online,
        MacCompleted(
          MeetingSummary.fromJson(
            jsonDecode(validJson) as Map<String, dynamic>,
          ),
        ),
      );
      final model = FakeModel(validJson);
      await transcript('one two three four');

      await runner(
        model: model,
        mac: mac,
        thresholds: const RoutingThresholds(maxPhoneTranscriptWords: 3),
      ).runUntilIdle();

      expect(model.prompts, isEmpty);
      expect(store.byId('tx-1')!.placement, Placement.mac);
    },
  );
}
