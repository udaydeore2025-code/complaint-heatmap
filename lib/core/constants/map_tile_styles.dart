import 'package:flutter/material.dart';

class MapTileStyle {
  final String id;
  final String name;
  final String urlTemplate;
  final String description;
  final IconData icon;

  const MapTileStyle({
    required this.id,
    required this.name,
    required this.urlTemplate,
    required this.description,
    required this.icon,
  });

  static const MapTileStyle standardOsm = MapTileStyle(
    id: 'osm_standard',
    name: 'OpenStreetMap',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    description: 'Standard community cartography',
    icon: Icons.map_outlined,
  );

  static const MapTileStyle cartoVoyager = MapTileStyle(
    id: 'carto_voyager',
    name: 'Streets & POIs',
    urlTemplate: 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
    description: 'Detailed streets, buildings & landmarks',
    icon: Icons.layers_outlined,
  );

  static const MapTileStyle cartoDark = MapTileStyle(
    id: 'carto_dark',
    name: 'Dark Matter',
    urlTemplate: 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
    description: 'High-contrast dark mode for night operations',
    icon: Icons.dark_mode_outlined,
  );

  static const List<MapTileStyle> availableStyles = [
    standardOsm,
    cartoVoyager,
    cartoDark,
  ];
}

