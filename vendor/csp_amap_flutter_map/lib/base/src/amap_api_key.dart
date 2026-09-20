part of '../csp_amap_flutter_base.dart';

///高德开放平台api key配置
///
///申请key请到高德开放平台官网:https://lbs.amap.com/
///
///Android平台的key的获取请参考：https://lbs.amap.com/api/poi-sdk-android/develop/create-project/get-key/?sug_index=2
///
///iOS平台key的获取请参考：https://lbs.amap.com/api/poi-sdk-ios/develop/create-project/get-key/?sug_index=1
///
///HarmonyOS平台key的获取请参考：https://lbs.amap.com/api/harmonyosnext-map3d-sdk/guide/get-key
class AMapApiKey {
  //iOS平台的key
  final String? iosKey;

  //Android平台的key
  final String? androidKey;

  //HarmonyOS平台的key
  final String? ohosKey;

  ///构造AMapKeyConfig
  ///
  ///[iosKey] iOS平台的key
  ///
  ///[androidKey] Android平台的key
  ///
  ///[ohosKey] HarmonyOS平台的key
  const AMapApiKey({this.iosKey, this.androidKey, this.ohosKey});

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> json = <String, dynamic>{};

    void addIfPresent(String fieldName, dynamic value) {
      if (value != null) {
        json[fieldName] = value;
      }
    }

    addIfPresent('androidKey', androidKey);
    addIfPresent('iosKey', iosKey);
    addIfPresent('ohosKey', ohosKey);
    return json;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    final AMapApiKey typedOther = other as AMapApiKey;
    return androidKey == typedOther.androidKey &&
        iosKey == typedOther.iosKey &&
        ohosKey == typedOther.ohosKey;
  }

  @override
  int get hashCode => Object.hashAll([androidKey, iosKey, ohosKey]);

  @override
  String toString() {
    return 'AMapApiKey(androidKey: $androidKey, iosKey: $iosKey, ohosKey: $ohosKey)';
  }
}
