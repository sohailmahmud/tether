import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Logs every BLoC/Cubit state change and error in debug builds, so queue and
/// camera state transitions can be traced without a debugger.
///
/// Release builds log nothing: states may carry file paths, which should not
/// end up in device logs.
class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    if (kDebugMode) {
      developer.log(
        '${change.currentState} -> ${change.nextState}',
        name: bloc.runtimeType.toString(),
      );
    }
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      developer.log(
        'Unhandled error',
        name: bloc.runtimeType.toString(),
        error: error,
        stackTrace: stackTrace,
      );
    }
    super.onError(bloc, error, stackTrace);
  }
}
