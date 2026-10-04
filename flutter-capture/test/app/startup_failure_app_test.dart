import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/app/startup_failure_app.dart';

void main() {
  testWidgets('explains that storage could not be opened', (tester) async {
    await tester.pumpWidget(const StartupFailureApp());

    expect(find.text("Can't open storage"), findsOneWidget);
    expect(find.textContaining('Free up some space'), findsOneWidget);
    expect(find.textContaining('Nothing has been deleted'), findsOneWidget);
  });
}
