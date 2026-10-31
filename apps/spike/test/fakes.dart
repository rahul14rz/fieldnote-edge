import 'dart:async';
import 'dart:typed_data';

import 'package:fieldnote_spike/src/asr_benchmark.dart';
import 'package:fieldnote_spike/src/llm_benchmark.dart';
import 'package:fieldnote_spike/src/memory.dart';
import 'package:fieldnote_spike/src/timing.dart';

/// A clock that only moves when the test advances it.
class FakeClock {
  Duration current = Duration.zero;
  Duration call() => current;
  void advance(int ms) => current += Duration(milliseconds: ms);
}

class FakeProbe implements MemoryProbe {
  FakeProbe(this.readings);
  final List<MemoryReading> readings;
  int reads = 0;

  @override
  Future<MemoryReading> read() async => readings[reads++ % readings.length];
}

MemoryReading reading({
  int? anonymous,
  int? fileBacked,
  int? peak,
  int maxRss = 0,
}) => MemoryReading(
  anonymousBytes: anonymous,
  fileBackedBytes: fileBacked,
  anonymousPeakBytes: peak,
  maxRssBytes: maxRss,
);

/// Emits a scripted reply. Each chunk arrives after [msPerChunk] on [clock];
/// prefill takes [prefillMs]. Token count is one per whitespace-separated word.
class FakeEngine implements LlmEngine {
  FakeEngine(
    this.clock, {
    this.prefillMs = 100,
    this.msPerChunk = 20,
    this.reply = 'one two three four five',
  });
  final FakeClock clock;
  final int prefillMs;
  final int msPerChunk;
  final String reply;
  final sessions = <FakeSession>[];

  @override
  Future<LlmSession> newSession({required int maxOutputTokens}) async {
    final session = FakeSession(this, maxOutputTokens);
    sessions.add(session);
    return session;
  }
}

class FakeSession implements LlmSession {
  FakeSession(this.engine, this.maxOutputTokens);
  final FakeEngine engine;
  final int maxOutputTokens;
  final prompts = <String>[];
  bool closed = false;

  @override
  Future<void> addPrompt(String text) async => prompts.add(text);

  @override
  Stream<String> response() async* {
    engine.clock.advance(engine.prefillMs);
    final words = engine.reply.split(' ');
    for (var i = 0; i < words.length; i++) {
      if (i > 0) engine.clock.advance(engine.msPerChunk);
      yield i == 0 ? words[i] : ' ${words[i]}';
    }
  }

  @override
  Future<int> countTokens(String text) async =>
      text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

  @override
  Future<void> close() async => closed = true;
}

class FakeTranscriber implements Transcriber {
  final calls = <(int bytes, String language)>[];

  @override
  Future<String> transcribe(Uint8List pcm, {required String language}) async {
    calls.add((pcm.length, language));
    return ' window${calls.length} ';
  }
}

Now fakeNow(FakeClock clock) => clock.call;
