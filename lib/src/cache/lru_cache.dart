import 'dart:collection';

/// A lightweight, generic Least Recently Used (LRU) in-memory cache.
class LruCache<K, V> {
  final int capacity;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  LruCache({this.capacity = 64})
      : assert(capacity > 0, 'Capacity must be greater than zero');

  /// Gets the value associated with [key] and marks it as most recently used.
  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value;
    }
    return value;
  }

  /// Adds or updates [key] with [value]. Evicts oldest entry if capacity is exceeded.
  void put(K key, V value) {
    _map.remove(key);
    if (_map.length >= capacity) {
      final oldestKey = _map.keys.first;
      _map.remove(oldestKey);
    }
    _map[key] = value;
  }

  /// Checks if [key] is present in cache.
  bool containsKey(K key) => _map.containsKey(key);

  /// Clears all entries from cache.
  void clear() => _map.clear();

  /// Current number of items in cache.
  int get length => _map.length;
}
