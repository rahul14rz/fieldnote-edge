import 'package:fieldnote_mobile/src/jobs/job.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 1, 9);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));
  Job queued() => Job.queued(
    id: 'j1',
    kind: JobKind.transcribe,
    inputPath: 'rec/1.wav',
    now: t0,
  );
  const policy = RetryPolicy(
    maxAttempts: 3,
    baseDelay: Duration(seconds: 10),
    maxDelay: Duration(seconds: 25),
  );

  test('a job runs from queued to completed and records where it ran', () {
    final done = queued()
        .start(Placement.phone, at(1))
        .complete('out/1.txt', at(2));

    expect(done.state, JobState.completed);
    expect(done.placement, Placement.phone);
    expect(done.attempts, 1);
    expect(done.resultPath, 'out/1.txt');
    expect(isTerminal(done.state), isTrue);
  });

  test('transient failures back off exponentially up to the cap, then the job fails', () {
    var job = queued()
        .start(Placement.mac, at(0))
        .failTransient('mac unreachable', at(0), policy);
    expect(job.state, JobState.retryable);
    expect(job.notBefore, at(10));

    job = job
        .requeue(at(10))
        .start(Placement.mac, at(10))
        .failTransient('mac unreachable', at(10), policy);
    expect(job.notBefore, at(30));

    job = job
        .requeue(at(30))
        .start(Placement.mac, at(30))
        .failTransient('mac unreachable', at(30), policy);
    expect(job.state, JobState.failed);
    expect(job.lastError, contains('gave up after 3 attempts'));
  });

  test('the delay never exceeds the cap', () {
    expect(policy.delayAfter(1), const Duration(seconds: 10));
    expect(policy.delayAfter(2), const Duration(seconds: 20));
    expect(policy.delayAfter(3), const Duration(seconds: 25));
  });

  test('illegal transitions throw instead of changing state', () {
    expect(
      () => queued().complete('x', at(1)),
      throwsA(isA<IllegalTransition>()),
    );
    final done = queued().start(Placement.phone, at(1)).complete('x', at(2));
    expect(() => done.cancel(at(3)), throwsA(isA<IllegalTransition>()));
    expect(
      () => done.start(Placement.phone, at(3)),
      throwsA(isA<IllegalTransition>()),
    );
  });

  test('a job can be cancelled from every non-terminal state', () {
    final processing = queued().start(Placement.phone, at(1));
    final retryable = processing.failTransient('x', at(2), policy);
    for (final job in [queued(), processing, retryable]) {
      expect(
        job.cancel(at(5)).state,
        JobState.cancelled,
        reason: job.state.name,
      );
    }
  });

  test('survives a JSON round trip', () {
    final job = queued()
        .start(Placement.mac, at(1))
        .failTransient('timeout', at(2), policy);

    expect(Job.fromJson(job.toJson()).toJson(), job.toJson());
  });
}
