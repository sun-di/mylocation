import 'dart:math';

import 'package:csp_amap_flutter_map/base/csp_amap_flutter_base.dart';
import 'package:csp_amap_flutter_map/csp_amap_flutter_map.dart';
import 'package:csp_amap_flutter_map_example/base_page.dart';
import 'package:flutter/material.dart';

class MarkerAddWithMapPage extends BasePage {
  MarkerAddWithMapPage(String title, String subTitle) : super(title, subTitle);

  @override
  Widget build(BuildContext context) => _Body();
}

class _Body extends StatefulWidget {
  @override
  _BodyState createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  static const LatLng mapCenter = LatLng(39.909187, 116.397451);
  final Map<String, Marker> _initMarkerMap = <String, Marker>{};
  final BitmapDescriptor _markerIcon =
      BitmapDescriptor.fromIconPath('assets/end.png');
  @override
  Widget build(BuildContext context) {
    for (int i = 0; i < 10; i++) {
      LatLng position = LatLng(mapCenter.latitude + sin(i * pi / 12.0) / 20.0,
          mapCenter.longitude + cos(i * pi / 12.0) / 20.0);
      Marker marker = Marker(position: position, alpha: 1, icon: _markerIcon);
      _initMarkerMap[marker.id] = marker;
    }

    final AMapWidget amap = AMapWidget(
      markers: Set<Marker>.of(_initMarkerMap.values),
    );
    return Container(
      child: amap,
    );
  }
}
