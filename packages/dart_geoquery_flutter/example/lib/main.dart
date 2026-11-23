import 'dart:math' as math;
import 'package:dart_geoquery/dart_geoquery.dart' as gq;
import 'package:dart_geoquery_flutter/dart_geoquery_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const DartGeoQueryDemoApp());
}

enum DemoRegion {
  bogota(
    nameEs: 'Bogotá (Local PMTiles)',
    nameEn: 'Bogotá (Local PMTiles)',
    flag: '🇨🇴',
    center: LatLng(4.6728, -74.0538),
    borderBuilding: LatLng(4.67317, -74.05336),
    attributionEs:
        '© Contribuidores de OpenStreetMap | PMTiles por Protomaps (Bogotá, Colombia)',
    attributionEn:
        '© OpenStreetMap contributors | PMTiles by Protomaps (Bogotá, Colombia)',
  ),
  wellington(
    nameEs: 'Wellington (Remoto PMTiles)',
    nameEn: 'Wellington (Remote PMTiles)',
    flag: '🇳🇿',
    center: LatLng(-41.2775, 174.7701),
    borderBuilding: LatLng(-41.277496, 174.770091),
    attributionEs:
        '© Contribuidores de OpenStreetMap | Datos © LINZ (Nueva Zelanda) | PMTiles por Protomaps',
    attributionEn:
        '© OpenStreetMap contributors | Data © LINZ (New Zealand) | PMTiles by Protomaps',
  );

  final String nameEs;
  final String nameEn;
  final String flag;
  final LatLng center;
  final LatLng borderBuilding;
  final String attributionEs;
  final String attributionEn;

  const DemoRegion({
    required this.nameEs,
    required this.nameEn,
    required this.flag,
    required this.center,
    required this.borderBuilding,
    required this.attributionEs,
    required this.attributionEn,
  });

  String name(bool isEs) => isEs ? nameEs : nameEn;
  String attribution(bool isEs) => isEs ? attributionEs : attributionEn;
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

  /// Keeps the FlutterMap state (tiles, controller) across globe transitions.
  final GlobalKey _flutterMapKey = GlobalKey();
  final GlobalKey<GeoInteractiveLayerState> _interactiveKey = GlobalKey();
  final GeoSelectionController _selectionController =
      GeoSelectionController(multiSelect: false);

  DemoRegion _currentRegion = DemoRegion.bogota;
  gq.GeoQuery? _geoQuery;
  bool _isLoading = true;
  bool _isQuerying = false;
  bool _showTileGrid = true;
  bool _isSpanish = true;
  double _currentZoom = 15.5;

  gq.GeoFeature? _selectedFeature;
  LatLng? _lastTappedPoint;
  int _lastQueryLatencyMs = 0;
  bool _showRawJson = false;

  LatLng? _myLocation;
  double? _myAccuracyMeters;
  bool _isLocating = false;

  static const _remoteUrl =
      'https://r2-public.protomaps.com/protomaps-sample-datasets/nz-buildings-v3.pmtiles';

  /// Globe interpolation factor (1.0 = circular 3D globe at zoom <= 1.5, 0.0 = flat 2D at zoom >= 5.0)
  double get _globeFactor {
    return (1.0 - ((_currentZoom - 1.5) / (5.0 - 1.5))).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _loadGeoEngine(_currentRegion);
  }

