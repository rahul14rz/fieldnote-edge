import 'package:fieldnote_gateway_client/fieldnote_gateway_client.dart';
import 'package:fieldnote_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(800, 2000);
    view.devicePixelRatio = 1;
  });
  tearDown(
    () => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .resetPhysicalSize(),
  );

  testWidgets(
    'record, stop, and see the transcript and summary made on the phone',
    (tester) async {
      final h = (await tester.runAsync(() => Harness.create()))!;
      await tester.runAsync(h.controller.start);
      await tester.pumpWidget(FieldnoteApp(controller: h.controller));
      expect(
        find.text('No recordings yet. Tap Record to start.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tamil and English'));
      await tester.pumpAndSettle();
      expect(find.text('Stop'), findsOneWidget);

      await tester.runAsync(() async {
        await h.controller.stopRecording();
        await h.controller.kick();
      });
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Summary: Done on this phone'),
        findsOneWidget,
      );
      expect(find.textContaining('Tamil and English'), findsOneWidget);

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(find.text('Arun: I will send the quote.'), findsOneWidget);
      expect(find.text('Priya (Procurement, Acme Foods)'), findsOneWidget);
      expect(
        find.text('• Send the revised quote. Owner: Arun. Due: 2026-11-06.'),
        findsOneWidget,
      );
      expect(
        find.text(
          '• Confirm the delivery address. Owner: not stated. Due: not stated.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'without a Mac, an invalid phone summary is shown as failed with the reason',
    (tester) async {
      final h = (await tester.runAsync(
        () => Harness.create(modelAnswer: 'not json'),
      ))!;
      await tester.runAsync(h.controller.start);
      await tester.pumpWidget(FieldnoteApp(controller: h.controller));

      await tester.runAsync(() async {
        await h.controller.startRecording('en');
        await h.controller.stopRecording();
        await h.controller.kick();
      });
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Summary: Failed: the phone output failed validation; no Mac is paired',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'asks for models before recording, and downloads them from Settings',
    (tester) async {
      final h = (await tester.runAsync(() => Harness.create()))!;
      h.models
        ..speechReady = false
        ..summaryReady = false;
      await tester.runAsync(h.controller.start);
      await tester.pumpWidget(FieldnoteApp(controller: h.controller));
      expect(
        find.text(
          'Download the on-device models in Settings before recording.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await h.controller.installModels();
      });
      await tester.pumpAndSettle();

      expect(h.models.installs, 2);
      expect(find.text('Speech (Whisper base): installed'), findsOneWidget);
    },
  );

  testWidgets('finds the Mac, pairs with the typed code, and can unpair', (
    tester,
  ) async {
    final h = (await tester.runAsync(() => Harness.create()))!;
    await tester.runAsync(h.controller.start);
    await tester.pumpWidget(FieldnoteApp(controller: h.controller));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Find my Mac'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fieldnote gateway on macbook'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Pairing code'),
      '44PY2-HRX7D',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(h.pairs.single.$1.toString(), '192.168.1.20:8787');
    expect(h.pairs.single.$2, '44PY2-HRX7D');
    expect(h.credentials.stored?.deviceId, startsWith('dev_'));
    expect(
      find.textContaining('Paired with 192.168.1.20:8787. Status: online.'),
      findsOneWidget,
    );

    await tester.runAsync(h.controller.unpair);
    await tester.pumpAndSettle();
    expect(h.credentials.stored, isNull);
    expect(find.text('Find my Mac'), findsOneWidget);
  });

  testWidgets('shows a clear message when the Mac rejects the code', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => Harness.create(pairError: const GatewayRejected(401, 'nope')),
    ))!;
    await tester.runAsync(h.controller.start);
    await tester.pumpWidget(FieldnoteApp(controller: h.controller));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Mac address'),
      '192.168.1.20',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Pairing code'),
      'WRONGCODE0',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The Mac rejected the code. Run "pair" again on the Mac for a new one.',
      ),
      findsOneWidget,
    );
    expect(h.credentials.stored, isNull);
  });
}
