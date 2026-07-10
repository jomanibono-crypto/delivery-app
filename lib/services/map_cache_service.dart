import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/mapbox_config.dart';

/// Manages persistent map-tile caching using `flutter_cache_manager`.
///
/// We chose this approach (instead of FMTC/ObjectBox) because it has zero
/// Gradle/SDK compatibility issues while still providing on-disk caching
/// that survives app restarts. Tiles are cached for 30 days and served from
/// disk on repeat visits, so the map appears almost instantly for already-seen
/// areas.
///
/// The custom [TileProvider] checks the cache first; on a miss it downloads
/// from the network and stores the result for next time.
class MapCacheService {
  MapCacheService._();

  static final DefaultCacheManager _cache = DefaultCacheManager();

  /// Mapbox tile URL (used for pre-warming) — reads token from
  /// [MapboxConfig] which is sourced via --dart-define=MAPBOX_TOKEN.
  static const String _mapboxTileUrl = MapboxConfig.mapboxTileUrl;

  /// Build a caching [TileProvider] for the given URL template.
  /// Tiles are read from disk cache first, then network.
  static TileProvider tileProvider(String urlTemplate) {
    return _CachingTileProvider(urlTemplate, _cache);
  }

  /// Pre-warm tiles around [center] so the map screen loads instantly.
  /// Downloads a 3x3 grid at z14 around the user (9 tiles). Best-effort.
  static Future<void> preWarm(LatLng center) async {
    try {
      final z = 14;
      final n = math.pow(2, z).toDouble();
      final xTile = ((center.longitude + 180) / 360 * n).floor();
      final latRad = center.latitude * math.pi / 180;
      final yTile =
          ((1 - (math.log(math.sin(latRad) + math.tan(latRad))) / math.pi) /
                  2 *
                  n)
              .floor();

      var downloaded = 0;
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          final url = _mapboxTileUrl
              .replaceAll('{z}', z.toString())
              .replaceAll('{x}', (xTile + dx).toString())
              .replaceAll('{y}', (yTile + dy).toString());
          try {
            await _cache.getSingleFile(url);
            downloaded++;
          } catch (_) {
            // Skip failed tiles — pre-warming is best-effort.
          }
        }
      }
      debugPrint('[MapCache] Pre-warm done: $downloaded/9 tiles cached.');
    } catch (e) {
      debugPrint('[MapCache] Pre-warm skipped: $e');
    }
  }
}

/// A [TileProvider] that serves tiles from a persistent disk cache first,
/// falling back to the network on cache misses.
class _CachingTileProvider extends TileProvider {
  _CachingTileProvider(this._urlTemplate, this._cache);

  final String _urlTemplate;
  final DefaultCacheManager _cache;

  String _buildUrl(TileCoordinates coords) {
    return _urlTemplate
        .replaceAll('{z}', coords.z.toString())
        .replaceAll('{x}', coords.x.toString())
        .replaceAll('{y}', coords.y.toString());
  }

  @override
  ImageProvider getImage(TileCoordinates coords, TileLayer options) {
    final url = _buildUrl(coords);
    return _CachedTileImageProvider(url, _cache);
  }
}

/// [ImageProvider] that loads a tile from disk cache (if fresh) or network.
class _CachedTileImageProvider extends ImageProvider<_CachedTileImageProvider> {
  _CachedTileImageProvider(this.url, this._cache);

  final String url;
  final DefaultCacheManager _cache;

  @override
  Future<_CachedTileImageProvider> obtainKey(ImageConfiguration cfg) {
    return SynchronousFuture<_CachedTileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadBytes(key).then((bytes) async {
        final buffer = await ImmutableBuffer.fromUint8List(bytes);
        return decode(buffer);
      }),
      scale: 1.0,
    );
  }

  Future<Uint8List> _loadBytes(_CachedTileImageProvider key) async {
    try {
      final file = await key._cache.getSingleFile(key.url);
      final bytes = await file.readAsBytes();
      return bytes;
    } catch (e) {
      debugPrint('[MapCache] Tile load failed: $e');
      throw Exception('Failed to load tile: $e');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _CachedTileImageProvider && url == other.url;

  @override
  int get hashCode => url.hashCode;
}
