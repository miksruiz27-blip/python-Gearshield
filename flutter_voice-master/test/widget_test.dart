import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_voice/main.dart';

void main() {
  testWidgets('Vocalis GearShield app loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const VocalisGearShieldApp());
    expect(find.byType(VocalisGearShieldApp), findsOneWidget);
  });
}
