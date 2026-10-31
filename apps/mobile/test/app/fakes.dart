import 'dart:io';

import 'package:fieldnote_gateway_client/fieldnote_gateway_client.dart';
import 'package:fieldnote_mobile/src/app/app_controller.dart';
import 'package:fieldnote_mobile/src/jobs/job_store.dart';
import 'package:fieldnote_mobile/src/pipeline/engines.dart';
import 'package:fieldnote_mobile/src/pipeline/job_runner.dart';
import 'package:fieldnote_mobile/src/pipeline/mac_gateway.dart';
import 'package:fieldnote_mobile/src/pipeline/summary_validation.dart';
import 'package:fieldnote_mobile/src/platform/credential_store.dart';
import 'package:fieldnote_mobile/src/platform/settings_store.dart';
import 'package:fieldnote_mobile/src/routing/routing_policy.dart';

final schema = File('assets/meeting-summary.schema.json').readAsStringSync();
final template = File('assets/summarize-prompt.txt').readAsStringSync();
final validJson = File(
  '../../packages/contracts/fixtures/meeting-summary.valid.json',
).readAsStringSync();

class FakeRecorder implements Recorder {
  bool permission = true;
  String? path;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start(String path) async {
    this.path = path;
  }

  @override
  Future<String?> stop() async {
    File(path!).writeAsBytesSync(List.filled(32000, 0));
    return path;
  }
}

class FakeModels implements ModelInstaller, ModelAvailability {
  @override
  bool speechReady = true;
  @override
  bool summaryReady = true;
  int installs = 0;

  @override
  Future<void> installSpeechModel(void Function(int percent) onProgress) async {
    installs++;
    onProgress(100);
    speechReady = true;
  }

  @override
  Future<void> installSummaryModel(
    void Function(int percent) onProgress,
  ) async {
    installs++;
    onProgress(100);
    summaryReady = true;
  }
}

class MemoryCredentials implements CredentialStore {
  PairedGateway? stored;

  @override
  Future<PairedGateway?> read() async => stored;

  @override
  Future<void> write(PairedGateway gateway) async => stored = gateway;

  @override
  Future<void> delete() async => stored = null;
}

class OnlineMac implements MacGateway {
  @override
  Future<MacStatus> status() async => MacStatus.online;

  @override
  Future<MacResult> summarize({
    required String jobId,
    required String transcript,
    required String language,
  }) async => const MacUnavailable('not used');
}

class TextSpeech implements SpeechToText {
  @override
  Future<String> transcribe(String wavPath, {required String language}) async =>
      'Arun: I will send the quote.';
}

class FixedModel implements SummaryModel {
  FixedModel(this.answer);
  final String answer;

  @override
  Future<String> generate(String prompt) async => answer;
}

class Harness {
  Harness._(
    this.controller,
    this.dir,
    this.recorder,
    this.models,
    this.credentials,
    this.pairs,
  );

  final AppController controller;
  final Directory dir;
  final FakeRecorder recorder;
  final FakeModels models;
  final MemoryCredentials credentials;
  final List<(GatewayAddress, String)> pairs;

  static Future<Harness> create({
    String modelAnswer = '',
    Object? pairError,
  }) async {
    final dir = Directory.systemTemp.createTempSync('app');
    final store = await JobStore.open(
      File('${dir.path}/jobs.json'),
      now: DateTime.now(),
    );
    final recorder = FakeRecorder();
    final models = FakeModels();
    final credentials = MemoryCredentials();
    final pairs = <(GatewayAddress, String)>[];
    final controller = AppController(
      store: store,
      runnerFor: (mac, allowMac) => JobRunner(
        store: store,
        speech: TextSpeech(),
        summaryModel: FixedModel(modelAnswer.isEmpty ? validJson : modelAnswer),
        models: models,
        validator: SummaryValidator(schema),
        promptTemplate: template,
        schemaJson: schema,
        allowMac: allowMac,
        now: DateTime.now,
        mac: mac,
      ),
      recordingsDir: Directory('${dir.path}/recordings'),
      recorder: recorder,
      models: models,
      credentials: credentials,
      settingsStore: SettingsStore(File('${dir.path}/settings.json')),
      pairFunction: (address, {required code, required deviceName}) async {
        pairs.add((address, code));
        if (pairError != null) throw pairError;
        return PairedGateway(
          address: address,
          fingerprint: 'ab' * 32,
          deviceId: 'dev_${'0' * 32}',
          deviceSecret: 'A' * 43,
        );
      },
      discover: () async => [
        DiscoveredGateway(
          name: 'Fieldnote gateway on macbook',
          address: const GatewayAddress('192.168.1.20', 8787),
          fingerprintPrefix: 'ab' * 8,
        ),
      ],
      macFactory: (_) => OnlineMac(),
      deviceName: 'test phone',
    );
    return Harness._(controller, dir, recorder, models, credentials, pairs);
  }
}
