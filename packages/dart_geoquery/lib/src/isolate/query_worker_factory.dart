/// Creates the background [QueryWorker] for the current platform.
///
/// Native platforms spawn an isolate; on web (no `dart:isolate` support)
/// this resolves to `null` and queries run on the calling isolate.
library;

export 'query_worker_factory_stub.dart'
    if (dart.library.isolate) 'query_worker_factory_isolate.dart';
