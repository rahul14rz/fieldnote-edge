import 'package:fieldnote_mobile/src/jobs/job.dart';
import 'package:fieldnote_mobile/src/routing/routing_policy.dart';
import 'package:flutter_test/flutter_test.dart';

RoutingInput input({
  JobKind kind = JobKind.summarize,
  int size = 100,
  bool ready = true,
  MacStatus mac = MacStatus.online,
  PhoneOutcome last = PhoneOutcome.notTried,
  bool allowMac = true,
  RoutingThresholds thresholds = const RoutingThresholds(
    maxPhoneTranscriptWords: 1000,
    maxPhoneAudioSeconds: 600,
  ),
}) => RoutingInput(
  kind: kind,
  inputSize: size,
  phoneModelReady: ready,
  mac: mac,
  lastPhoneOutcome: last,
  allowMac: allowMac,
  thresholds: thresholds,
);

/// Every combination of the inputs, with sizes on both sides of each limit.
Iterable<RoutingInput> everyInput() sync* {
  for (final kind in JobKind.values) {
    for (final size in [1, 1000, 1001, 100000]) {
      for (final ready in [true, false]) {
        for (final mac in MacStatus.values) {
          for (final last in PhoneOutcome.values) {
            for (final allowMac in [true, false]) {
              for (final thresholds in const [
                RoutingThresholds(),
                RoutingThresholds(
                  maxPhoneTranscriptWords: 1000,
                  maxPhoneAudioSeconds: 1000,
                ),
              ]) {
                yield input(
                  kind: kind,
                  size: size,
                  ready: ready,
                  mac: mac,
                  last: last,
                  allowMac: allowMac,
                  thresholds: thresholds,
                );
              }
            }
          }
        }
      }
    }
  }
}

void main() {
  group('decisions', () {
    test(
      'a job the phone can run stays on the phone, even with the Mac online',
      () {
        expect(route(input()), isA<RunOnPhone>());
      },
    );

    test('an oversized job goes to the Mac when it is online', () {
      expect(route(input(size: 1001)), isA<RunOnMac>());
      expect(
        route(input(kind: JobKind.transcribe, size: 601)),
        isA<RunOnMac>(),
      );
    });

    test('an oversized job runs on the phone when the Mac is not online, so the app stays useful', () {
      expect(
        route(input(size: 1001, mac: MacStatus.pairedOffline)),
        isA<RunOnPhone>(),
      );
      expect(
        route(input(size: 1001, mac: MacStatus.unpaired)),
        isA<RunOnPhone>(),
      );
    });

    test('with no limit set, size never moves a job off the phone', () {
      expect(
        route(input(size: 1 << 30, thresholds: const RoutingThresholds())),
        isA<RunOnPhone>(),
      );
    });

    test(
      'an invalid phone output escalates, waits, or stops depending on the Mac',
      () {
        expect(route(input(last: PhoneOutcome.invalidOutput)), isA<RunOnMac>());
        expect(
          route(
            input(
              last: PhoneOutcome.invalidOutput,
              mac: MacStatus.pairedOffline,
            ),
          ),
          isA<WaitForMac>(),
        );
        expect(
          route(
            input(last: PhoneOutcome.invalidOutput, mac: MacStatus.unpaired),
          ),
          isA<CannotRun>(),
        );
      },
    );

    test('a missing phone model needs the Mac', () {
      expect(route(input(ready: false)), isA<RunOnMac>());
      expect(
        route(input(ready: false, mac: MacStatus.unpaired)).reason,
        contains('no Mac is paired'),
      );
    });

    test('turning Mac use off keeps every job off the Mac and says why', () {
      final result = route(input(last: PhoneOutcome.error, allowMac: false));
      expect(result, isA<CannotRun>());
      expect(result.reason, contains('turned off'));
    });
  });

  group('invariants over every input combination', () {
    final all = everyInput().toList();

    test('the same input always gives the same route', () {
      for (final i in all) {
        final a = route(i);
        final b = route(i);
        expect((a.runtimeType, a.reason), (b.runtimeType, b.reason));
      }
    });

    test('nothing goes to, or waits for, the Mac when Mac use is off or no Mac is paired', () {
      for (final i in all.where(
        (i) => !i.allowMac || i.mac == MacStatus.unpaired,
      )) {
        expect(route(i), isNot(anyOf(isA<RunOnMac>(), isA<WaitForMac>())));
      }
    });

    test('a job is sent to the Mac only when the Mac is online', () {
      for (final i in all.where((i) => route(i) is RunOnMac)) {
        expect(i.mac, MacStatus.online);
      }
    });

    test('a first attempt with a ready phone model always runs somewhere', () {
      for (final i in all.where(
        (i) => i.phoneModelReady && i.lastPhoneOutcome == PhoneOutcome.notTried,
      )) {
        expect(route(i), anyOf(isA<RunOnPhone>(), isA<RunOnMac>()));
      }
    });
  });
}
