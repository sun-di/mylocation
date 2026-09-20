import 'package:csp_amap_flutter_map/base/csp_amap_flutter_base.dart';

class ConstConfig {
  static const AMapApiKey amapApiKeys = AMapApiKey(
      androidKey: '900f72eeee0f21e435cebb0ef155582a',
      iosKey: '4dfdec97b7bf0b8c13e94777103015a9',
      ohosKey:
          '00000000000000000000000000000000'); // TODO: 替换为高德开放平台申请的 HarmonyOS API Key
  static const AMapPrivacyStatement amapPrivacyStatement =
      AMapPrivacyStatement(hasContains: true, hasShow: true, hasAgree: true);
}
