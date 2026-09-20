import 'package:csp_amap_flutter_map/csp_amap_flutter_map.dart';
import 'package:csp_amap_flutter_map_example/base_page.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class MyLocationPage extends BasePage {
  // ignore: unused_element_parameter
  const MyLocationPage(super.title, super.subTitle, {super.key});
  @override
  Widget build(BuildContext context) => const _Body();
}

class _Body extends StatefulWidget {
  const _Body({super.key});
  @override
  _BodyState createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  @override
  void initState() {
    super.initState();
    _requestLocaitonPermission();
  }

  @override
  void reassemble() {
    super.reassemble();
    _requestLocaitonPermission();
  }

  void _requestLocaitonPermission() async {
    PermissionStatus status = await Permission.location.request();
    print('permissionStatus=====> $status');
  }

  @override
  Widget build(BuildContext context) {
    final AMapWidget amap = AMapWidget(
      myLocationStyleOptions: MyLocationStyleOptions(
        true,
        icon: BitmapDescriptor.defaultMarker,
      ),
    );
    return amap;
  }
}
