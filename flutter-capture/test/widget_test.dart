import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/app/app.dart';

void main() {
  testWidgets('app shell renders its title', (tester) async {
    await tester.pumpWidget(const TetherCaptureApp());

    expect(find.text(TetherCaptureApp.title), findsOneWidget);
  });
}
