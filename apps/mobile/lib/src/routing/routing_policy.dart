import '../jobs/job.dart';

/// Whether the Mac gateway can take a job right now.
enum MacStatus { unpaired, pairedOffline, online }

/// Size limits above which a job goes to the Mac when it can. A null limit
/// is not set: Milestone 0 has not measured what the phone can handle, and
/// no limit is invented before it does (ADR 0001).
class RoutingThresholds {
  const RoutingThresholds({
    this.maxPhoneAudioSeconds,
    this.maxPhoneTranscriptWords,
  });

  final int? maxPhoneAudioSeconds;
  final int? maxPhoneTranscriptWords;
}

class RoutingInput {
  const RoutingInput({
    required this.kind,
    required this.inputSize,
    required this.phoneModelReady,
    required this.mac,
    required this.lastPhoneOutcome,
    required this.allowMac,
    this.thresholds = const RoutingThresholds(),
  });

  final JobKind kind;

  /// Audio seconds for [JobKind.transcribe], transcript words for
  /// [JobKind.summarize].
  final int inputSize;

  /// The model this job kind needs is installed and loadable on the phone.
  final bool phoneModelReady;
  final MacStatus mac;
  final PhoneOutcome lastPhoneOutcome;

  /// The user's setting. When false the job never leaves the phone.
  final bool allowMac;
  final RoutingThresholds thresholds;
}

/// Where to run a job, and why. [reason] is shown to the user and logged.
sealed class Route {
  const Route(this.reason);
  final String reason;
}

class RunOnPhone extends Route {
  const RunOnPhone(super.reason);
}

class RunOnMac extends Route {
  const RunOnMac(super.reason);
}

/// Keep the job retryable until the paired Mac comes back.
class WaitForMac extends Route {
  const WaitForMac(super.reason);
}

/// The job can't run anywhere with the current setup.
class CannotRun extends Route {
  const CannotRun(super.reason);
}

/// Decides where a job runs. Deterministic: the same input always gives the
/// same route, and nothing outside [input] is read (ADR 0002). Historical
/// accuracy is deliberately not an input.
Route route(RoutingInput input) {
  final macUsable = input.allowMac && input.mac != MacStatus.unpaired;

  Route needsMac(String why) => switch ((macUsable, input.mac)) {
    (true, MacStatus.online) => RunOnMac(why),
    (true, _) => WaitForMac('$why; waiting for the paired Mac'),
    _ => CannotRun(
      input.allowMac
          ? '$why; no Mac is paired'
          : '$why; sending jobs to the Mac is turned off',
    ),
  };

  if (!input.phoneModelReady) {
    return needsMac('the phone model is not installed');
  }

  switch (input.lastPhoneOutcome) {
    case PhoneOutcome.invalidOutput:
      return needsMac('the phone output failed validation');
    case PhoneOutcome.error:
      return needsMac('the phone run failed');
    case PhoneOutcome.notTried:
      break;
  }

  final limit = switch (input.kind) {
    JobKind.transcribe => input.thresholds.maxPhoneAudioSeconds,
    JobKind.summarize => input.thresholds.maxPhoneTranscriptWords,
  };
  if (limit != null &&
      input.inputSize > limit &&
      macUsable &&
      input.mac == MacStatus.online) {
    return RunOnMac(
      'input size ${input.inputSize} is over the phone limit $limit',
    );
  }
  return const RunOnPhone('the phone can run it');
}
