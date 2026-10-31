import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'job.dart';

/// Thrown when the jobs file exists but can't be read. The store does not
/// overwrite it, so no job is lost silently.
class JobStoreCorrupt implements Exception {
  const JobStoreCorrupt(this.path, this.cause);
  final String path;
  final Object cause;

  @override
  String toString() => 'JobStoreCorrupt: $path ($cause)';
}

/// Jobs persisted as one JSON file.
///
/// Every change is written to a temporary file and renamed over the old one,
/// so a crash leaves either the old or the new file, never a partial one.
/// Writes are serialized; the store is the only writer of its file.
class JobStore {
  JobStore._(this._file, this._jobs, this._policy);

  final File _file;
  final Map<String, Job> _jobs;
  final RetryPolicy _policy;
  Future<void> _lastWrite = Future.value();

  RetryPolicy get policy => _policy;

  /// Loads [file], creating it if missing. Jobs left in
  /// [JobState.processing] by an earlier run become retryable, and the change
  /// is persisted before this returns.
  static Future<JobStore> open(
    File file, {
    required DateTime now,
    RetryPolicy policy = const RetryPolicy(),
  }) async {
    final jobs = <String, Job>{};
    if (file.existsSync()) {
      try {
        final list =
            (jsonDecode(await file.readAsString())
                    as Map<String, Object?>)['jobs']!
                as List<Object?>;
        for (final raw in list) {
          final job = Job.fromJson(raw! as Map<String, Object?>);
          jobs[job.id] = job;
        }
      } on Object catch (error) {
        throw JobStoreCorrupt(file.path, error);
      }
    }
    final store = JobStore._(file, jobs, policy);
    var recovered = false;
    for (final job in jobs.values.toList()) {
      if (job.state == JobState.processing) {
        jobs[job.id] = job.failTransient(
          'interrupted: the app stopped while the job was running',
          now,
          policy,
        );
        recovered = true;
      }
    }
    if (recovered || !file.existsSync()) await store._persist();
    return store;
  }

  List<Job> get jobs => List.unmodifiable(
    _jobs.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
  );

  Job? byId(String id) => _jobs[id];

  /// Adds [job] and persists it. Adding an id that already exists returns the
  /// stored job unchanged, so a repeated submit creates no duplicate.
  Future<Job> add(Job job) async {
    final existing = _jobs[job.id];
    if (existing != null) return existing;
    _jobs[job.id] = job;
    await _persist();
    return job;
  }

  /// Applies [change] to job [id] and persists the result before returning it.
  /// If [change] throws, for example [IllegalTransition], nothing is stored.
  Future<Job> update(String id, Job Function(Job job) change) async {
    final current = _jobs[id];
    if (current == null) throw ArgumentError.value(id, 'id', 'no such job');
    final next = change(current);
    _jobs[id] = next;
    await _persist();
    return next;
  }

  /// Moves retryable jobs whose delay has passed back to queued, then returns
  /// the oldest queued job, or null.
  Future<Job?> nextRunnable(DateTime now) async {
    for (final job in jobs) {
      if (job.state == JobState.retryable &&
          !(job.notBefore?.isAfter(now) ?? false)) {
        await update(job.id, (j) => j.requeue(now));
      }
    }
    for (final job in jobs) {
      if (job.state == JobState.queued) return job;
    }
    return null;
  }

  Future<void> _persist() {
    final snapshot = jsonEncode({
      'version': 1,
      'jobs': [for (final j in jobs) j.toJson()],
    });
    return _lastWrite = _lastWrite.then((_) async {
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(snapshot, flush: true);
      await temp.rename(_file.path);
    });
  }
}
