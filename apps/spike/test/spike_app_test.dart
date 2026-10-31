import 'dart:io';

import 'package:fieldnote_spike/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows the work directory, runs the config, and reports where results went',
    (tester) async {
      Directory? ranIn;
      await tester.pumpWidget(
        SpikeApp(
          workDir: () async => Directory('/data/spike'),
          run: (dir, {required log}) async {
            ranIn = dir;
            log('run en-short #1');
            return File('/data/spike/results/x.json');
          },
        ),
      );
      await tester.pump();

      expect(find.text('Work directory: /data/spike'), findsOneWidget);
      await tester.tap(find.text('Run spike_config.json'));
      await tester.pumpAndSettle();

      expect(ranIn?.path, '/data/spike');
      expect(find.text('run en-short #1'), findsOneWidget);
      expect(
        find.text('DONE wrote /data/spike/results/x.json'),
        findsOneWidget,
      );
    },
  );

  testWidgets('shows a failure instead of crashing', (tester) async {
    await tester.pumpWidget(
      SpikeApp(
        workDir: () async => Directory('/data/spike'),
        run: (dir, {required log}) async => throw const FileSystemException(
          'no spike_config.json in the work directory',
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Run spike_config.json'));
    await tester.pumpAndSettle();

    expect(find.textContaining('FAILED'), findsOneWidget);
  });
}
