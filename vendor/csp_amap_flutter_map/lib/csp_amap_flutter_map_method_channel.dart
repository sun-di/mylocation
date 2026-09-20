import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'csp_amap_flutter_map_platform_interface.dart';

/// An implementation of [CspAmapFlutterMapPlatform] that uses method channels.
class MethodChannelCspAmapFlutterMap extends CspAmapFlutterMapPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('csp_amap_flutter_map');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
