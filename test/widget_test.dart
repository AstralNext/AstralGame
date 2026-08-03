import 'package:flutter_test/flutter_test.dart';

import 'package:astral_game/ui/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AstralGameApp());
    expect(find.text('仪表盘'), findsOneWidget);
  });
}
