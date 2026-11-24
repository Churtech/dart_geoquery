import 'isolate_query_worker.dart';
import 'query_worker.dart';

/// Spawns the background isolate worker (native platforms).
Future<QueryWorker?> spawnQueryWorker({required int cacheCapacity}) =>
    IsolateQueryWorker.spawn(cacheCapacity: cacheCapacity);
