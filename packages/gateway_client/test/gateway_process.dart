import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The built gateway (`pnpm --filter @fieldnote/gateway build`) run as a
/// child process, with a fake OpenAI-compatible model server in this isolate.
class GatewayProcess {
  GatewayProcess._(this.process, this.port, this.dataDir, this._model);

  final Process process;
  final int port;
  final Directory dataDir;
  final HttpServer? _model;

  static final gatewayDir = Directory('../../services/gateway');
  static File get _server => File('${gatewayDir.path}/dist/src/server.js');
  static File get _cli => File('${gatewayDir.path}/dist/src/cli.js');

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  /// [modelAnswer] is what the fake model returns for every prompt.
  static Future<GatewayProcess> start({
    String? modelAnswer,
    Map<String, String> env = const {},
  }) async {
    if (!_server.existsSync()) {
      throw StateError(
        'build the gateway first: pnpm --filter @fieldnote/gateway build',
      );
    }
    HttpServer? model;
    if (modelAnswer != null) {
      model = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      model.listen((request) async {
        await utf8.decodeStream(request);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': modelAnswer},
              },
            ],
          }),
        );
        await request.response.close();
      });
    }
    final dataDir = Directory.systemTemp.createTempSync('gateway-client-');
    final port = await _freePort();
    final process = await Process.start(
      'node',
      [_server.path],
      environment: {
        'PORT': '$port',
        'HOST': '127.0.0.1',
        'DATA_DIR': dataDir.path,
        'MDNS': 'off',
        'LOG_LEVEL': 'info',
        if (model != null) ...{
          'INFERENCE_BACKEND': 'openai-compatible',
          'INFERENCE_URL': 'http://127.0.0.1:${model.port}/v1',
          'INFERENCE_MODEL': 'test-model',
        },
        ...env,
      },
    );
    final ready = Completer<void>();
    final lines = <String>[];
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          lines.add(line);
          if (line.contains('Server listening') && !ready.isCompleted) {
            ready.complete();
          }
        });
    process.stderr.transform(utf8.decoder).listen(lines.add);
    unawaited(
      process.exitCode.then((code) {
        if (!ready.isCompleted) {
          ready.completeError(
            StateError('gateway exited with $code:\n${lines.join('\n')}'),
          );
        }
      }),
    );
    await ready.future.timeout(const Duration(seconds: 20));
    return GatewayProcess._(process, port, dataDir, model);
  }

  /// Runs `cli.js pair` against this gateway's data directory and returns the code.
  Future<String> pairingCode() async {
    final result = await Process.run(
      'node',
      [_cli.path, 'pair'],
      environment: {'DATA_DIR': dataDir.path},
    );
    final match = RegExp(r'Pairing code: ([0-9A-Z]{10})')
        .firstMatch(result.stdout as String);
    if (match == null) {
      throw StateError(
        'no code in CLI output: ${result.stdout}${result.stderr}',
      );
    }
    return match.group(1)!;
  }

  Future<void> stop() async {
    process.kill(ProcessSignal.sigterm);
    await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    await _model?.close(force: true);
    dataDir.deleteSync(recursive: true);
  }
}
