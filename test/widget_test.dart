import 'package:flutter_test/flutter_test.dart';
import 'package:apertureflow/main.dart';
import 'package:apertureflow/repositories/booking_repository.dart';

void main() {
  testWidgets('ApertureFlowApp smoke test', (WidgetTester tester) async {
    // Build our app using the decoupled MockBookingRepository
    // This allows testing the widget tree UI without initializing real Firebase instances.
    await tester.pumpWidget(ApertureFlowApp(repository: MockBookingRepository()));

    // Wait for mock streams and initial render animations to complete
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Verify that the app header/title is displayed.
    expect(find.text('APERTUREFLOW'), findsOneWidget);
  });
}
