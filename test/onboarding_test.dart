import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranepa_sync/screens/onboarding_screen.dart';

void main() {
  testWidgets('стартовый экран ссылается на открытый код', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(home: OnboardingScreen(onLogin: () {})),
    );
    expect(
      find.text(
        'Неофициальное приложение\nс открытым кодом',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });
}
