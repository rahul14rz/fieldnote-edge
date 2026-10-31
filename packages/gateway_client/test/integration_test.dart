@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:fieldnote_contracts/fieldnote_contracts.dart';
import 'package:fieldnote_gateway_client/fieldnote_gateway_client.dart';
import 'package:test/test.dart';

import 'gateway_process.dart';

void main() {
  final summaryJson = File('../contracts/fixtures/meeting-summary.valid.json')
      .readAsStringSync();
  final gateways = <GatewayProcess>[];
  tearDown(() async {
    for (final g in gateways) {
      await g.stop();
    }
    gateways.clear();
  });

  Future<GatewayProcess> start({
    String? modelAnswer,
    Map<String, String> env = const {},
  }) async {
    final g = await GatewayProcess.start(modelAnswer: modelAnswer, env: env);
    gateways.add(g);
    return g;
  }

  GatewayAddress addressOf(GatewayProcess g) =>
      GatewayAddress('127.0.0.1', g.port);

  test('pairs with a code, pins the certificate, and runs a job to a validated summary', () async {
    final gateway = await start(modelAnswer: summaryJson);
    final code = await gateway.pairingCode();

    final paired = await pair(
      addressOf(gateway),
      code: code,
      deviceName: 'integration test',
    );
    final client = GatewayClient(paired);
    addTearDown(client.close);

    expect(paired.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect((await client.health()).toJson()['status'], 'ok');

    final submitted = await client.submit(
      JobSubmission(
        jobId: 'job-1',
        kind: JobKind.SUMMARIZE,
        transcript: 'Arun: send it Friday',
        language: 'en',
      ),
    );
    expect(submitted.jobId, 'job-1');
    var status = submitted;
    for (var i = 0; i < 50 && status.state != JobState.COMPLETED; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      status = await client.status('job-1');
    }

    expect(status.state, JobState.COMPLETED);
    expect((await client.summary('job-1')).toJson(), jsonDecode(summaryJson));
  });

  test('pairs with a code typed in lower case with spaces or a dash', () async {
    final gateway = await start();
    final code = await gateway.pairingCode();
    final typed = '${code.substring(0, 5).toLowerCase()} -${code.substring(5)}';

    final paired = await pair(
      addressOf(gateway),
      code: typed,
      deviceName: 'phone',
    );

    expect(paired.deviceId, startsWith('dev_'));
  });

  test('a wrong code is rejected with 401 and pairs nothing', () async {
    final gateway = await start();

    await expectLater(
      pair(addressOf(gateway), code: '0000000000', deviceName: 'phone'),
      throwsA(
        isA<GatewayRejected>().having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
  });

  test('refuses a gateway whose certificate is not the pinned one', () async {
    final real = await start();
    final impostor = await start();
    final paired = await pair(
      addressOf(real),
      code: await real.pairingCode(),
      deviceName: 'phone',
    );

    final client = GatewayClient(paired.at(addressOf(impostor)));
    addTearDown(client.close);

    await expectLater(client.health(), throwsA(isA<PinMismatch>()));
  });

  test('reports an unreachable gateway as GatewayUnreachable', () async {
    final gateway = await start();
    final paired = await pair(
      addressOf(gateway),
      code: await gateway.pairingCode(),
      deviceName: 'phone',
    );
    await gateway.stop();
    gateways.remove(gateway);

    final client = GatewayClient(paired);
    addTearDown(client.close);

    await expectLater(client.health(), throwsA(isA<GatewayUnreachable>()));
  });

  test('a revoked device can no longer use the gateway', () async {
    final gateway = await start();
    final paired = await pair(
      addressOf(gateway),
      code: await gateway.pairingCode(),
      deviceName: 'phone',
    );
    final client = GatewayClient(paired);
    addTearDown(client.close);
    await expectLater(
      client.status('none'),
      throwsA(
        isA<GatewayRejected>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );

    final revoke = await Process.run(
      'node',
      [
        '${GatewayProcess.gatewayDir.path}/dist/src/cli.js',
        'revoke',
        paired.deviceId,
      ],
      environment: {'DATA_DIR': gateway.dataDir.path},
    );
    expect(revoke.exitCode, 0, reason: '${revoke.stdout}${revoke.stderr}');

    await expectLater(
      client.status('none'),
      throwsA(
        isA<GatewayRejected>().having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
  });

  test('rejects a pairing reply whose server proof is wrong, as from an impostor that lacks the code', () async {
    // Borrow a real gateway certificate so the impostor speaks TLS, then answer
    // pairing with a made-up credential and a wrong server proof.
    final real = await start();
    final tlsDir = '${real.dataDir.path}/tls';
    final context = SecurityContext()
      ..useCertificateChain('$tlsDir/gateway-cert.pem')
      ..usePrivateKey('$tlsDir/gateway-key.pem');
    final impostor = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    addTearDown(() => impostor.close(force: true));
    impostor.listen((request) async {
      await utf8.decodeStream(request);
      request.response
        ..statusCode = 201
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'deviceId': 'dev_${'0' * 32}',
            'deviceSecret': 'A' * 43,
            'serverProof': 'f' * 64,
          }),
        );
      await request.response.close();
    });

    await expectLater(
      pair(
        GatewayAddress('127.0.0.1', impostor.port),
        code: '44PY2HRX7D',
        deviceName: 'phone',
      ),
      throwsA(isA<ServerProofMismatch>()),
    );
  });
}
