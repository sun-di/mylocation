import 'package:csp_amap_flutter_map/base/csp_amap_flutter_base.dart';
import 'package:csp_amap_flutter_map/csp_amap_flutter_map.dart';
import 'package:csp_amap_flutter_map_example/base_page.dart';
import 'package:flutter/material.dart';

class PoiClickDemoPage extends BasePage {
  PoiClickDemoPage(String title, String subTitle) : super(title, subTitle);

  @override
  Widget build(BuildContext context) => const _Body();
}

class _Body extends StatefulWidget {
  const _Body({Key? key}) : super(key: key);

  @override
  _BodyState createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  Widget? _poiInfo;
  @override
  Widget build(BuildContext context) {
    final AMapWidget amap = AMapWidget(
      touchPoiEnabled: true,
      onPoiTouched: _onPoiTouched,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints.expand(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            child: amap,
          ),
          Positioned(
            top: 40,
            width: MediaQuery.of(context).size.width,
            height: 50,
            child: Container(
              child: _poiInfo,
            ),
          )
        ],
      ),
    );
  }

  Widget showPoiInfo(AMapPoi poi) {
    return Container(
      alignment: Alignment.center,
      color: const Color(0x8200CCFF),
      child: Text(
        '您点击了 ${poi.name}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  void _onPoiTouched(AMapPoi poi) {
    setState(() {
      _poiInfo = showPoiInfo(poi);
    });
  }
}
