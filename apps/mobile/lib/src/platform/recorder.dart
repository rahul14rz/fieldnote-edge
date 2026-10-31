import 'package:record/record.dart';

import '../app/app_controller.dart';

/// Records 16 kHz mono 16-bit WAV, the only format the speech package reads.
class WavRecorder implements Recorder {
  final _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
    ),
    path: path,
  );

  /// Returns the path of the finished file.
  @override
  Future<String?> stop() => _recorder.stop();

  Future<void> dispose() => _recorder.dispose();
}
