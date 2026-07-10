/// Single source of truth for map tile configuration.
///
/// RATIONALE: We use flutter_map with raster tiles (Mapbox primary, OpenStreetMap
/// fallback) instead of the official `mapbox_maps_flutter` SDK. The official SDK
/// renders maps via native platform views and cannot host Flutter widgets as
/// markers — which would force us to convert our emoji markers, name labels, and
/// tap handlers into generated annotation images. By keeping flutter_map and
/// only swapping the tile URL, ALL existing marker/camera/label code stays 100%
/// intact.
///
/// To change the token or map style, edit this file only.
class MapboxConfig {
  MapboxConfig._();

  /// Mapbox access token supplied via --dart-define=MAPBOX_TOKEN.
  ///
  /// Falls back to empty string if not defined (OSM will be used instead).
  /// NOTE: If this token is rejected (HTTP 401 "Not Authorized - Invalid Token"),
  /// the TileLayer will fall back to OpenStreetMap automatically.
  static const String accessToken = String.fromEnvironment(
    'MAPBOX_TOKEN',
    defaultValue: '',
  );

  /// Mapbox style ID. `streets-v12` is the default road map style.
  /// Alternatives: `outdoors-v12`, `satellite-v9`, `dark-v11`, `light-v11`.
  static const String styleId = 'streets-v12';

  /// Mapbox raster tile URL template (compatible with flutter_map's TileLayer).
  static const String mapboxTileUrl =
      'https://api.mapbox.com/styles/v1/mapbox/$styleId/tiles/512/{z}/{x}/{y}@2x?access_token=$accessToken';

  /// OpenStreetMap fallback tile URL. Used when the Mapbox token is invalid or
  /// rate-limited. OSM is free, requires no token, and always works.
  static const String osmFallbackTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Package name sent in the HTTP `User-Agent` / attribution.
  static const String attributionPackage = 'com.glovo_mate.app';

  /// Maximum native zoom level. Mapbox serves up to z22; OSM up to z19.
  /// We use 19 (the OSM cap) so the fallback renders correctly at all zooms.
  static const int maxNativeZoom = 19;
}
