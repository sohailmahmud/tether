import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/app/queue_change_channel.dart';

void main() {
  test('an announced change reaches the listening isolate', () async {
    var changes = 0;
    final port = QueueChangeChannel.listen(() => changes++);
    addTearDown(port.close);

    QueueChangeChannel.announce();
    QueueChangeChannel.announce();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(changes, 2);
  });

  test('announcing with no app listening is harmless', () {
    final port = QueueChangeChannel.listen(() {})..close();
    // The mapping still points at a closed port; sending to it is a no-op.
    expect(QueueChangeChannel.announce, returnsNormally);
    expect(port, isNotNull);
  });
}
