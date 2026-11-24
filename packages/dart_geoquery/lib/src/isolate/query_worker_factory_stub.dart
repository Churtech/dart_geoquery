import 'query_worker.dart';

/// Web fallback: isolates are unavailable, so no background worker exists.
Future<QueryWorker?> spawnQueryWorker({required int cacheCapacity}) async =>
    null;
