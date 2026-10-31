/// A unit of work: transcribe one recording, or summarize one transcript.
enum JobKind { transcribe, summarize }

/// Where a job runs. The routing policy chooses it; see routing_policy.dart.
enum Placement { phone, mac }

/// The durable job states from docs/failure-handling.md.
enum JobState { queued, processing, completed, retryable, failed, cancelled }

/// Allowed state changes. Anything not listed throws [IllegalTransition].
const _allowed = <JobState, Set<JobState>>{
  JobState.queued: {JobState.processing, JobState.cancelled},
  JobState.processing: {
    JobState.completed,
    JobState.retryable,
    JobState.failed,
    JobState.cancelled,
  },
  JobState.retryable: {JobState.queued, JobState.failed, JobState.cancelled},
  JobState.completed: {},
  JobState.failed: {},
  JobState.cancelled: {},
};

bool isTerminal(JobState state) => _allowed[state]!.isEmpty;

class IllegalTransition implements Exception {
  const IllegalTransition(this.from, this.to);
  final JobState from;
  final JobState to;

  @override
  String toString() => 'IllegalTransition: ${from.name} -> ${to.name}';
}

class Job {
  const Job({
    required this.id,
    required this.kind,
    required this.inputPath,
    required this.state,
    required this.attempts,
    required this.createdAt,
    required this.updatedAt,
    this.placement,
    this.notBefore,
    this.resultPath,
    this.lastError,
  });

  factory Job.queued({
    required String id,
    required JobKind kind,
    required String inputPath,
    required DateTime now,
  }) => Job(
    id: id,
    kind: kind,
    inputPath: inputPath,
    state: JobState.queued,
    attempts: 0,
    createdAt: now,
    updatedAt: now,
  );

  final String id;
  final JobKind kind;

  /// Recording (transcribe) or transcript (summarize) on local storage.
  final String inputPath;
  final JobState state;

  /// Number of times the job entered [JobState.processing].
  final int attempts;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Where the current or last attempt ran.
  final Placement? placement;

  /// A retryable job is not picked up before this time.
  final DateTime? notBefore;
  final String? resultPath;
  final String? lastError;

  Job _to(
    JobState next,
    DateTime now, {
    Placement? placement,
    int? attempts,
    DateTime? notBefore,
    String? resultPath,
    String? lastError,
  }) {
    if (!_allowed[state]!.contains(next)) throw IllegalTransition(state, next);
    return Job(
      id: id,
      kind: kind,
      inputPath: inputPath,
      state: next,
      attempts: attempts ?? this.attempts,
      createdAt: createdAt,
      updatedAt: now,
      placement: placement ?? this.placement,
      notBefore: notBefore,
      resultPath: resultPath ?? this.resultPath,
      lastError: lastError ?? this.lastError,
    );
  }

  Job start(Placement where, DateTime now) =>
      _to(JobState.processing, now, placement: where, attempts: attempts + 1);

  Job complete(String result, DateTime now) =>
      _to(JobState.completed, now, resultPath: result);

  /// A failure that may go away: the Mac was unreachable, the app was killed.
  /// Becomes [JobState.failed] once [RetryPolicy.maxAttempts] is used up.
  Job failTransient(String reason, DateTime now, RetryPolicy policy) =>
      attempts >= policy.maxAttempts
      ? _to(
          JobState.failed,
          now,
          lastError: '$reason (gave up after $attempts attempts)',
        )
      : _to(
          JobState.retryable,
          now,
          lastError: reason,
          notBefore: now.add(policy.delayAfter(attempts)),
        );

  /// A failure a retry will not fix, such as unreadable audio.
  Job failPermanent(String reason, DateTime now) =>
      _to(JobState.failed, now, lastError: reason);

  Job cancel(DateTime now) => _to(JobState.cancelled, now);

  Job requeue(DateTime now) => _to(JobState.queued, now);

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'inputPath': inputPath,
    'state': state.name,
    'attempts': attempts,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'placement': placement?.name,
    'notBefore': notBefore?.toUtc().toIso8601String(),
    'resultPath': resultPath,
    'lastError': lastError,
  };

  factory Job.fromJson(Map<String, Object?> json) {
    DateTime? time(String key) =>
        json[key] == null ? null : DateTime.parse(json[key]! as String);
    return Job(
      id: json['id']! as String,
      kind: JobKind.values.byName(json['kind']! as String),
      inputPath: json['inputPath']! as String,
      state: JobState.values.byName(json['state']! as String),
      attempts: json['attempts']! as int,
      createdAt: time('createdAt')!,
      updatedAt: time('updatedAt')!,
      placement: json['placement'] == null
          ? null
          : Placement.values.byName(json['placement']! as String),
      notBefore: time('notBefore'),
      resultPath: json['resultPath'] as String?,
      lastError: json['lastError'] as String?,
    );
  }
}

/// Bounded retries with exponential backoff.
class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 5,
    this.baseDelay = const Duration(seconds: 30),
    this.maxDelay = const Duration(minutes: 30),
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  /// Delay before the next attempt after attempt number [attempt] (1-based) failed.
  Duration delayAfter(int attempt) {
    final delay = baseDelay * (1 << (attempt - 1).clamp(0, 20));
    return delay > maxDelay ? maxDelay : delay;
  }
}
