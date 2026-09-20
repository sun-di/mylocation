import 'package:flutter_test/flutter_test.dart';
import 'package:csp_amap_flutter_map/csp_amap_flutter_map_platform_interface.dart';
import 'package:csp_amap_flutter_map/csp_amap_flutter_map_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockCspAmapFlutterMapPlatform
    with MockPlatformInterfaceMixin
    implements CspAmapFlutterMapPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final CspAmapFlutterMapPlatform initialPlatform =
      CspAmapFlutterMapPlatform.instance;

  test('$MethodChannelCspAmapFlutterMap is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelCspAmapFlutterMap>());
  });

  test('getPlatformVersion', () async {
    MockCspAmapFlutterMapPlatform fakePlatform =
        MockCspAmapFlutterMapPlatform();
    CspAmapFlutterMapPlatform.instance = fakePlatform;

    expect(await CspAmapFlutterMapPlatform.instance.getPlatformVersion(), '42');
  });
}
