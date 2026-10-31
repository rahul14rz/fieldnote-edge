import 'dart:io';

import 'package:fieldnote_mobile/src/jobs/job.dart';
import 'package:fieldnote_mobile/src/jobs/job_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File file;
  final t0 = DateTime.utc(2026, 11, 1, 9);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));
  Job newJob(String id, {int createdSecond = 0}) => Job.queued(
    id: id,
    kind: JobKind.summarize,
    inputPath: 't/$id.txt',
    now: at(createdSecond),
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jobs');
    file = File('${dir.path}/jobs.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('jobs survive closing and reopening the store', () async {
    final store = await JobStore.open(file, now: t0);
    await store.add(newJob('a'));
    await store.update(
      'a',
      (j) => j.start(Placement.phone, at(1)).complete('s/a.json', at(2)),
    );

    final reopened = await JobStore.open(file, now: at(10));

    expect(reopened.byId('a')!.state, JobState.completed);
    expect(reopened.byId('a')!.resultPath, 's/a.json');
  });

  test(
    'a job left processing by a crash becomes retryable on the next open',
    () async {
      final store = await JobStore.open(file, now: t0);
      await store.add(newJob('a'));
      await store.update('a', (j) => j.start(Placement.phone, at(1)));
      // The process dies here: no complete or fail is ever written.

      final reopened = await JobStore.open(file, now: at(60));

      expect(reopened.byId('a')!.state, JobState.retryable);
      expect(reopened.byId('a')!.lastError, contains('interrupted'));
      expect(
        (await JobStore.open(file, now: at(61))).byId('a')!.state,
        JobState.retryable,
      );
    },
  );

  test('adding the same id twice keeps one job', () async {
    final store = await JobStore.open(file, now: t0);
    await store.add(newJob('a'));
    await store.update('a', (j) => j.start(Placement.phone, at(1)));

    final again = await store.add(newJob('a'));

    expect(store.jobs, hasLength(1));
    expect(again.state, JobState.processing);
  });

  test('an illegal change stores nothing', () async {
    final store = await JobStore.open(file, now: t0);
    await store.add(newJob('a'));

    await expectLater(
      store.update('a', (j) => j.complete('x', at(1))),
      throwsA(isA<IllegalTransition>()),
    );

    expect(
      (await JobStore.open(file, now: at(2))).byId('a')!.state,
      JobState.queued,
    );
  });

  test('runs queued jobs oldest first and holds retryable jobs until their delay passes', () async {
    final store = await JobStore.open(
      file,
      now: t0,
      policy: const RetryPolicy(baseDelay: Duration(seconds: 30)),
    );
    await store.add(newJob('old', createdSecond: 0));
    await store.add(newJob('new', createdSecond: 5));
    await store.update(
      'old',
      (j) => j
          .start(Placement.mac, at(6))
          .failTransient('mac offline', at(6), store.policy),
    );

    expect((await store.nextRunnable(at(10)))!.id, 'new');
    await store.update(
      'new',
      (j) => j.start(Placement.phone, at(10)).complete('r', at(11)),
    );
    expect(await store.nextRunnable(at(20)), isNull);
    expect((await store.nextRunnable(at(36)))!.id, 'old');
  });

  test('refuses to open a corrupt file and leaves it untouched', () async {
    file.writeAsStringSync('{not json');

    await expectLater(
      JobStore.open(file, now: t0),
      throwsA(isA<JobStoreCorrupt>()),
    );

    expect(file.readAsStringSync(), '{not json');
  });
}
