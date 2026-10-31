import 'dart:async';
import 'dart:io';

import 'package:fieldnote_gateway_client/fieldnote_gateway_client.dart';
import 'package:flutter/foundation.dart';

import '../jobs/job.dart';
import '../jobs/job_store.dart';
import '../pipeline/job_runner.dart';
import '../pipeline/mac_gateway.dart';
import '../platform/credential_store.dart';
import '../platform/settings_store.dart';
import '../routing/routing_policy.dart';

/// Records audio to a WAV file.
abstract interface class Recorder {
  Future<bool> hasPermission();
  Future<void> start(String path);
  Future<String?> stop();
}

/// Installs the on-device models.
abstract interface class ModelInstaller {
  bool get speechReady;
  bool get summaryReady;
  Future<void> installSpeechModel(void Function(int percent) onProgress);
  Future<void> installSummaryModel(void Function(int percent) onProgress);
}

/// The Mac the runner talks to. Pairing and unpairing swap what is behind it.
class SwitchableMac implements MacGateway {
  MacGateway? current;

  @override
  Future<MacStatus> status() async =>
      await current?.status() ?? MacStatus.unpaired;

  @override
  Future<MacResult> summarize({
    required String jobId,
    required String transcript,
    required String language,
  }) =>
      current?.summarize(
        jobId: jobId,
        transcript: transcript,
        language: language,
      ) ??
      Future.value(const MacUnavailable('no Mac is paired'));
}

typedef PairFunction = Future<PairedGateway> Function(
  GatewayAddress address, {
  required String code,
  required String deviceName,
});
typedef MacFactory = MacGateway Function(PairedGateway paired);

/// App state for the UI (ADR 0004: built-in ChangeNotifier, no package).
class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    required this.runnerFor,
    required this.recordingsDir,
    required this.recorder,
    required this.models,
    required this.credentials,
    required this.settingsStore,
    required this.pairFunction,
    required this.discover,
    required this.macFactory,
    required this.deviceName,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final JobStore store;

  /// Builds the runner. Receives the switchable Mac and the live settings.
  final JobRunner Function(MacGateway mac, bool Function() allowMac) runnerFor;
  final Directory recordingsDir;
  final Recorder recorder;
  final ModelInstaller models;
  final CredentialStore credentials;
  final SettingsStore settingsStore;
  final PairFunction pairFunction;
  final Future<List<DiscoveredGateway>> Function() discover;
  final MacFactory macFactory;
  final String deviceName;
  final DateTime Function() now;

  final mac = SwitchableMac();
  late final JobRunner _runner = runnerFor(mac, () => settings.allowMac);
  Timer? _timer;
  Future<void>? _current;
  bool _again = false;

  AppSettings settings = const AppSettings();
  PairedGateway? paired;
  MacStatus macStatus = MacStatus.unpaired;
  String? recordingPath;
  String recordingLanguage = 'en';
  int? speechProgress;
  int? summaryProgress;
  String? message;

  bool get isRecording => recordingPath != null;
  bool get speechReady => models.speechReady;
  bool get summaryReady => models.summaryReady;

  /// Recordings, newest first. Each has a transcription job and, once that
  /// finishes, a summary job.
  List<Job> get recordings => store.jobs
      .where((j) => j.kind == JobKind.transcribe)
      .toList()
      .reversed
      .toList();

  Job? summaryFor(Job recording) => store.byId(summaryJobId(recording.id));

  Future<void> start() async {
    settings = await settingsStore.read();
    paired = await credentials.read();
    if (paired != null) mac.current = macFactory(paired!);
    await refreshMacStatus();
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(kick()),
    );
    unawaited(kick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refreshMacStatus() async {
    macStatus = await mac.status();
    notifyListeners();
  }

  /// Runs every runnable job. A call while the runner is busy makes it run
  /// once more when it finishes, so a job added mid-run is not left waiting.
  /// The returned future completes when the runner is idle.
  Future<void> kick() {
    if (_current case final running?) {
      _again = true;
      return running;
    }
    return _current = _drain().whenComplete(() => _current = null);
  }

  Future<void> _drain() async {
    try {
      do {
        _again = false;
        await _runner.runUntilIdle();
        notifyListeners();
      } while (_again);
    } on Object catch (e) {
      message = 'Job runner stopped: $e';
    } finally {
      notifyListeners();
    }
  }

  Future<void> startRecording(String language) async {
    if (isRecording) return;
    if (!await recorder.hasPermission()) {
      message = 'Microphone permission is needed to record.';
      notifyListeners();
      return;
    }
    recordingsDir.createSync(recursive: true);
    final id =
        'rec-${now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14)}';
    final path = '${recordingsDir.path}/$id.wav';
    await recorder.start(path);
    recordingPath = path;
    recordingLanguage = language;
    notifyListeners();
  }

  Future<void> stopRecording() async {
    final path = recordingPath;
    if (path == null) return;
    final finished = await recorder.stop() ?? path;
    recordingPath = null;
    final id = finished.split('/').last.replaceAll('.wav', '');
    await store.add(
      Job.queued(
        id: id,
        kind: JobKind.transcribe,
        inputPath: finished,
        language: recordingLanguage,
        now: now(),
      ),
    );
    notifyListeners();
    unawaited(kick());
  }

  Future<void> cancel(Job job) async {
    await store.update(job.id, (j) => j.cancel(now()));
    notifyListeners();
  }

  Future<void> setAllowMac(bool value) async {
    settings = settings.copyWith(allowMac: value);
    await settingsStore.write(settings);
    notifyListeners();
  }

  Future<List<DiscoveredGateway>> findGateways() => discover();

  /// Pairs with the gateway at [address]. Returns null on success, or the
  /// message to show.
  Future<String?> pairWith(GatewayAddress address, String code) async {
    try {
      final result = await pairFunction(
        address,
        code: code,
        deviceName: deviceName,
      );
      await credentials.write(result);
      paired = result;
      mac.current = macFactory(result);
      await refreshMacStatus();
      unawaited(kick());
      return null;
    } on GatewayRejected catch (e) {
      return e.statusCode == 429
          ? 'Too many wrong codes. Wait a minute and try again.'
          : 'The Mac rejected the code. Run "pair" again on the Mac for a new one.';
    } on ServerProofMismatch {
      return 'This device could not prove it is your Mac. Pairing stopped.';
    } on GatewayUnreachable {
      return 'Could not reach the Mac at $address.';
    }
  }

  Future<void> unpair() async {
    await credentials.delete();
    paired = null;
    mac.current = null;
    macStatus = MacStatus.unpaired;
    notifyListeners();
  }

  Future<void> installModels() async {
    try {
      if (!models.speechReady) {
        await models.installSpeechModel((p) {
          speechProgress = p;
          notifyListeners();
        });
      }
      if (!models.summaryReady) {
        await models.installSummaryModel((p) {
          summaryProgress = p;
          notifyListeners();
        });
      }
    } on Object catch (e) {
      message = 'Model download failed: $e';
    } finally {
      speechProgress = null;
      summaryProgress = null;
      notifyListeners();
      unawaited(kick());
    }
  }
}
