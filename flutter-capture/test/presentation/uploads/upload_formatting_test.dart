import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/presentation/uploads/upload_formatting.dart';

void main() {
  test('sizes use the largest sensible unit', () {
    expect(formatBytes(820), '820 B');
    expect(formatBytes(512 * 1024), '512 KB');
    expect(formatBytes((8.4 * 1024 * 1024).round()), '8.4 MB');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
  });
}
