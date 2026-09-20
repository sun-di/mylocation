import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:csp_amap_flutter_map/base/csp_amap_flutter_base.dart';
import 'package:csp_amap_flutter_map/csp_amap_flutter_map.dart';
import 'package:csp_amap_flutter_map_example/base_page.dart';
import 'package:flutter/material.dart';

class MarkerAddAfterMapPage extends BasePage {
  MarkerAddAfterMapPage(String title, String subTitle) : super(title, subTitle);

  @override
  Widget build(BuildContext context) => _Body();
}

class _Body extends StatefulWidget {
  @override
  _BodyState createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  static const LatLng defaultPosition = LatLng(39.909187, 116.397451);
  //需要先设置一个空的map赋值给AMapWidget的markers，否则后续无法添加marker
  final Map<String, Marker> _markers = <String, Marker>{};
  LatLng _currentLatLng = defaultPosition;

  // 添加回被删除的方法
  TextButton _createMyFloatButton(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        //文字颜色
        foregroundColor: WidgetStateProperty.all(Colors.white),
        //水波纹颜色
        overlayColor: WidgetStateProperty.all(Colors.blueAccent),
        //背景颜色
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          //设置按下时的背景颜色
          if (states.contains(WidgetState.pressed)) {
            return Colors.blueAccent;
          }
          //默认背景颜色
          return Colors.blue;
        }),
      ),
      child: Text(label),
    );
  }

  // 添加一个预览图片的方法
  void _addCustomMarkerImage() async {
    // 创建一个 GlobalKey 来获取 Widget 的渲染对象
    final GlobalKey repaintKey = GlobalKey();

    // 创建一个自定义的 Widget
    final Widget customWidget = RepaintBoundary(
      key: repaintKey,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 120,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.red,
            border: Border.all(color: Colors.white, width: 2),
            borderRadius: BorderRadius.circular(25),
          ),
          child: const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_on, color: Colors.white, size: 24.0),
                SizedBox(width: 3),
                Text(
                  '自定义标记',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // 首先将 Widget 添加到 Overlay 中进行渲染
    final OverlayState? overlayState = Overlay.of(context);
    final OverlayEntry entry = OverlayEntry(
      builder: (context) => Positioned(
        left: -1000, // 放在屏幕外
        top: -1000,
        child: customWidget,
      ),
    );

    overlayState?.insert(entry);

    // 等待下一帧完成渲染
    await Future.delayed(const Duration(milliseconds: 20));

    // 获取渲染对象并转换为图片
    final RenderRepaintBoundary? boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

    if (boundary == null) {
      entry.remove();
      return;
    }

    // 渲染为图片
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);

    // 使用完后移除 Overlay
    entry.remove();

    final Uint8List? bytes = byteData?.buffer.asUint8List();
    if (bytes != null) {
      final markerPosition =
          LatLng(_currentLatLng.latitude, _currentLatLng.longitude + 2 / 1000);
      final BitmapDescriptor bitmapDescriptor =
          BitmapDescriptor.fromBytes(bytes);
      final Marker marker = Marker(
        position: _currentLatLng,
        icon: bitmapDescriptor,
      );
      //调用setState触发AMapWidget的更新，从而完成marker的添加
      setState(() {
        _currentLatLng = markerPosition;
        //将新的marker添加到map里
        _markers[marker.id] = marker;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AMapWidget amap = AMapWidget(
      // //创建地图时，给marker属性赋值一个空的set，否则后续无法添加marker
      markers: Set<Marker>.of(_markers.values),
    );
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 10,
                child: amap,
              ),
              Expanded(
                flex: 1,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _createMyFloatButton('添加Widget标记', _addCustomMarkerImage),
                  ],
                ),
              ),
            ],
          ),
          // 预览层
        ],
      ),
    );
  }
}
