import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:csp_amap_flutter_map/csp_amap_flutter_map_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelCspAmapFlutterMap platform = MethodChannelCspAmapFlutterMap();
  const MethodChannel channel = MethodChannel('csp_amap_flutter_map');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
