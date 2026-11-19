import 'package:dart_geoquery/dart_geoquery.dart' as gq;
import 'package:dart_geoquery_flutter/dart_geoquery_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const DartGeoQueryDemoApp());
}

class DartGeoQueryDemoApp extends StatelessWidget {
  const DartGeoQueryDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dart_geoquery Interactive Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final GlobalKey<GeoInteractiveLayerState> _interactiveKey = GlobalKey();
  final GeoSelectionController _selectionController = GeoSelectionController();

  gq.GeoQuery? _geoQuery;
  bool _isLoading = true;
  bool _isQuerying = false;
  bool _showTileGrid = true;

  gq.GeoFeature? _selectedFeature;
  int _lastQueryLatencyMs = 0;

  static const _remoteUrl =
      'https://r2-public.protomaps.com/protomaps-sample-datasets/nz-buildings-v3.pmtiles';

  // Wellington downtown area (-41.2775, 174.7701)
  static const _wellingtonCenter = LatLng(-41.2775, 174.7701);

  @override
  void initState() {
    super.initState();
    _loadGeoEngine();
  }

  Future<void> _loadGeoEngine() async {
    setState(() => _isLoading = true);
    _geoQuery?.close();

    try {
      final query = await gq.GeoQuery.open(
        _remoteUrl,
        useIsolate: true,
        cacheCapacity: 128,
      );
      if (mounted) {
        setState(() {
          _geoQuery = query;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening PMTiles archive: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _geoQuery?.close();
    _selectionController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _onMapTap(LatLng point) async {
    if (_geoQuery == null) return;
    setState(() => _isQuerying = true);

    final watch = Stopwatch()..start();
    final feature = await _interactiveKey.currentState?.handleTap(point);
    watch.stop();

    if (mounted) {
      setState(() {
        _isQuerying = false;
        _selectedFeature = feature;
        _lastQueryLatencyMs = watch.elapsedMilliseconds;
      });
    }
  }

  /// Navigates to a known building situated directly on a tile boundary
  void _jumpToBorderBuilding() {
    // Coordinate near tile border at zoom 14
    const borderBuilding = LatLng(-41.277496, 174.770091);
    _mapController.move(borderBuilding, 16.5);
    _onMapTap(borderBuilding);
  }

  List<Polyline> _buildTileGridPolylines() {
    if (!_showTileGrid) return const [];
    // Generate grid lines around Wellington for zoom level 14
    const z = 14;
    final (centerTileX, centerTileY) = gq.TileMath.latLngToTile(
      gq.LatLng(_wellingtonCenter.latitude, _wellingtonCenter.longitude),
      z,
    );

    final lines = <Polyline>[];
    for (var dx = -3; dx <= 3; dx++) {
      for (var dy = -3; dy <= 3; dy++) {
        final tx = centerTileX + dx;
        final ty = centerTileY + dy;

        final nw = gq.TileMath.tileCoordinatesToLatLng(
          tileX: tx,
          tileY: ty,
          zoom: z,
          localX: 0,
          localY: 0,
          extent: 4096,
        );
        final ne = gq.TileMath.tileCoordinatesToLatLng(
          tileX: tx,
          tileY: ty,
          zoom: z,
          localX: 4096,
          localY: 0,
          extent: 4096,
        );
        final se = gq.TileMath.tileCoordinatesToLatLng(
          tileX: tx,
          tileY: ty,
          zoom: z,
          localX: 4096,
          localY: 4096,
          extent: 4096,
        );
        final sw = gq.TileMath.tileCoordinatesToLatLng(
          tileX: tx,
          tileY: ty,
          zoom: z,
          localX: 0,
          localY: 4096,
          extent: 4096,
        );

        lines.add(
          Polyline(
            points: [
              LatLng(nw.latitude, nw.longitude),
              LatLng(ne.latitude, ne.longitude),
              LatLng(se.latitude, se.longitude),
              LatLng(sw.latitude, sw.longitude),
              LatLng(nw.latitude, nw.longitude),
            ],
            color: Colors.blue.withValues(alpha: 0.35),
            strokeWidth: 1.0,
            pattern: const StrokePattern.dotted(),
          ),
        );
      }
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('dart_geoquery + flutter_map'),
        actions: [
          IconButton(
            tooltip: 'Toggle Tile Grid Lines',
            icon: Icon(_showTileGrid ? Icons.grid_on : Icons.grid_off),
            onPressed: () => setState(() => _showTileGrid = !_showTileGrid),
          ),
          IconButton(
            tooltip: 'Go to Tile-Border Building',
            icon: const Icon(Icons.crop_free),
            onPressed: _jumpToBorderBuilding,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Connecting to PMTiles archive...'),
                ],
              ),
            )
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _wellingtonCenter,
                    initialZoom: 15.5,
                    maxZoom: 18.0,
                    minZoom: 10.0,
                    onTap: (_, point) => _onMapTap(point),
                  ),
                  children: [
                    // 1. Base Map Tile Layer (OpenStreetMap with custom verified headers)
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'co.churtech.dart_geoquery',
                      tileProvider: NetworkTileProvider(
                        headers: {
                          'User-Agent':
                              'DartGeoQueryDemo/1.0.0 (contact@churtech.com)',
                        },
                        cachingProvider: const DisabledMapCachingProvider(),
                      ),
                    ),

                    // 2. Debug Tile Grid Layer
                    if (_showTileGrid)
                      PolylineLayer(polylines: _buildTileGridPolylines()),

                    // 3. Interactive Vector Selection Layer
                    GeoInteractiveLayer(
                      key: _interactiveKey,
                      query: _geoQuery!,
                      layer: 'buildings',
                      idKey: 'building_i',
                      controller: _selectionController,
                      stitchBoundaries: true,
                      selectedStyle: (feature) => PolygonStyle(
                        color: Colors.teal.withValues(alpha: 0.45),
                        borderColor: Colors.teal.shade800,
                        borderStrokeWidth: 2.5,
                        label: feature['town_city'] != null
                            ? '${feature['suburb_loc'] ?? ''}'
                            : null,
                        labelStyle: const TextStyle(
                          color: Colors.black87,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                // Top Loading & Latency Pill
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isQuerying)
                          const Padding(
                            padding: EdgeInsets.only(right: 8.0),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          const Icon(Icons.flash_on,
                              color: Colors.amber, size: 18),
                        Text(
                          _isQuerying
                              ? 'Querying Isolate...'
                              : 'Last query: ${_lastQueryLatencyMs}ms',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Attribute Panel & Attribution
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selectedFeature != null)
                        Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          elevation: 6,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.apartment,
                                        color: Colors.teal),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Building ID: ${_selectedFeature!['building_i']}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () {
                                        _selectionController.clear();
                                        setState(() => _selectedFeature = null);
                                      },
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 6,
                                  children: [
                                    _buildChip('City',
                                        _selectedFeature!['town_city']),
                                    _buildChip('Suburb',
                                        _selectedFeature!['suburb_loc']),
                                    _buildChip('District',
                                        _selectedFeature!['territoria']),
                                    _buildChip(
                                        'Use', _selectedFeature!['use']),
                                    _buildChip(
                                      'Boundary Stitched',
                                      _selectedFeature!.touchesTileBoundary
                                          ? 'Yes'
                                          : 'Self-contained',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Legal & Data Attribution Bar
                      Container(
                        color: Colors.black.withValues(alpha: 0.75),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                '© OpenStreetMap contributors | Data © LINZ (New Zealand) | PMTiles by Protomaps',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildChip(String label, dynamic value) {
    if (value == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value.toString()),
          ],
        ),
      ),
    );
  }
}
