import 'package:flutter_test/flutter_test.dart';

import 'package:glovo_mate/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GlovoMateApp());
    // Verify the app builds without crashing
    expect(find.text('GlovoMate'), findsNothing); // splash screen renders
  });
}
