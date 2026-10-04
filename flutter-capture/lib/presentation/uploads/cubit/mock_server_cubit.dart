import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/datasources/mock_server_settings.dart';

/// The mock server's behaviour, chosen on Pending Uploads to demonstrate the
/// failure paths. A demo control for the assessment's mock API, so it talks
/// to the data-layer setting directly rather than through a domain contract.
class MockServerCubit extends Cubit<MockServerMode> {
  MockServerCubit(this._settings) : super(MockServerMode.normal);

  final MockServerSettings _settings;

  Future<void> load() async {
    final mode = await _settings.read();
    if (!isClosed) emit(mode);
  }

  Future<void> select(MockServerMode mode) async {
    emit(mode);
    await _settings.write(mode);
  }
}
