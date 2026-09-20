import 'dart:convert';
import 'package:csp_amap_flutter_map_example/base_page.dart';
import 'package:csp_amap_flutter_map_example/widgets/amap_switch_button.dart';
import 'package:flutter/material.dart';
import 'package:csp_amap_flutter_map/csp_amap_flutter_map.dart';
import 'package:csp_amap_flutter_map/base/csp_amap_flutter_base.dart';

class PolylineDemoPage extends BasePage {
  PolylineDemoPage(String title, String subTitle) : super(title, subTitle);
  @override
  Widget build(BuildContext context) {
    return const _Body();
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<StatefulWidget> createState() => _State();
}

class _State extends State<_Body> {
  _State();

// Values when toggling polyline color
  int colorsIndex = 0;
  List<Color> colors = <Color>[
    Colors.purple,
    Colors.red,
    Colors.green,
    Colors.pink,
  ];
  final Map<String, Polyline> _polylines = <String, Polyline>{};
  String? selectedPolylineId;
  LatLng mapCenter = const LatLng(36.811483, 118.497235);
  final Map<String, Marker> _initMarkerMap = <String, Marker>{};
  final BitmapDescriptor _markerIcon =
      BitmapDescriptor.fromIconPath('assets/start.png');
  final BitmapDescriptor _markerIcon1 =
      BitmapDescriptor.fromIconPath('assets/end.png');
  void _onMapCreated(AMapController controller) {}
  List<LatLng> points = <LatLng>[];
  List<LatLng> _createPoints() {
    final List<LatLng> points = <LatLng>[];
    points.add(const LatLng(39.90403, 116.407525));
    points.add(const LatLng(31.238068, 121.501654));
    points.add(const LatLng(30.679879, 104.064855));
    return points;
  }

  void readJsonFileToMap() async {
    String jsonString =
        await DefaultAssetBundle.of(context).loadString("assets/map.json");
    Map<String, dynamic> jsonMap = jsonDecode(jsonString);
    String polylinesPositions = jsonMap['data']['polyline'];

    List<String> pointsString = polylinesPositions.split(';');
    for (String point in pointsString) {
      List<String> latLng = point.split(',');
      if (latLng.length == 2) {
        points.add(LatLng(double.parse(latLng[0]), double.parse(latLng[1])));
      }
    }
    final Polyline polyline = Polyline(
        color: Colors.red, width: 5, points: points, onTap: _onPolylineTapped);
    setState(() {
      _polylines[polyline.id] = polyline;
      LatLng position = points[0];
      mapCenter = points[(points.length ~/ 2).toInt()];
      Marker marker = Marker(
        position: position,
        alpha: 1,
        icon: _markerIcon,
        zIndex: 1,
        infoWindow: const InfoWindow(title: '起点', snippet: '起点起点起点起点起点起点起点起点'),
      );
      _initMarkerMap[marker.id] = marker;
      Marker marker1 = Marker(
          position: points.last,
          alpha: 1,
          icon: _markerIcon1,
          zIndex: 1,
          infoWindow:
              const InfoWindow(title: '终点', snippet: '终点终点终点终点终点终点终点终点终点'));
      _initMarkerMap[marker1.id] = marker1;
    });
  }

  void _add() {
    final Polyline polyline = Polyline(
        color: Colors.red,
        width: 10,
        points: _createPoints(),
        onTap: _onPolylineTapped);
    print('Polyline: ${polyline.toMap().toString()} 被添加了');
    setState(() {
      _polylines[polyline.id] = polyline;
    });
  }

  void _remove() {
    final Polyline? selectedPolyline = _polylines[selectedPolylineId];
    //有选中的Marker
    if (selectedPolyline != null) {
      setState(() {
        _polylines.remove(selectedPolylineId);
      });
    } else {
      print('无选中的Polyline，无法删除');
    }
  }

  void _changeWidth() {
    final Polyline selectedPolyline = _polylines[selectedPolylineId]!;
    //有选中的Polyline
    double currentWidth = selectedPolyline.width;
    if (currentWidth < 50) {
      currentWidth += 10;
    } else {
      currentWidth = 5;
    }

    setState(() {
      _polylines[selectedPolylineId!] =
          selectedPolyline.copyWith(widthParam: currentWidth);
    });
  }

  void _onPolylineTapped(String polylineId) {
    print('Polyline: $polylineId 被点击了');
    setState(() {
      selectedPolylineId = polylineId;
    });
  }

