import 'package:fieldnote_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home screen names the app and says nothing is built yet', (
    tester,
  ) async {
    await tester.pumpWidget(const FieldnoteApp());

    expect(find.text('Fieldnote'), findsOneWidget);
    expect(find.textContaining('not built yet'), findsOneWidget);
  });
}
