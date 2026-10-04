import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/domain/entities/retry_policy.dart';

void main() {
  test('backoff doubles from 30 s and stops at 15 min', () {
    expect(
      [for (var n = 1; n <= 7; n++) RetryPolicy.delayAfter(n)],
      const [
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 2),
        Duration(minutes: 4),
        Duration(minutes: 8),
        Duration(minutes: 15),
        Duration(minutes: 15),
      ],
    );
  });

  test('a huge failure count neither overflows nor exceeds the cap', () {
    expect(RetryPolicy.delayAfter(10000), RetryPolicy.maxDelay);
  });
}
