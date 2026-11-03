import 'package:flutter_test/flutter_test.dart';

/// Local storage fixtures can cross real and widget clocks. Drain both without
/// advancing a fake timeout past a still-pending platform acknowledgement.
Future<void> pumpUntilLocalCommit(
  WidgetTester tester,
  bool Function() acknowledged,
) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.pump();
    if (acknowledged()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(acknowledged(), isTrue, reason: 'Local commit was not acknowledged');
}