  Future<void> _changeDashLineType() async {
    final Polyline? polyline = _polylines[selectedPolylineId];
    if (polyline == null) {
      return;
    }
    DashLineType currentType = polyline.dashLineType;
    if (currentType.index < DashLineType.circle.index) {
      currentType = DashLineType.values[currentType.index + 1];
    } else {
      currentType = DashLineType.none;
    }

    setState(() {
      _polylines[selectedPolylineId!] =
          polyline.copyWith(dashLineTypeParam: currentType);
    });
  }

  void _changeCapType() {
    final Polyline polyline = _polylines[selectedPolylineId]!;
    CapType capType = polyline.capType;
    if (capType.index < CapType.round.index) {
      capType = CapType.values[capType.index + 1];
    } else {
      capType = CapType.butt;
    }
    setState(() {
      _polylines[selectedPolylineId!] =
          polyline.copyWith(capTypeParam: capType);
    });
  }

  void _changeJointType() {
    final Polyline polyline = _polylines[selectedPolylineId]!;
    JoinType joinType = polyline.joinType;
    if (joinType.index < JoinType.round.index) {
      joinType = JoinType.values[joinType.index + 1];
    } else {
      joinType = JoinType.bevel;
    }
    setState(() {
      _polylines[selectedPolylineId!] =
          polyline.copyWith(joinTypeParam: joinType);
    });
  }

  Future<void> _changeAlpha() async {
    final Polyline polyline = _polylines[selectedPolylineId]!;
    final double current = polyline.alpha;
    setState(() {
      _polylines[selectedPolylineId!] = polyline.copyWith(
        alphaParam: current < 0.1 ? 1.0 : current * 0.75,
      );
    });
  }

  Future<void> _toggleVisible(value) async {
    final Polyline polyline = _polylines[selectedPolylineId]!;
    setState(() {
      _polylines[selectedPolylineId!] = polyline.copyWith(
        visibleParam: value,
      );
    });
  }

  void _changeColor() {
    final Polyline polyline = _polylines[selectedPolylineId]!;
    setState(() {
      _polylines[selectedPolylineId!] = polyline.copyWith(
        colorParam: colors[++colorsIndex % colors.length],
      );
    });
  }

  void _changePoints() {
    final Polyline polyline = _polylines[selectedPolylineId]!;
    List<LatLng> currentPoints = polyline.points;
    List<LatLng> newPoints = <LatLng>[];
    newPoints.addAll(currentPoints);
    newPoints.add(const LatLng(39.835347, 116.34575));

    setState(() {
      _polylines[selectedPolylineId!] = polyline.copyWith(
        pointsParam: newPoints,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    // _add();
    readJsonFileToMap();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AMapWidget map = AMapWidget(
      onMapCreated: _onMapCreated,
      initialCameraPosition: CameraPosition(
        target: mapCenter,
        zoom: 5,
      ),
      markers: Set<Marker>.of(_initMarkerMap.values),
      polylines: Set<Polyline>.of(_polylines.values),
    );
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            width: MediaQuery.of(context).size.width,
            child: map,
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Column(
                        children: <Widget>[
                          TextButton(
                            onPressed: _add,
                            child: const Text('添加'),
                          ),
                          TextButton(
                            onPressed:
                                (selectedPolylineId == null) ? null : _remove,
                            child: const Text('删除'),
                          ),
                          TextButton(
                            onPressed: (selectedPolylineId == null)
                                ? null
                                : _changeWidth,
                            child: const Text('修改线宽'),
                          ),
                          TextButton(
                            onPressed: (selectedPolylineId == null)
                                ? null
                                : _changeAlpha,
                            child: const Text('修改透明度'),
                          ),
                          AMapSwitchButton(
                            label: const Text('显示'),
                            onSwitchChanged: (selectedPolylineId == null)
                                ? null
                                : _toggleVisible,
                            defaultValue: true,
                          ),
                        ],
                      ),
                      Column(
                        children: <Widget>[
                          TextButton(
                            onPressed: (selectedPolylineId == null)
                                ? null
                                : _changeColor,
                            child: const Text('修改颜色'),
                          ),
                          TextButton(
                            onPressed: (selectedPolylineId == null)
                                ? null
                                : _changeCapType,
                            child: const Text('修改线头样式'),
                          ),
                          TextButton(
                            onPressed: (selectedPolylineId == null)
                                ? null
                                : _changeJointType,
                            child: const Text('修改连接样式'),
                          ),
                          TextButton(
                            onPressed: (selectedPolylineId == null)
                                ? null
                                : _changeDashLineType,
                            child: const Text('修改虚线类型'),
                          ),
                          TextButton(
                            onPressed: (selectedPolylineId == null)
                                ? null
                                : _changePoints,
                            child: const Text('修改坐标'),
                          ),
                        ],
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
