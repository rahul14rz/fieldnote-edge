import 'package:fieldnote_contracts/fieldnote_contracts.dart';
import 'package:fieldnote_gateway_client/fieldnote_gateway_client.dart';

import '../routing/routing_policy.dart';

sealed class MacResult {
  const MacResult();
}

class MacCompleted extends MacResult {
  const MacCompleted(this.summary);
  final MeetingSummary summary;
}

/// The Mac answered, but its answer is not a valid summary either.
class MacInvalidOutput extends MacResult {
  const MacInvalidOutput(this.reason);
  final String reason;
}

/// The Mac could not be reached or could not run the model. Retry later.
class MacUnavailable extends MacResult {
  const MacUnavailable(this.reason);
  final String reason;
}

/// What the job runner needs from the Mac.
abstract interface class MacGateway {
  Future<MacStatus> status();
  Future<MacResult> summarize({
    required String jobId,
    required String transcript,
    required String language,
  });
}

/// Uses a paired gateway through [GatewayClient]. Polls a submitted job until
/// it finishes or [timeout] passes.
class PairedMacGateway implements MacGateway {
  PairedMacGateway(
    this.client, {
    this.pollInterval = const Duration(seconds: 2),
    this.timeout = const Duration(minutes: 15),
  });

  final GatewayClient client;
  final Duration pollInterval;
  final Duration timeout;

  static const _codes = {'en', 'ta', 'ml', 'hi', 'ta-en', 'ml-en', 'hi-en'};

  @override
  Future<MacStatus> status() async {
    try {
      await client.health();
      return MacStatus.online;
    } on GatewayUnreachable {
      return MacStatus.pairedOffline;
    } on PinMismatch {
      return MacStatus.pairedOffline;
    }
  }

  @override
  Future<MacResult> summarize({
    required String jobId,
    required String transcript,
    required String language,
  }) async {
    try {
      var status = await client.submit(
        JobSubmission(
          jobId: jobId,
          kind: JobKind.SUMMARIZE,
          transcript: transcript,
          language: _codes.contains(language) ? language : null,
        ),
      );
      final deadline = DateTime.now().add(timeout);
      while (status.state == JobState.QUEUED ||
          status.state == JobState.PROCESSING) {
        if (DateTime.now().isAfter(deadline)) {
          return const MacUnavailable('the Mac did not finish in time');
        }
        await Future<void>.delayed(pollInterval);
        status = await client.status(jobId);
      }
      if (status.state == JobState.COMPLETED) {
        return MacCompleted(await client.summary(jobId));
      }
      final error = status.error;
      return error?.kind == JobErrorKind.INVALID_OUTPUT
          ? MacInvalidOutput(error?.message ?? 'invalid output')
          : MacUnavailable(error?.message ?? 'the Mac failed the job');
    } on GatewayUnreachable catch (e) {
      return MacUnavailable('$e');
    } on PinMismatch catch (e) {
      return MacUnavailable('$e');
    } on GatewayRejected catch (e) {
      return MacUnavailable('$e');
    }
  }
}
