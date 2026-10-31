import 'dart:io';

import 'package:fieldnote_gateway_client/fieldnote_gateway_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app/app_controller.dart';
import 'src/app/home_screen.dart';
import 'src/jobs/job_store.dart';
import 'src/pipeline/job_runner.dart';
import 'src/pipeline/mac_gateway.dart';
import 'src/pipeline/summary_validation.dart';
import 'src/platform/credential_store.dart';
import 'src/platform/edge_ai_engines.dart';
import 'src/platform/multicast_lock.dart';
import 'src/platform/recorder.dart';
import 'src/platform/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeEdgeAi();
  final support = await getApplicationSupportDirectory();
  final store = await JobStore.open(
    File('${support.path}/jobs.json'),
    now: DateTime.now(),
  );
  final schema = await rootBundle.loadString(
    'assets/meeting-summary.schema.json',
  );
  final template = await rootBundle.loadString('assets/summarize-prompt.txt');
  final models = EdgeAiModels();
  final recorder = WavRecorder();

  final controller = AppController(
    store: store,
    runnerFor: (mac, allowMac) => JobRunner(
      store: store,
      speech: WhisperSpeech(),
      summaryModel: GemmaSummary(),
      models: models,
      validator: SummaryValidator(schema),
      promptTemplate: template,
      schemaJson: schema,
      allowMac: allowMac,
      now: DateTime.now,
      mac: mac,
    ),
    recordingsDir: Directory('${support.path}/recordings'),
    recorder: recorder,
    models: models,
    credentials: SecureCredentialStore(),
    settingsStore: SettingsStore(File('${support.path}/settings.json')),
    pairFunction: pair,
    discover: () => withMulticastLock(discoverGateways),
    macFactory: (paired) => PairedMacGateway(GatewayClient(paired)),
    deviceName: Platform.localHostname,
  );
  await controller.start();
  runApp(FieldnoteApp(controller: controller));
}

class FieldnoteApp extends StatelessWidget {
  const FieldnoteApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Fieldnote',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: HomeScreen(controller: controller),
  );
}
