// JSON map styles aligned with the Waddify Redesign A palette
// (Ink #10233F, Nile #0E7C7B / #2FB5B3, Sand #F7F6F2) so routes and
// markers remain legible in light and dark mode.

/// Light Google Map style JSON matching Waddify Sand and Nile accents.
const String waddifyLightMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [{"color": "#F7F6F2"}]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#4B5563"}]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [{"color": "#FFFFFF"}]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text",
    "stylers": [{"visibility": "simplified"}]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry.fill",
    "stylers": [{"color": "#E6EFEA"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [{"color": "#FFFFFF"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#E5E7EB"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{"color": "#FDE6C4"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#F2C382"}]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{"color": "#CFE7E6"}]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#0E7C7B"}]
  }
]
''';

/// Dark Google Map style JSON matching Waddify Ink and Nile Light accents.
const String waddifyDarkMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [{"color": "#10233F"}]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#9CA3AF"}]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [{"color": "#10233F"}]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry.fill",
    "stylers": [{"color": "#15324E"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [{"color": "#172C4C"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#27426D"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{"color": "#20385E"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#2FB5B3"}]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{"color": "#0B192E"}]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#2FB5B3"}]
  }
]
''';