  Future<void> _loadGeoEngine(DemoRegion region) async {
    setState(() {
      _currentRegion = region;
      _isLoading = true;
      _selectedFeature = null;
    });
    _geoQuery?.close();
    _selectionController.clear();

    try {
      final gq.GeoQuery query;
      if (region == DemoRegion.bogota) {
        final byteData = await rootBundle.load('assets/bogota.pmtiles');
        final bytes = byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
        query = await gq.GeoQuery.fromBytes(
          bytes,
          useIsolate: true,
          cacheCapacity: 128,
        );
      } else {
        query = await gq.GeoQuery.open(
          _remoteUrl,
          useIsolate: true,
          cacheCapacity: 128,
        );
      }

      if (mounted) {
        setState(() {
          _geoQuery = query;
          _isLoading = false;
          _currentZoom = 15.5;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              _mapController.move(region.center, 15.5);
            } catch (_) {}
          }
        });
      }
    } catch (e, stack) {
      debugPrint('Error loading PMTiles: $e\n$stack');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isSpanish
                ? 'Error al abrir PMTiles: $e'
                : 'Error loading PMTiles: $e'),
          ),
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
    setState(() {
      _isQuerying = true;
      _lastTappedPoint = point;
    });

    final watch = Stopwatch()..start();
    final feature = await _interactiveKey.currentState?.handleTap(point);
    watch.stop();

    if (mounted) {
      setState(() {
        _isQuerying = false;
        _selectedFeature = feature;
        _lastQueryLatencyMs = watch.elapsedMilliseconds;
        _showRawJson = false;
      });
      if (feature == null) {
        _selectionController.clear();
      }
    }
  }

  void _jumpToBorderBuilding() {
    _mapController.move(_currentRegion.borderBuilding, 16.5);
    _onMapTap(_currentRegion.borderBuilding);
  }

  Future<void> _locateUser() async {
    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _isLocating = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isSpanish
                  ? 'Por favor activá el servicio de ubicación/GPS'
                  : 'Please enable location services/GPS'),
            ),
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() => _isLocating = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_isSpanish
                    ? 'Permiso de ubicación denegado'
                    : 'Location permission denied'),
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _isLocating = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isSpanish
                  ? 'Los permisos de ubicación están deshabilitados en ajustes'
                  : 'Location permissions are permanently denied in settings'),
            ),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      final userPoint = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _myLocation = userPoint;
          _myAccuracyMeters = pos.accuracy;
          _isLocating = false;
          _currentZoom = 16.5;
        });
        _mapController.move(userPoint, 16.5);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLocating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isSpanish
                ? 'Error al obtener ubicación: $e'
                : 'Error obtaining location: $e'),
          ),
        );
      }
    }
  }

  /// Planar footprint area in m². Signed ring areas are summed so holes
  /// (opposite winding) subtract and stitched tile pieces add up.
  double _calculateArea(List<List<gq.LatLng>> coordinates) {
    if (coordinates.isEmpty || coordinates.first.length < 3) return 0.0;

    final centerLat = coordinates.first.first.latitude;
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLng =
        111320.0 * math.cos(centerLat * math.pi / 180.0);

    double total = 0.0;
    for (final ring in coordinates) {
      if (ring.length < 3) continue;
      double area = 0.0;
      for (var i = 0; i < ring.length; i++) {
        final j = (i + 1) % ring.length;
        final xi = ring[i].longitude * metersPerDegreeLng;
        final yi = ring[i].latitude * metersPerDegreeLat;
        final xj = ring[j].longitude * metersPerDegreeLng;
        final yj = ring[j].latitude * metersPerDegreeLat;
        area += (xi * yj) - (xj * yi);
      }
      total += area / 2.0;
    }
    return total.abs();
  }

  /// Length in meters of a closed [ring].
  double _calculatePerimeter(List<gq.LatLng> ring) {
    if (ring.length < 2) return 0.0;
    double length = 0.0;
    for (var i = 0; i < ring.length; i++) {
      length += ring[i].distanceTo(ring[(i + 1) % ring.length]);
    }
    return length;
  }

  /// Building height in meters, or `null` when the data has none.
  double? _heightOf(gq.GeoFeature feature) {
    final raw = feature['height'];
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    return value != null && value > 0 ? value : null;
  }

  String _formatMeters(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  static const _kindNames = <String, (String es, String en)>{
    'building': ('Edificio', 'Building'),
    'building_part': ('Parte de edificio', 'Building part'),
    'residential': ('Residencial', 'Residential'),
    'apartments': ('Apartamentos', 'Apartments'),
    'house': ('Casa', 'House'),
    'commercial': ('Comercial', 'Commercial'),
    'retail': ('Comercio', 'Retail'),
    'office': ('Oficinas', 'Office'),
    'industrial': ('Industrial', 'Industrial'),
    'school': ('Colegio', 'School'),
    'university': ('Universidad', 'University'),
    'hospital': ('Hospital', 'Hospital'),
    'church': ('Iglesia', 'Church'),
  };

  /// Readable name for a feature `kind` value.
  String _kindLabel(dynamic kind) {
    final raw = (kind ?? 'building').toString().trim();
    final known = _kindNames[raw.toLowerCase()];
    if (known != null) return _isSpanish ? known.$1 : known.$2;
    if (raw.isEmpty) return _isSpanish ? 'Edificio' : 'Building';
    final words = raw.replaceAll('_', ' ');
    return words[0].toUpperCase() + words.substring(1);
  }

  List<Polyline> _buildTileGridPolylines() {
    if (!_showTileGrid) return const [];
    const z = 14;
    final (centerTileX, centerTileY) = gq.TileMath.latLngToTile(
      gq.LatLng(_currentRegion.center.latitude, _currentRegion.center.longitude),
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
    final globeFactor = _globeFactor;
    final screenSize = MediaQuery.of(context).size;
    final globeDiameter =
        math.min(screenSize.width - 32.0, screenSize.height * 0.55);
    final targetWidth = screenSize.width -
        (globeFactor * (screenSize.width - globeDiameter));
    final targetHeight = screenSize.height -
        (globeFactor * (screenSize.height - globeDiameter));
    final targetRadius = globeFactor * (globeDiameter / 2.0);

    return Scaffold(
      backgroundColor: const Color(0xFF070B12), // Deep cosmic space
      appBar: AppBar(
        title: Text(_isSpanish ? 'dart_geoquery' : 'dart_geoquery'),
        actions: [
          // Language Switcher (ES / EN)
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(40, 36),
            ),
            onPressed: () => setState(() => _isSpanish = !_isSpanish),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.language, size: 16),
                const SizedBox(width: 4),
                Text(
                  _isSpanish ? 'ES' : 'EN',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Region Switcher
          PopupMenuButton<DemoRegion>(
            initialValue: _currentRegion,
            tooltip: _isSpanish ? 'Cambiar región' : 'Switch Map Dataset',
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_currentRegion.flag,
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
            onSelected: (region) {
              if (region != _currentRegion) {
                _loadGeoEngine(region);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: DemoRegion.bogota,
                child: Row(
                  children: [
                    const Text('🇨🇴', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text(DemoRegion.bogota.name(_isSpanish)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: DemoRegion.wellington,
                child: Row(
                  children: [
                    const Text('🇳🇿', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text(DemoRegion.wellington.name(_isSpanish)),
                  ],
                ),
              ),
            ],
          ),

          // Tile Grid Toggle
          IconButton(
            tooltip: _isSpanish ? 'Mostrar cuadrícula' : 'Show grid',
            icon: Icon(_showTileGrid ? Icons.grid_on : Icons.grid_off),
            onPressed: () => setState(() => _showTileGrid = !_showTileGrid),
          ),

          // Sample Building
          IconButton(
            tooltip: _isSpanish
                ? 'Ver un edificio entre zonas'
                : 'Show a building across zones',
            icon: const Icon(Icons.crop_free),
            onPressed: _jumpToBorderBuilding,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.teal),
                  const SizedBox(height: 16),
                  Text(
                    _isSpanish
                        ? 'Cargando ${_currentRegion.nameEs}...'
                        : 'Loading ${_currentRegion.nameEn}...',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                // 1. Globe 3D / Planar Map Dynamic Container
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    width: targetWidth,
                    height: targetHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(targetRadius),
                      boxShadow: globeFactor > 0.05
                          ? [
                              // Atmosphere rim (tight, bright)
                              BoxShadow(
                                color: const Color(0xFF7DD3FC).withValues(
                                  alpha: 0.5 * globeFactor,
                                ),
                                blurRadius: 14 * globeFactor,
                                spreadRadius: 1.5 * globeFactor,
                              ),
                              // Atmosphere glow
                              BoxShadow(
                                color: Colors.cyanAccent.withValues(
                                  alpha: 0.35 * globeFactor,
                                ),
                                blurRadius: 40 * globeFactor,
                                spreadRadius: 4 * globeFactor,
                              ),
                              // Outer space shadow
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: 0.7 * globeFactor,
                                ),
                                blurRadius: 35 * globeFactor,
                                spreadRadius: 2 * globeFactor,
                              ),
                            ]
                          : null,
                    ),
                    // Always clip: toggling clipBehavior inserts/removes a
                    // ClipPath and would remount FlutterMap.
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Tilt the map content only, scaled up so the tilted
                        // edges never reveal the background inside the clip.
                        Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001) // 3D Perspective
                            ..rotateX(0.12 * globeFactor) // Subtle tilt
                            ..scaleByDouble(
                              1 + 0.08 * globeFactor,
                              1 + 0.08 * globeFactor,
                              1,
                              1,
                            ),
                          child: Stack(
                            children: [
                              FlutterMap(
                                key: _flutterMapKey,
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: _currentRegion.center,
                                  initialZoom: _currentZoom,
                                  maxZoom: 18.0,
                                  minZoom: 1.5, // Total zoom out enabled
                                  onPositionChanged: (camera, hasGesture) {
                                    if ((camera.zoom - _currentZoom).abs() >
                                        0.05) {
                                      setState(() => _currentZoom = camera.zoom);
                                    }
                                  },
                                  onTap: (_, point) => _onMapTap(point),
                                ),
                                children: [
                                  // 1.1 Base Map Raster Layer
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName:
                                        'co.churtech.dart_geoquery',
                                    tileProvider: NetworkTileProvider(
                                      headers: {
                                        'User-Agent':
                                            'DartGeoQueryDemo/1.0.0 (contact@churtech.com)',
                                      },
                                      cachingProvider:
                                          const DisabledMapCachingProvider(),
                                    ),
                                  ),

                                  // 1.2 Debug Tile Grid Layer
                                  if (_showTileGrid)
                                    PolylineLayer(
                                      polylines: _buildTileGridPolylines(),
                                    ),

                                  // 1.3 User GPS Location Layer (Pulsing Dot + Accuracy Halo)
                                  if (_myLocation != null) ...[
                                    if (_myAccuracyMeters != null &&
                                        _myAccuracyMeters! > 5)
                                      CircleLayer(
                                        circles: [
                                          CircleMarker(
                                            point: _myLocation!,
                                            radius: (_myAccuracyMeters! * 0.75)
                                                .clamp(12.0, 100.0),
                                            useRadiusInMeter: false,
                                            color:
                                                Colors.blue.withValues(alpha: 0.12),
                                            borderColor: Colors.blueAccent
                                                .withValues(alpha: 0.35),
                                            borderStrokeWidth: 1.5,
                                          ),
                                        ],
                                      ),
                                    MarkerLayer(
                                      markers: [
                                        Marker(
                                          point: _myLocation!,
                                          width: 44,
                                          height: 44,
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: Colors.blue
                                                      .withValues(alpha: 0.25),
                                                ),
                                              ),
                                              Container(
                                                width: 16,
                                                height: 16,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: Colors.blue.shade600,
                                                  border: Border.all(
                                                      color: Colors.white,
                                                      width: 3),
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Colors.black38,
                                                      blurRadius: 6,
                                                      offset: Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],

                                  // 1.4 Interactive Vector Selection Layer
                                  if (_geoQuery != null)
                                    GeoInteractiveLayer(
                                      key: _interactiveKey,
                                      query: _geoQuery!,
                                      layer: 'buildings',
                                      idKey: _currentRegion ==
                                              DemoRegion.wellington
                                          ? 'building_i'
                                          : 'id',
                                      controller: _selectionController,
                                      stitchBoundaries: true,
                                      extrude: true,
                                      heightKey: 'height',
                                      selectedStyle: (feature) => PolygonStyle(
                                        color: Colors.teal
                                            .withValues(alpha: 0.45),
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
                            ],
                          ),
                        ),

                        // 1.5 Sphere lighting inside the same clip: highlight
                        // top-left, limb darkening on the real edge.
                        // Always mounted so the tree shape never changes with
                        // globeFactor; it paints nothing when flat.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: _GlobeLighting(
                              factor: globeFactor,
                              radius: targetRadius,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Top Response & Zoom Pill
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.teal,
                              ),
                            ),
                          )
                        else
                          const Icon(Icons.flash_on,
                              color: Colors.amber, size: 18),
                        Text(
                          _isQuerying
                              ? (_isSpanish
                                  ? 'Consultando Isolate...'
                                  : 'Querying Isolate...')
                              : '${_isSpanish ? 'Respuesta' : 'Response'}: $_lastQueryLatencyMs ms | Zoom: ${_currentZoom.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Right Vertical Quick Controls (Zoom +, Zoom -, Globe 3D, City Focus)
                Positioned(
                  right: 16,
                  top: 80,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'zoom_in',
                        tooltip: _isSpanish ? 'Acercar (+)' : 'Zoom In (+)',
                        onPressed: () {
                          final target = (_currentZoom + 1.5).clamp(1.5, 18.0);
                          _mapController.move(
                              _mapController.camera.center, target);
                        },
                        child: const Icon(Icons.add),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'zoom_out',
                        tooltip: _isSpanish ? 'Alejar (-)' : 'Zoom Out (-)',
                        onPressed: () {
                          final target = (_currentZoom - 1.5).clamp(1.5, 18.0);
                          _mapController.move(
                              _mapController.camera.center, target);
                        },
                        child: const Icon(Icons.remove),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'my_location',
                        tooltip: _isSpanish
                            ? 'Mi Ubicación GPS'
                            : 'My GPS Location',
                        backgroundColor: _myLocation != null
                            ? Colors.blue.shade50
                            : Colors.white,
                        onPressed: _isLocating ? null : _locateUser,
                        child: _isLocating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.blue,
                                ),
                              )
                            : Icon(
                                Icons.my_location,
                                color: _myLocation != null
                                    ? Colors.blue.shade700
                                    : Colors.black87,
                              ),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'globe_view',
                        tooltip: _isSpanish ? 'Vista Globo 3D' : '3D Globe View',
                        backgroundColor: Colors.teal.shade50,
                        onPressed: () {
                          _mapController.move(_currentRegion.center, 1.5);
                        },
                        child: const Icon(Icons.public, color: Colors.teal),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'city_view',
                        tooltip: _isSpanish
                            ? 'Enfocar datos PMTiles'
                            : 'Focus PMTiles Dataset',
                        backgroundColor: Colors.white,
                        onPressed: () {
                          _mapController.move(_currentRegion.center, 15.5);
                        },
                        child: const Icon(Icons.location_city,
                            color: Colors.black87),
                      ),
                    ],
                  ),
                ),

                // Bottom Attribute Panel & Attribution (CLEANLY ELEVATED OVER ANDROID SYSTEM BUTTONS)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: true, // Guarantees rendering above Android system navigation bar
                    left: false,
                    right: false,
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selectedFeature != null)
                          Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            elevation: 8,
                            shadowColor: Colors.black45,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header Row
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.shade50,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(Icons.apartment,
                                            color: Colors.teal, size: 24),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _currentRegion ==
                                                      DemoRegion.wellington
                                                  ? '${_isSpanish ? 'Edificio' : 'Building'} #${_selectedFeature!['building_i']}'
                                                  : _kindLabel(
                                                      _selectedFeature!['kind'],
                                                    ),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                            if (_lastTappedPoint != null)
                                              Text(
                                                '${_lastTappedPoint!.latitude.toStringAsFixed(5)}, ${_lastTappedPoint!.longitude.toStringAsFixed(5)}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: _isSpanish
                                            ? 'Cerrar'
                                            : 'Close',
                                        icon: const Icon(Icons.close,
                                            size: 20),
                                        onPressed: () {
                                          _selectionController.clear();
                                          setState(() =>
                                              _selectedFeature = null);
                                        },
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 18),

                                  // Primary metric: footprint area
                                  if (_selectedFeature!.coordinates !=
                                          null &&
                                      _selectedFeature!
                                          .coordinates!.isNotEmpty) ...[
                                    Text(
                                      _isSpanish
                                          ? 'Área aprox.'
                                          : 'Approx. area',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    Text(
                                      '${_calculateArea(_selectedFeature!.coordinates!).toStringAsFixed(0)} m²',
                                      style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],

                                  // Secondary metrics
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      if (_currentRegion ==
                                          DemoRegion.wellington) ...[
                                        _buildChip(
                                          _isSpanish ? 'Ciudad' : 'City',
                                          _selectedFeature!['town_city'],
                                        ),
                                        _buildChip(
                                          _isSpanish ? 'Barrio' : 'Suburb',
                                          _selectedFeature!['suburb_loc'],
                                        ),
                                        _buildChip(
                                          _isSpanish
                                              ? 'Distrito'
                                              : 'District',
                                          _selectedFeature!['territoria'],
                                        ),
                                        _buildChip(
                                          _isSpanish ? 'Uso' : 'Use',
                                          _selectedFeature!['use'],
                                        ),
                                      ],
                                      if (_heightOf(_selectedFeature!)
                                          case final height?) ...[
                                        _buildChip(
                                          _isSpanish ? 'Altura' : 'Height',
                                          '${_formatMeters(height)} m',
                                        ),
                                        _buildChip(
                                          _isSpanish
                                              ? 'Pisos aprox.'
                                              : 'Approx. floors',
                                          math.max(1, (height / 3).round()),
                                        ),
                                      ],
                                      _buildChip(
                                        _isSpanish
                                            ? 'Alt. mínima'
                                            : 'Min. height',
                                        _selectedFeature!['min_height'] !=
                                                null
                                            ? '${_selectedFeature!['min_height']} m'
                                            : null,
                                      ),
                                      // Perimeter of a single-tile outline;
                                      // stitched pieces would count tile seams.
                                      if (_selectedFeature!.tileCount == 1 &&
                                          _selectedFeature!.coordinates !=
                                              null &&
                                          _selectedFeature!
                                              .coordinates!.isNotEmpty)
                                        _buildChip(
                                          _isSpanish
                                              ? 'Perímetro'
                                              : 'Perimeter',
                                          '${_calculatePerimeter(_selectedFeature!.coordinates!.first).toStringAsFixed(0)} m',
                                        ),
                                      _buildChip(
                                        _isSpanish ? 'Forma' : 'Shape',
                                        _selectedFeature!.tileCount == 1
                                            ? (_isSpanish
                                                ? 'completa'
                                                : 'complete')
                                            : (_isSpanish
                                                ? 'unida de ${_selectedFeature!.tileCount} partes'
                                                : 'joined from ${_selectedFeature!.tileCount} parts'),
                                        color: _selectedFeature!.tileCount > 1
                                            ? Colors.green.shade50
                                            : Colors.blue.shade50,
                                        borderColor:
                                            _selectedFeature!.tileCount > 1
                                                ? Colors.green.shade300
                                                : Colors.blue.shade300,
                                      ),
                                    ],
                                  ),

                                  // Toggle Raw Attributes Accordion
                                  const SizedBox(height: 8),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () => setState(
                                        () => _showRawJson = !_showRawJson),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _showRawJson
                                                ? Icons.keyboard_arrow_up
                                                : Icons.keyboard_arrow_down,
                                            size: 18,
                                            color: Colors.teal.shade700,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _isSpanish
                                                ? (_showRawJson
                                                    ? 'Ocultar datos'
                                                    : 'Ver todos los datos (${_selectedFeature!.properties.length})')
                                                : (_showRawJson
                                                    ? 'Hide data'
                                                    : 'Show all data (${_selectedFeature!.properties.length})'),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.teal.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  if (_showRawJson) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      constraints: const BoxConstraints(
                                          maxHeight: 120),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: SingleChildScrollView(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: _selectedFeature!
                                              .properties.entries
                                              .map(
                                                (e) => Text(
                                                  '${e.key}: ${e.value}',
                                                  style: const TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 11,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                        // Legal & Data Attribution Bar
                        Container(
                          color: Colors.black.withValues(alpha: 0.8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  _currentRegion.attribution(_isSpanish),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildChip(
    String label,
    dynamic value, {
    Color? color,
    Color? borderColor,
  }) {
    if (value == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor ?? Colors.grey.shade300),
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

/// Sphere shading for the low-zoom globe: a soft highlight towards the
/// top-left light source and limb darkening along the clipped edge.
///
/// Must be placed inside the globe's clip so it shares its exact shape.
class _GlobeLighting extends StatelessWidget {
  const _GlobeLighting({required this.factor, required this.radius});

  /// Globe interpolation factor (0 = flat map, 1 = full globe).
  final double factor;

  /// Corner radius of the clipped globe container.
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LimbPainter(factor: factor, radius: radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.45, -0.5),
            radius: 0.9,
            colors: [
              Colors.white.withValues(alpha: 0.28 * factor),
              Colors.white.withValues(alpha: 0.07 * factor),
              Colors.white.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.35, 0.8],
          ),
        ),
      ),
    );
  }
}

/// Darkens a band along the container's rounded edge. The stroke is centered
/// on the edge and blurred; the parent clip keeps only its inner half.
class _LimbPainter extends CustomPainter {
  const _LimbPainter({required this.factor, required this.radius});

  final double factor;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (factor <= 0) return;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final band = size.shortestSide * 0.16;

    void stroke(double width, double alpha) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = Colors.black.withValues(alpha: alpha * factor)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.35),
      );
    }

    stroke(band * 2.4, 0.25); // wide, soft falloff
    stroke(band, 0.45); // dark limb right at the edge
  }

  @override
  bool shouldRepaint(_LimbPainter oldDelegate) =>
      oldDelegate.factor != factor || oldDelegate.radius != radius;
}
